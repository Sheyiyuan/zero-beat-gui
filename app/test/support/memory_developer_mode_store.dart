import 'package:zero_beat_gui/features/developer_mode.dart';

class MemoryDeveloperModeStore implements DeveloperModeStore {
  MemoryDeveloperModeStore([this.value = false]);

  bool value;
  int reads = 0;
  int writes = 0;

  @override
  Future<bool> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(bool enabled) async {
    writes++;
    value = enabled;
  }
}

class FailingDeveloperModeStore implements DeveloperModeStore {
  FailingDeveloperModeStore({this.failRead = false, this.failWrite = false});

  final bool failRead;
  final bool failWrite;

  @override
  Future<bool> read() async {
    if (failRead) throw StateError('read failed');
    return false;
  }

  @override
  Future<void> write(bool enabled) async {
    if (failWrite) throw StateError('write failed');
  }
}
