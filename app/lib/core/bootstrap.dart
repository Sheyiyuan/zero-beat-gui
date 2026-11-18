import 'dart:io';
import 'dart:async';
import 'package:audio_session/audio_session.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zero_beat_rpc/client.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../engine/media_kit_engine_player.dart';
import '../engine/playback_host.dart';
import '../platform/android_audio.dart';
import 'interruption_policy.dart';
import 'audio_focus.dart';
import 'native_start.dart';

class StartedCore {
  StartedCore({
    required this.api,
    required this.host,
    required this.policy,
    required this.platform,
  });

  final CoreApi api;
  final PlaybackHost host;
  final InterruptionPolicy policy;
  final String platform;
}

/// Process-wide core startup. A second activity reuses the same future.
class CoreRuntime {
  CoreRuntime._();

  static final instance = CoreRuntime._();

  Future<StartedCore>? _pending;
  Future<void>? _closing;
  NativeCore? _native;
  StartedCore? _started;
  ZeroAudioHandler? _audio;
  AudioFocusCoordinator? _focus;

  Future<StartedCore> reconnect() {
    if (_closing != null) return _closing!.then((_) => ensureStarted());
    final running = _pending;
    if (running != null) return running;
    late final Future<StartedCore> run;
    run = _reconnect().whenComplete(() {
      if (identical(_pending, run)) _pending = null;
    });
    return _pending = run;
  }

  Future<StartedCore> _reconnect() async {
    final previous = _started;
    final native = _native;
    if (previous == null || native == null) return _start();
    await previous.api.close();
    await previous.host.reset();
    final api = await native.connect(host: previous.host);
    previous.host.onEvent = (event) => _forwardEngine(api, event);
    previous.host.onFocusDenied = () {
      unawaited(api.pause().catchError((Object _) {}));
    };
    try {
      await api.playerState();
      await _audio?.rebind(api);
      if (_closing != null) throw StateError('核心正在关闭');
    } catch (_) {
      await api.close();
      rethrow;
    }
    return _started = StartedCore(
      api: api,
      host: previous.host,
      policy: previous.policy,
      platform: previous.platform,
    );
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    // Publish the closing barrier before any await. New startup waits for it;
    // the current startup/reconnect unwinds its own partially owned resources.
    final done = Completer<void>();
    _closing = done.future;
    unawaited(_close().then(done.complete, onError: done.completeError));
    return done.future.whenComplete(() {
      if (identical(_closing, done.future)) _closing = null;
    });
  }

  Future<void> _close() async {
    try {
      await _pending;
    } catch (_) {}
    final started = _started;
    _started = null;
    final native = _native;
    _native = null;
    _pending = null;
    await _releaseAll([
      () async {
        await _audio?.shutdown();
      },
      () async {
        await started?.api.close();
      },
      () async {
        await started?.host.close();
      },
      () async {
        await _focus?.close();
      },
      () async {
        await native?.close();
      },
    ]);
  }

  Future<StartedCore> ensureStarted() {
    if (_closing != null) return _closing!.then((_) => ensureStarted());
    if (_pending != null) return _pending!;
    if (_started != null) {
      if (_started!.api.connected) return Future.value(_started);
      return reconnect();
    }
    late final Future<StartedCore> run;
    run = _start().whenComplete(() {
      if (identical(_pending, run)) _pending = null;
    });
    return _pending = run;
  }

  Future<StartedCore> _start() async {
    final android = !kIsWeb && Platform.isAndroid;
    final platform = android ? 'android' : 'linux';
    final host = PlaybackHost(createPlayer: MediaKitEnginePlayer.create);
    RpcClient? api;
    try {
      await host.prepare();
      final dataDir = android
          ? (await getApplicationSupportDirectory()).path
          : '';
      _native = await NativeCore.start(
        platform: platform,
        dataDir: dataDir,
        lock: !android,
        startNative: startZeroOffUiIsolate,
        stopNative: stopZeroOffUiIsolate,
      );
      api = await _native!.connect(host: host);
      final connected = api;
      host.onEvent = (event) => _forwardEngine(connected, event);
      host.onFocusDenied = () {
        unawaited(connected.pause().catchError((Object _) {}));
      };
      final policy = InterruptionPolicy();
      if (android) {
        final session = await AudioSession.instance;
        final focus = _focus = AudioFocusCoordinator(
          (active) => session.setActive(active),
        );
        policy.onUserTransport = () {
          focus.interrupted = false;
        };
        host.acquireFocus = focus.acquire;
        host.releaseFocus = focus.release;
        host.abandonFocus = focus.close;
        if (_audio == null) {
          _audio = await startAndroidAudio(
            api: api,
            policy: policy,
            focus: focus,
          );
        } else {
          _audio!.policy = policy;
          _audio!.focus = focus;
          await _audio!.bindSession(session);
          await _audio!.rebind(api);
        }
      }
      if (_closing != null) throw StateError('核心正在关闭');
      return _started = StartedCore(
        api: api,
        host: host,
        policy: policy,
        platform: platform,
      );
    } catch (_) {
      final native = _native;
      _native = null;
      try {
        await _releaseAll([
          () async {
            await _audio?.shutdown();
          },
          () async {
            await api?.close();
          },
          host.close,
          () async {
            await _focus?.close();
          },
          () async {
            await native?.close();
          },
        ]);
      } catch (_) {
        // Preserve the startup error; every owned resource has been attempted.
      }
      rethrow;
    }
  }
}

void _forwardEngine(RpcClient api, HostEvent event) {
  final id = event.report.playbackId;
  if (id == null || id.isEmpty) return;
  final report = event.report;
  switch (event.kind) {
    case HostEventKind.position:
      api.sendEnginePosition(
        playbackId: id,
        seq: report.seq,
        positionMs: report.positionMs,
        durationMs: report.durationMs,
      );
    case HostEventKind.state:
      api.sendEngineState(
        playbackId: id,
        seq: report.seq,
        state: report.state,
        positionMs: report.positionMs,
        durationMs: report.durationMs,
      );
    case HostEventKind.ended:
      api.sendEngineEnded(
        playbackId: id,
        seq: report.seq,
        positionMs: report.positionMs,
        durationMs: report.durationMs,
      );
    case HostEventKind.failed:
      api.sendEngineFailed(
        playbackId: id,
        seq: report.seq,
        error: report.error,
        positionMs: report.positionMs,
        durationMs: report.durationMs,
      );
  }
}

Future<void> _releaseAll(List<Future<void> Function()> releases) async {
  Object? firstError;
  StackTrace? firstStack;
  for (final release in releases) {
    try {
      await release();
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
  }
  if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
}
