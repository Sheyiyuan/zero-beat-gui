import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/core/audio_focus.dart';
import 'package:zero_beat_gui/core/interruption_policy.dart';
import 'package:zero_beat_gui/platform/android_audio.dart';
import 'package:zero_beat_gui/shared/playback.dart';

import 'support/fake_core.dart';
import 'support/samples.dart';

void main() {
  test('system stop cancels interruption resume and releases focus', () async {
    final api = FakeCoreApi();
    final policy = InterruptionPolicy()..onBegin(active: true);
    final focusChanges = <bool>[];
    final focus = AudioFocusCoordinator((active) async {
      focusChanges.add(active);
      return true;
    });
    final handler = ZeroAudioHandler(api, policy, focus);
    addTearDown(handler.shutdown);
    addTearDown(api.closeControllers);
    await focus.acquire();
    focus.interrupted = true;

    await handler.stop();

    expect(api.stops, 1);
    expect(api.pauses, 0);
    expect(api.quits, 0);
    expect(policy.shouldResume(temporary: true), isFalse);
    expect(focusChanges, [true, false]);
  });

  test('stopped snapshot leaves media service idle, pause remains ready', () {
    final api = FakeCoreApi();
    final handler = ZeroAudioHandler(
      api,
      InterruptionPolicy(),
      AudioFocusCoordinator((_) async => true),
    );
    addTearDown(handler.shutdown);
    addTearDown(api.closeControllers);
    final song = sampleSong();
    handler.publish(
      playerView(
        current: song,
        state: PlaybackStatus.valuePlaying,
        playWhenReady: true,
      ),
    );
    expect(handler.playbackState.value.playing, isTrue);
    handler.publish(
      playerView(current: song, state: PlaybackStatus.valuePaused),
    );
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
    handler.publish(playerView());
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    expect(
      handler.playbackState.value.systemActions,
      contains(MediaAction.stop),
    );
  });

  test('system play restarts retained queue after stop', () async {
    final api = FakeCoreApi();
    final handler = ZeroAudioHandler(
      api,
      InterruptionPolicy(),
      AudioFocusCoordinator((_) async => true),
    );
    addTearDown(handler.shutdown);
    addTearDown(api.closeControllers);
    handler.publish(playerView());
    await handler.play();
    expect(api.toggles, 0);
    expect(api.resumes, 1);
    handler.publish(
      playerView(current: sampleSong(), state: PlaybackStatus.valuePaused),
    );
    await handler.play();
    expect(api.toggles, 0);
    expect(api.resumes, 2);
  });

  test('media controls keep transport compact and expose restart/mode', () {
    final api = FakeCoreApi();
    final handler = ZeroAudioHandler(
      api,
      InterruptionPolicy(),
      AudioFocusCoordinator((_) async => true),
    );
    addTearDown(handler.shutdown);
    addTearDown(api.closeControllers);
    handler.publish(
      playerView(
        current: sampleSong(),
        state: PlaybackStatus.valuePaused,
        mode: PlaybackMode.valueLoopOne,
      ),
    );

    final state = handler.playbackState.value;
    expect(state.androidCompactActionIndices, [0, 1, 2]);
    expect(state.controls.take(3).map((control) => control.action).toList(), [
      MediaAction.skipToPrevious,
      MediaAction.play,
      MediaAction.skipToNext,
    ]);
    expect(
      state.controls
          .map((control) => control.customAction?.name)
          .whereType<String>(),
      containsAll([
        ZeroAudioHandler.restartAction,
        ZeroAudioHandler.cycleModeAction,
      ]),
    );
    expect(state.repeatMode, AudioServiceRepeatMode.one);
    expect(state.shuffleMode, AudioServiceShuffleMode.none);
    expect(
      state.systemActions,
      containsAll([
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
        MediaAction.seek,
      ]),
    );
  });

  test('restart control seeks to zero without changing play state', () async {
    final api = FakeCoreApi();
    final handler = ZeroAudioHandler(
      api,
      InterruptionPolicy(),
      AudioFocusCoordinator((_) async => true),
    );
    addTearDown(handler.shutdown);
    addTearDown(api.closeControllers);
    handler.publish(
      playerView(
        current: sampleSong(),
        state: PlaybackStatus.valuePlaying,
        positionMs: 42000,
        playWhenReady: true,
      ),
    );

    await handler.customAction(ZeroAudioHandler.restartAction);

    expect(api.seekPositions, [0]);
    expect(api.pauses, 0);
    expect(api.resumes, 0);
    expect(api.toggles, 0);
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('mode control cycles list, one, shuffle and ordered', () async {
    final api = FakeCoreApi();
    final handler = ZeroAudioHandler(
      api,
      InterruptionPolicy(),
      AudioFocusCoordinator((_) async => true),
    );
    addTearDown(handler.shutdown);
    addTearDown(api.closeControllers);
    var mode = PlaybackMode.valueListLoop;
    for (final want in [
      PlaybackMode.valueLoopOne,
      PlaybackMode.valueShuffle,
      PlaybackMode.valueOrdered,
      PlaybackMode.valueListLoop,
    ]) {
      handler.publish(
        playerView(
          current: sampleSong(),
          state: PlaybackStatus.valuePaused,
          mode: mode,
        ),
      );
      await handler.customAction(ZeroAudioHandler.cycleModeAction);
      expect(api.modes.last, want.value);
      mode = want;
    }
    expect(ZeroAudioHandler.nextPlaybackMode('unexpected'), 'list_loop');
  });

  test('standard repeat and shuffle controls map onto app modes', () async {
    final api = FakeCoreApi();
    final handler = ZeroAudioHandler(
      api,
      InterruptionPolicy(),
      AudioFocusCoordinator((_) async => true),
    );
    addTearDown(handler.shutdown);
    addTearDown(api.closeControllers);

    handler.publish(playerView(mode: PlaybackMode.valueListLoop));
    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    expect(api.modes, ['loop_one']);

    handler.publish(playerView(mode: PlaybackMode.valueLoopOne));
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    expect(api.modes.last, 'list_loop');

    handler.publish(playerView(mode: PlaybackMode.valueListLoop));
    await handler.setRepeatMode(AudioServiceRepeatMode.none);
    expect(api.modes.last, 'ordered');

    handler.publish(playerView(mode: PlaybackMode.valueOrdered));
    await handler.setShuffleMode(AudioServiceShuffleMode.all);
    expect(api.modes.last, 'shuffle');

    handler.publish(playerView(mode: PlaybackMode.valueShuffle));
    await handler.setShuffleMode(AudioServiceShuffleMode.none);
    expect(api.modes.last, 'ordered');

    // 标准面板关闭随机时恢复进入随机前的模式，而不是固定顺序播放。
    handler.publish(playerView(mode: PlaybackMode.valueLoopOne));
    await handler.setShuffleMode(AudioServiceShuffleMode.all);
    expect(api.modes.last, 'shuffle');
    handler.publish(playerView(mode: PlaybackMode.valueShuffle));
    await handler.setShuffleMode(AudioServiceShuffleMode.none);
    expect(api.modes.last, 'loop_one');

    // 随机状态下 repeat=none 只表示“不额外重复”，不能把随机关掉。
    handler.publish(playerView(mode: PlaybackMode.valueShuffle));
    final calls = api.modes.length;
    await handler.setRepeatMode(AudioServiceRepeatMode.none);
    expect(api.modes, hasLength(calls));

    // 标准面板可能重复上报同一模式；不要产生多余 RPC。
    handler.publish(playerView(mode: PlaybackMode.valueOrdered));
    final orderedCalls = api.modes.length;
    await handler.setShuffleMode(AudioServiceShuffleMode.none);
    expect(api.modes, hasLength(orderedCalls));
  });
}
