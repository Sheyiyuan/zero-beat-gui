import 'dart:async';

import 'package:zero_beat_gui/platform/system_volume.dart';

/// In-memory Android media volume for widget tests.
///
/// [emit] simulates a hardware volume key / another app changing
/// `STREAM_MUSIC`; [setVolume] is what the slider/mute button calls.
class FakeSystemVolume implements SystemVolume {
  FakeSystemVolume({int volume = 8, int max = 15})
    : _state = SystemVolumeState(volume: volume.clamp(0, max), max: max) {
    _changes = StreamController<SystemVolumeState>.broadcast(
      onListen: () => listeners += 1,
      onCancel: () => listeners -= 1,
    );
  }

  late final StreamController<SystemVolumeState> _changes;
  SystemVolumeState _state;

  int listeners = 0;
  int readCalls = 0;
  final writes = <int>[];

  SystemVolumeState get state => _state;

  @override
  Stream<SystemVolumeState> get changes => _changes.stream;

  @override
  Future<SystemVolumeState> read() async {
    readCalls += 1;
    return _state;
  }

  @override
  Future<void> setVolume(int volume) async {
    writes.add(volume);
    _apply(volume);
  }

  void emit(int volume) => _apply(volume);

  void _apply(int volume) {
    final max = _state.max;
    final clamped = max > 0 ? volume.clamp(0, max) : 0;
    _state = SystemVolumeState(volume: clamped, max: max);
    if (!_changes.isClosed) _changes.add(_state);
  }

  @override
  Future<void> dispose() => _changes.close();
}
