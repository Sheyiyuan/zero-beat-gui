import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../core/interruption_policy.dart';
import '../core/audio_focus.dart';

/// Notification and headset controls. Every transport call goes to [CoreApi].
class ZeroAudioHandler extends BaseAudioHandler with SeekHandler {
  ZeroAudioHandler(this.api, this.policy, this.focus);

  CoreApi api;
  AudioFocusCoordinator focus;
  InterruptionPolicy policy;
  PlayerView? _view;
  StreamSubscription<PlayerView>? _states;
  StreamSubscription<void>? _noisy;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;

  void bindPlayback() {
    _states ??= api.states.listen(publish);
    unawaited(api.playerState().then(publish, onError: (_) {}));
  }

  Future<void> rebind(CoreApi next) async {
    await _states?.cancel();
    _states = null;
    api = next;
    bindPlayback();
  }

  void _run(Future<void> action) {
    unawaited(action.catchError((Object _) {}));
  }

  Future<void> bindSession(AudioSession session) async {
    await _noisy?.cancel();
    await _interruptions?.cancel();
    _noisy = session.becomingNoisyEventStream.listen((_) {
      policy.blockResume();
      focus.interrupted = false;
      _run(focus.release());
      _run(api.pause());
    });
    _interruptions = session.interruptionEventStream.listen((event) {
      final temporary =
          event.type == AudioInterruptionType.pause ||
          event.type == AudioInterruptionType.duck;
      if (event.begin) {
        if (!focus.interrupted) policy.onBegin(active: _active);
        focus.interrupted = temporary;
        if (!temporary) policy.blockResume();
        _run(api.pause());
        return;
      }
      focus.interrupted = false;
      if (policy.shouldResume(temporary: temporary)) {
        _run(api.resume());
      } else {
        _run(focus.release());
      }
    });
  }

  bool get _active {
    final view = _view;
    if (view == null) return false;
    return view.playWhenReady ||
        view.snapshot.state == PlaybackStatus.valuePlaying;
  }

  void publish(PlayerView view) {
    _view = view;
    final song = view.snapshot.current;
    if (song != null) {
      final cover = Uri.tryParse(song.cover);
      mediaItem.add(
        MediaItem(
          id: song.id,
          title: song.title.isEmpty ? '未命名' : song.title,
          artist: song.artist,
          album: song.album,
          duration: Duration(milliseconds: view.snapshot.durationMs),
          artUri: cover != null && cover.hasScheme ? cover : null,
        ),
      );
    } else {
      mediaItem.add(null);
    }
    final playing = view.snapshot.state == PlaybackStatus.valuePlaying;
    final buffering = view.snapshot.state == PlaybackStatus.valueBuffering;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.stop,
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: view.snapshot.state == PlaybackStatus.valueIdle
            ? AudioProcessingState.idle
            : buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: Duration(milliseconds: view.snapshot.positionMs),
        speed: playing ? 1 : 0,
      ),
    );
  }

  @override
  Future<void> play() {
    policy.noteUserTransport();
    focus.interrupted = false;
    return api.resume();
  }

  @override
  Future<void> pause() {
    policy.noteUserTransport();
    focus.interrupted = false;
    return api.pause();
  }

  @override
  Future<void> stop() async {
    policy.noteUserTransport();
    focus.interrupted = false;
    try {
      await api.stop();
    } finally {
      await focus.release();
    }
  }

  @override
  Future<void> skipToNext() {
    policy.noteUserTransport();
    focus.interrupted = false;
    return api.next();
  }

  @override
  Future<void> skipToPrevious() {
    policy.noteUserTransport();
    focus.interrupted = false;
    return api.previous();
  }

  @override
  Future<void> seek(Duration position) {
    policy.noteUserTransport();
    focus.interrupted = false;
    return api.seek(position.inMilliseconds);
  }

  Future<void> shutdown() async {
    await _states?.cancel();
    _states = null;
    await _noisy?.cancel();
    await _interruptions?.cancel();
    await focus.close();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }
}

Future<ZeroAudioHandler> startAndroidAudio({
  required CoreApi api,
  required InterruptionPolicy policy,
  required AudioFocusCoordinator focus,
}) async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  final handler = await AudioService.init(
    builder: () => ZeroAudioHandler(api, policy, focus),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.sheyiyuan.zero_beat_gui.playback',
      androidNotificationChannelName: '零拍播放',
      androidNotificationChannelDescription: '播放与切歌',
      androidStopForegroundOnPause: true,
    ),
  );
  handler.bindPlayback();
  await handler.bindSession(session);
  return handler;
}
