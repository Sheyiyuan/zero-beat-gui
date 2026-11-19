import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../core/interruption_policy.dart';
import '../core/audio_focus.dart';
import '../shared/cover_art.dart';

/// Notification and headset controls. Every transport call goes to [CoreApi].
class ZeroAudioHandler extends BaseAudioHandler with SeekHandler {
  ZeroAudioHandler(this.api, this.policy, this.focus);

  /// 自定义媒体动作名，和 [customAction] 的分支一一对应。
  static const restartAction = 'restart';
  static const cycleModeAction = 'cycle_mode';

  // Android 13 起系统媒体面板会从 PlaybackState 读取自定义动作（具体显示
  // 位置由系统决定）；Android 12 及更早的 MediaStyle 通知不会把自定义动作
  // 渲染成按钮，只能显示标准传输动作。把两个自定义动作放在上一首/播放/
  // 下一首之后，并显式固定 compact 索引，旧系统的锁屏和通知不会因此丢掉
  // 最常用的三个按钮。旧系统无法把自定义动作画成通知按钮时：从头播放可
  // 退化为把通知进度条（MediaAction.seek）拖到 0，播放模式可退化为系统的
  // repeat/shuffle 控件；MediaSession 自定义动作也仍可被车机、蓝牙扩展和
  // 媒体控制器调用。
  static final _restartControl = MediaControl.custom(
    name: restartAction,
    label: '从头播放',
    // Use audio_service's built-in drawable so resource shrinking cannot
    // remove the name before getIdentifier() resolves it.
    androidIcon: 'drawable/audio_service_fast_rewind',
  );
  static final _cycleModeControl = MediaControl.custom(
    name: cycleModeAction,
    label: '切换播放模式',
    androidIcon: 'drawable/audio_service_fast_forward',
  );

  CoreApi api;
  AudioFocusCoordinator focus;
  InterruptionPolicy policy;
  PlayerView? _view;
  String? _modeBeforeShuffle;
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
      final cover = Uri.tryParse(coverImageUrl(song.cover));
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
    final mode = view.snapshot.mode.value;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          _restartControl,
          _cycleModeControl,
        ],
        // 旧版 Android 只认前三个 compact 按钮；固定成上一首/播放/下一首，
        // 防止新增的自定义动作在通知栏把播放键挤出去。
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.stop,
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          // 标准重复/随机模式让 Android 13+ 的系统面板可以显示原生循环/随机
          // 控件；应用自己的四模式切换另由 cycleModeAction 精确处理。
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
        },
        repeatMode: _repeatModeFor(mode),
        shuffleMode: _shuffleModeFor(mode),
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

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case restartAction:
        // 从头播放只 seek 到 0，不调用 pause/resume，保持当前播放状态。
        policy.noteUserTransport();
        focus.interrupted = false;
        return api.seek(0);
      case cycleModeAction:
        policy.noteUserTransport();
        focus.interrupted = false;
        return _cycleMode();
    }
    return super.customAction(name, extras);
  }

  Future<void> _cycleMode() async {
    var view = _view;
    if (view == null) {
      view = await api.playerState();
      publish(view);
    }
    await api.setMode(nextPlaybackMode(view.snapshot.mode.value));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // Android 的重复模式是独立属性；应用只有四个互斥模式，因此一次写入
    // 会明确落到其中一个模式。随机开启时系统仍可单独关闭随机。
    switch (repeatMode) {
      case AudioServiceRepeatMode.one:
        await _setMode('loop_one');
      case AudioServiceRepeatMode.all:
        await _setMode('list_loop');
      case AudioServiceRepeatMode.none:
        // 随机是一种独立的应用模式；系统同时把 repeat 设为 none 时不应
        // 把随机关掉，只有非随机状态才落到“顺序播放”。
        if (_view?.snapshot.mode.value != 'shuffle') {
          await _setMode('ordered');
        }
      case AudioServiceRepeatMode.group:
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    switch (shuffleMode) {
      case AudioServiceShuffleMode.all:
        await _setMode('shuffle');
      case AudioServiceShuffleMode.none:
        if (_view?.snapshot.mode.value == 'shuffle') {
          // 标准面板只是关闭随机；恢复进入随机前的模式，拿不到就回列表循环。
          await _setMode(_modeBeforeShuffle ?? 'list_loop');
        }
      case AudioServiceShuffleMode.group:
        break;
    }
  }

  Future<void> _setMode(String mode) async {
    final current = _view?.snapshot.mode.value;
    if (current == mode) return;
    if (mode == 'shuffle' && current != null) {
      _modeBeforeShuffle = current;
    }
    policy.noteUserTransport();
    focus.interrupted = false;
    await api.setMode(mode);
  }

  static String nextPlaybackMode(String mode) => switch (mode) {
    'list_loop' => 'loop_one',
    'loop_one' => 'shuffle',
    'shuffle' => 'ordered',
    _ => 'list_loop',
  };

  static AudioServiceRepeatMode _repeatModeFor(String mode) => switch (mode) {
    'loop_one' => AudioServiceRepeatMode.one,
    'ordered' || 'shuffle' => AudioServiceRepeatMode.none,
    _ => AudioServiceRepeatMode.all,
  };

  static AudioServiceShuffleMode _shuffleModeFor(String mode) =>
      mode == 'shuffle'
      ? AudioServiceShuffleMode.all
      : AudioServiceShuffleMode.none;

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
