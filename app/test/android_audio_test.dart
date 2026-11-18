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
}
