import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:zero_beat_rpc/engine_host.dart';

import 'audio_filters.dart';
import 'engine_player.dart';

enum HostEventKind { position, state, ended, failed }

class HostEvent {
  const HostEvent(this.kind, this.report);

  final HostEventKind kind;
  final EngineReport report;
}

class _Binding {
  _Binding({
    required this.playbackId,
    required this.request,
    required this.playWhenReady,
    required this.clipStartMs,
    required this.clipEndMs,
  });

  final String playbackId;
  final EngineLoad request;
  EnginePlayer? output;
  EnginePlayer get player => output!;
  bool playWhenReady;
  bool ready = false;
  int intentVersion = 0;
  int? pendingSeek;

  /// Original-timeline bounds from the engine.load that opened this binding.
  /// open(end:) reads clipEndMs once. Later clip edits must not assign these
  /// fields: position updates treat clipEndMs as the playback end and emit
  /// ended when position reaches it.
  int clipStartMs;
  int clipEndMs;
  bool disposed = false;
  bool stopRequested = false;
  bool terminal = false;
  bool buffering = false;
  int seq = 0;
  int positionMs = 0;
  int durationMs = 0;
  String state = 'idle';
}

/// Single owner of the live audio player.
///
/// Each load disposes the previous player before creating the next one.
/// Callbacks closed over the old player cannot emit for the replacement.
class PlaybackHost extends ChangeNotifier implements EngineHost {
  PlaybackHost({
    required EnginePlayer Function() createPlayer,
    bool enablePositionClock = true,
  }) : _createPlayer = createPlayer {
    if (enablePositionClock) {
      _timer = Timer.periodic(positionInterval, (_) => _onTick());
    }
  }

  static const positionInterval = Duration(milliseconds: 250);

  final EnginePlayer Function() _createPlayer;
  final List<HostEvent> events = [];
  final List<EngineReport> terminalEvents = [];

  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  _Binding? _binding;
  _Binding? _physical;
  bool _closed = false;

  Future<bool> Function()? acquireFocus;
  Future<void> Function()? releaseFocus;
  Future<void> Function()? abandonFocus;
  void Function()? onFocusDenied;
  String focusNotice = '';
  EngineReport _report = EngineReport(
    playbackId: null,
    seq: 0,
    state: 'idle',
    positionMs: 0,
    durationMs: 0,
  );
  double _volume = 0.8;
  double _compDb = 0;
  bool _autoGain = false;
  bool _loudnorm = false;
  String _loudnormNotice = '';

  String get loudnormNotice => _loudnormNotice;

  int get activeClipStartMs => _binding?.clipStartMs ?? 0;

  int get activeClipEndMs => _binding?.clipEndMs ?? 0;

  String? get activePlaybackId => _binding?.playbackId;

  /// Optional sink for position, state, ended, and failed reports.
  void Function(HostEvent event)? onEvent;

  @override
  List<String> get capabilities {
    final names = <String>['clip'];
    if (_loudnorm) names.add('loudnorm');
    return List.unmodifiable(names);
  }

  @override
  EngineReport reportState() => _report;

  /// Probes loudnorm on a throwaway player, then disposes it.
  Future<void> prepare() async {
    final EnginePlayer player;
    try {
      player = _createPlayer();
    } catch (_) {
      _markLoudnormUnavailable();
      return;
    }
    try {
      _loudnorm = await player.trySetFilter(kLoudnormFilter);
    } catch (_) {
      _loudnorm = false;
    } finally {
      await player.dispose();
    }
    if (!_loudnorm) _markLoudnormUnavailable();
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    await reset();
  }

  /// Invalidate immediately, including loads whose media open is still pending.
  Future<void> reset() async {
    final binding = _binding;
    if (binding != null) {
      binding.disposed = true;
      binding.stopRequested = true;
      binding.playWhenReady = false;
    }
    _binding = null;
    _report = EngineReport(
      playbackId: null,
      seq: 0,
      state: 'idle',
      positionMs: 0,
      durationMs: 0,
    );
    try {
      await _serialized(_disposePhysical);
    } finally {
      await (abandonFocus ?? releaseFocus)?.call();
    }
  }

  @override
  Future<void> load(EngineLoad request) async {
    if (_closed) throw StateError('播放器已关闭');
    if (request.playbackId.isEmpty || request.stream.url.isEmpty) {
      throw ArgumentError('播放参数无效');
    }
    final old = _binding;
    if (old != null) old.disposed = true;
    final binding = _Binding(
      playbackId: request.playbackId,
      request: request,
      playWhenReady: request.playWhenReady,
      clipStartMs: request.stream.clipStartMs,
      clipEndMs: request.stream.clipEndMs,
    );
    _binding = binding;
    notifyListeners();
    _volume = request.volume.clamp(0, 1).toDouble();
    _compDb = request.compDb;
    _autoGain = request.autoGain;
    _setState(binding, binding.playWhenReady ? 'buffering' : 'paused');
    // Only lifecycle work is serialized. Network open must never occupy it.
    unawaited(
      _serialized(() async {
        await _disposePhysical();
        if (!_alive(binding)) return;
        binding.output = _createPlayer();
        _physical = binding;
        binding.player.listen(
          EnginePlayerListener(
            onPosition: (position, duration) =>
                _onPosition(binding, position, duration),
            onPlaying: (playing) => _onPlaying(binding, playing),
            onBuffering: (buffering) => _onBuffering(binding, buffering),
            onCompleted: () => _onCompleted(binding),
            onError: (message) => _onError(binding, message),
          ),
        );
        unawaited(_open(binding));
      }).catchError((Object error) {
        if (_alive(binding)) _fail(binding, '$error');
      }),
    );
  }

  @override
  Future<void> pause(String playbackId) async {
    final binding = _current(playbackId);
    if (binding == null) return;
    binding.playWhenReady = false;
    final version = ++binding.intentVersion;
    _setState(binding, 'paused');
    if (binding.ready && _alive(binding)) await binding.player.pause();
    if (_alive(binding) && version == binding.intentVersion) {
      await releaseFocus?.call();
    }
  }

  @override
  Future<void> resume(String playbackId) async {
    final binding = _current(playbackId);
    if (binding == null) return;
    binding.playWhenReady = true;
    binding.intentVersion++;
    _setState(binding, 'buffering');
    if (binding.ready) await _applyIntent(binding);
  }

  @override
  Future<void> stop(String playbackId) async {
    final binding = _current(playbackId);
    if (binding == null) return;
    await reset();
  }

  @override
  Future<void> seek(String playbackId, int positionMs) async {
    final binding = _current(playbackId);
    if (binding == null) return;
    binding.pendingSeek = positionMs;
    if (!binding.ready) return;
    await binding.player.seek(Duration(milliseconds: positionMs));
    if (!_alive(binding)) return;
    binding.positionMs = positionMs;
    binding.pendingSeek = null;
    await _applyIntent(binding);
  }

  @override
  Future<void> volume(String playbackId, double volume) async {
    if (!_accepts(playbackId)) return;
    _volume = volume.clamp(0, 1).toDouble();
    final binding = _binding;
    if (binding != null && binding.ready) await _applyOutput(binding);
  }

  @override
  Future<void> compensation(String playbackId, double compDb) async {
    if (!_accepts(playbackId)) return;
    _compDb = compDb;
    final binding = _binding;
    if (binding != null && binding.ready) await _applyOutput(binding);
  }

  @override
  Future<void> autoGain(String playbackId, bool enabled) async {
    if (!_accepts(playbackId)) return;
    _autoGain = enabled;
    final binding = _binding;
    if (binding != null && binding.ready) await _applyOutput(binding);
  }

  Future<void> _open(_Binding binding) async {
    final request = binding.request;
    try {
      await _applyOutput(binding);
      if (!_alive(binding)) return;
      final startMs = _startMs(request);
      await binding.player.open(
        url: request.stream.url,
        headers: request.stream.headers,
        start: startMs > 0 ? Duration(milliseconds: startMs) : null,
        // Same end [_onPosition] will use for this binding. Core replaces
        // both by sending a new engine.load; this open is not rewritten.
        end: binding.clipEndMs > 0
            ? Duration(milliseconds: binding.clipEndMs)
            : null,
        play: false,
      );
      if (!_alive(binding)) return;
      await _applyOutput(binding);
      if (!_alive(binding)) return;
      final seek = binding.pendingSeek;
      if (seek != null) {
        await binding.player.seek(Duration(milliseconds: seek));
        binding.pendingSeek = null;
      }
      if (!_alive(binding)) return;
      binding.ready = true;
      await _applyIntent(binding);
    } catch (error) {
      if (_alive(binding)) _fail(binding, '$error');
    }
  }

  Future<void> _applyIntent(_Binding binding) async {
    if (!_alive(binding) || !binding.ready || binding.terminal) return;
    final version = binding.intentVersion;
    if (!binding.playWhenReady) {
      await binding.player.pause();
      if (_alive(binding) && version == binding.intentVersion) {
        await releaseFocus?.call();
      }
      if (_alive(binding) && !binding.playWhenReady) {
        _setState(binding, 'paused');
      }
      return;
    }
    final allowed = await acquireFocus?.call() ?? true;
    if (!_alive(binding) ||
        version != binding.intentVersion ||
        !binding.playWhenReady) {
      return;
    }
    if (!allowed) {
      binding.playWhenReady = false;
      focusNotice = '未获得音频焦点，播放已暂停';
      notifyListeners();
      _setState(binding, 'paused');
      // Do not wait on a reverse RPC from within an engine RPC command.
      onFocusDenied?.call();
      return;
    }
    if (focusNotice.isNotEmpty) {
      focusNotice = '';
      notifyListeners();
    }
    await binding.player.play();
    if (_alive(binding) &&
        version == binding.intentVersion &&
        binding.playWhenReady) {
      _setState(binding, binding.buffering ? 'buffering' : 'playing');
    }
  }

  int _startMs(EngineLoad request) {
    var at = request.startAtMs;
    final clipStart = _binding?.clipStartMs ?? request.stream.clipStartMs;
    if (clipStart > 0 && at < clipStart) at = clipStart;
    return at;
  }

  Future<void> _applyOutput(_Binding binding) async {
    final wantLoudnorm = _autoGain && _loudnorm;
    var loudnormApplied = false;
    if (wantLoudnorm) {
      loudnormApplied = await binding.player.trySetFilter(kLoudnormFilter);
      if (!loudnormApplied) _markLoudnormUnavailable();
    }
    var limiterApplied = false;
    if (_compDb != 0) {
      final chain = playbackFilter(loudnorm: loudnormApplied, compDb: _compDb);
      limiterApplied = await binding.player.trySetFilter(chain);
      if (!limiterApplied && loudnormApplied) {
        loudnormApplied = await binding.player.trySetFilter(kLoudnormFilter);
      }
    }
    final percent = _outputPercent(limiterApplied: limiterApplied);
    await binding.player.setVolume(percent);
  }

  double _outputPercent({required bool limiterApplied}) {
    if (limiterApplied || _compDb == 0) {
      return _volume.clamp(0, 1) * 100;
    }
    final gain = math.pow(10, _compDb / 20).toDouble();
    return (_volume * gain).clamp(0, 1) * 100;
  }

  void _onTick() {
    final binding = _binding;
    if (binding == null || !_alive(binding) || binding.terminal) return;
    if (binding.state == 'idle') return;
    _emit(binding, HostEventKind.position, binding.state);
  }

  void _onPosition(_Binding binding, Duration position, Duration duration) {
    if (!_alive(binding) || binding.terminal) return;
    binding.positionMs = position.inMilliseconds;
    if (duration > Duration.zero) {
      binding.durationMs = duration.inMilliseconds;
    }
    final end = binding.clipEndMs;
    if (end > 0 && binding.positionMs >= end) {
      _finishClip(binding);
    }
  }

  void _onPlaying(_Binding binding, bool playing) {
    if (!_alive(binding) || binding.terminal || binding.stopRequested) return;
    if (!binding.playWhenReady && playing) {
      unawaited(binding.player.pause());
      return;
    }
    if (!binding.ready) return;
    if (!binding.playWhenReady) {
      _setState(binding, 'paused');
    } else if (binding.buffering) {
      _setState(binding, 'buffering');
    } else {
      _setState(binding, playing ? 'playing' : 'paused');
    }
  }

  void _onBuffering(_Binding binding, bool buffering) {
    if (!_alive(binding) || binding.terminal) return;
    binding.buffering = buffering;
    if (!binding.playWhenReady) {
      _setState(binding, 'paused');
      return;
    }
    if (buffering || !binding.ready) {
      _setState(binding, 'buffering');
      return;
    }
    _setState(binding, binding.playWhenReady ? 'playing' : 'paused');
  }

  void _onCompleted(_Binding binding) {
    if (!_alive(binding) || binding.stopRequested || binding.terminal) return;
    binding.terminal = true;
    _emit(binding, HostEventKind.ended, 'ended');
    unawaited(releaseFocus?.call());
  }

  void _onError(_Binding binding, String message) {
    if (!_alive(binding) || binding.terminal || message.isEmpty) return;
    _fail(binding, message);
  }

  void _finishClip(_Binding binding) {
    if (!_alive(binding) || binding.terminal || binding.stopRequested) return;
    binding.terminal = true;
    binding.stopRequested = true;
    _emit(binding, HostEventKind.ended, 'ended');
    unawaited(releaseFocus?.call());
    unawaited(binding.player.stop());
  }

  void _fail(_Binding binding, String message) {
    if (binding.terminal) return;
    binding.terminal = true;
    _emit(binding, HostEventKind.failed, 'failed', error: message);
    unawaited(releaseFocus?.call());
  }

  void _setState(_Binding binding, String state) {
    if (!_alive(binding) || binding.state == state) return;
    binding.state = state;
    _emit(binding, HostEventKind.state, state);
  }

  void _emit(
    _Binding binding,
    HostEventKind kind,
    String state, {
    String error = '',
  }) {
    if (!_alive(binding)) return;
    binding.seq += 1;
    binding.state = state;
    final report = EngineReport(
      playbackId: binding.playbackId,
      seq: binding.seq,
      state: state,
      positionMs: binding.positionMs,
      durationMs: binding.durationMs,
      error: error,
    );
    final event = HostEvent(kind, report);
    if (kind == HostEventKind.position &&
        events.isNotEmpty &&
        events.last.kind == HostEventKind.position) {
      events[events.length - 1] = event;
    } else {
      events.add(event);
    }
    _report = report;
    if (kind == HostEventKind.ended || kind == HostEventKind.failed) {
      terminalEvents.add(report);
    }
    if (events.length > 256) events.removeRange(0, events.length - 256);
    if (terminalEvents.length > 32) terminalEvents.removeAt(0);
    final sink = onEvent;
    if (sink != null) sink(event);
  }

  bool _accepts(String playbackId) {
    final binding = _binding;
    if (binding == null) return true;
    return binding.playbackId == playbackId;
  }

  _Binding? _current(String playbackId) {
    final binding = _binding;
    if (binding == null ||
        binding.playbackId != playbackId ||
        !_alive(binding)) {
      return null;
    }
    return binding;
  }

  bool _alive(_Binding binding) =>
      !binding.disposed && identical(_binding, binding);

  Future<void> _disposePhysical() async {
    final binding = _physical;
    if (binding == null) return;
    binding.disposed = true;
    binding.stopRequested = true;
    // Keep ownership until disposal completes; never overlap native players.
    await binding.player.dispose();
    _physical = null;
  }

  void _markLoudnormUnavailable() {
    _loudnorm = false;
    if (_loudnormNotice.isNotEmpty) return;
    _loudnormNotice = '当前播放器无法启用响度均衡';
    notifyListeners();
  }

  Future<void> _serialized(Future<void> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }
}
