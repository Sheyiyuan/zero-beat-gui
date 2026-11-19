import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A snapshot of the phone's media stream (`STREAM_MUSIC`) volume.
///
/// Android exposes volume as an integer index with a device-dependent maximum,
/// so both values are kept together. [fraction] is what the slider uses.
@immutable
class SystemVolumeState {
  const SystemVolumeState({required this.volume, required this.max});

  final int volume;
  final int max;

  double get fraction =>
      max <= 0 ? 0 : (volume / max).clamp(0.0, 1.0).toDouble();

  int get percent => (fraction * 100).round();
}

/// Platform media volume. Only available on Android; desktop keeps using the
/// core volume through [VolumeControl]'s existing path.
abstract interface class SystemVolume {
  /// Raw stream of media-volume updates, including hardware volume keys.
  Stream<SystemVolumeState> get changes;

  Future<SystemVolumeState> read();

  Future<void> setVolume(int volume);

  Future<void> dispose();
}

/// `zero_beat/volume` MethodChannel + `zero_beat/volume_events` EventChannel.
///
/// The event channel is opened lazily when the first listener arrives and
/// closed when the last one leaves. That means navigating away from the full
/// player stops the ContentObserver in Kotlin instead of leaving it running for
/// the whole app lifetime.
class AndroidSystemVolume implements SystemVolume {
  static const methodChannel = MethodChannel('zero_beat/volume');
  static const eventChannel = EventChannel('zero_beat/volume_events');

  StreamController<SystemVolumeState>? _controller;
  StreamSubscription<dynamic>? _platformSubscription;

  @override
  Stream<SystemVolumeState> get changes {
    _controller ??= StreamController<SystemVolumeState>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
    return _controller!.stream;
  }

  void _startListening() {
    _platformSubscription = eventChannel.receiveBroadcastStream().listen(
      (event) {
        final state = _decode(event);
        if (state != null) _controller?.add(state);
      },
      onError: (Object _) {
        // A missing/older platform side must not take the player down. The
        // widget falls back to the core volume when `read` also fails.
      },
    );
  }

  void _stopListening() {
    final subscription = _platformSubscription;
    _platformSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  @override
  Future<SystemVolumeState> read() async {
    final values = await Future.wait<int?>(<Future<int?>>[
      methodChannel.invokeMethod<int>('get'),
      methodChannel.invokeMethod<int>('max'),
    ]);
    final volume = values[0];
    final max = values[1];
    if (volume == null || max == null || max <= 0) {
      throw StateError('系统媒体音量不可用');
    }
    return SystemVolumeState(volume: volume.clamp(0, max), max: max);
  }

  @override
  Future<void> setVolume(int volume) async {
    await methodChannel.invokeMethod<void>('set', volume);
  }

  @override
  Future<void> dispose() async {
    _stopListening();
    final controller = _controller;
    _controller = null;
    if (controller != null) await controller.close();
  }

  SystemVolumeState? _decode(Object? event) {
    if (event is! Map) return null;
    final volume = (event['volume'] as num?)?.toInt();
    final max = (event['max'] as num?)?.toInt();
    if (volume == null || max == null || max <= 0) return null;
    return SystemVolumeState(volume: volume.clamp(0, max), max: max);
  }
}

/// `null` on desktop (and in widget tests unless a fake is injected), which
/// keeps the existing core-backed [VolumeControl] path unchanged.
final systemVolumeProvider = Provider<SystemVolume?>((ref) {
  if (kIsWeb || !Platform.isAndroid) return null;
  final volume = AndroidSystemVolume();
  ref.onDispose(volume.dispose);
  return volume;
});
