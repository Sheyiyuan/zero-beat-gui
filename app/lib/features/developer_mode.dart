import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/developer_log.dart';
import '../shared/playback.dart';

/// Persistence seam for the developer flag. Tests inject an in-memory store so
/// no platform channel or file system is required.
abstract interface class DeveloperModeStore {
  Future<bool> read();

  Future<void> write(bool enabled);
}

/// Stores the developer flag next to the app's other private support data.
///
/// It is intentionally local-only: [GUISettings] is generated from the core
/// wire schema, so adding a field there would require Go core/RPC and generated
/// model changes. A small JSON file keeps this UI preference out of sync and
/// out of the wire protocol.
class FileDeveloperModeStore implements DeveloperModeStore {
  FileDeveloperModeStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const fileName = 'developer-mode.json';

  final Future<Directory> Function() _supportDirectory;

  Future<File> _file() async {
    final directory = await _supportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<bool> read() async {
    final file = await _file();
    if (!await file.exists()) return false;
    final raw = (await file.readAsString()).trim();
    if (raw.isEmpty) return false;
    if (raw == 'true' || raw == '1') return true;
    try {
      final data = jsonDecode(raw);
      if (data is bool) return data;
      if (data is Map) return data['developer'] == true;
    } on FormatException {
      return false;
    }
    return false;
  }

  @override
  Future<void> write(bool enabled) async {
    final file = await _file();
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final payload = jsonEncode({'developer': enabled});
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      // rename over an existing file is not portable (notably on Windows).
      await file.writeAsString(payload, flush: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

final developerModeStoreProvider = Provider<DeveloperModeStore>(
  (ref) => FileDeveloperModeStore(),
);

/// Loads the persisted flag once and writes changes on a best-effort basis.
/// The in-memory state changes immediately so the UI never waits for disk.
class DeveloperModeController extends Notifier<bool> {
  bool _alive = true;
  bool _touched = false;

  @override
  bool build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final store = ref.watch(developerModeStoreProvider);
    Future<void>(() async {
      try {
        final stored = await store.read();
        if (_alive && !_touched && stored) state = true;
      } catch (error) {
        DeveloperLog.instance.warning('开发者模式', '读取本地开关失败：${errorText(error)}');
      }
    });
    return false;
  }

  Future<void> setEnabled(bool enabled) async {
    if (_touched && state == enabled) return;
    _touched = true;
    state = enabled;
    try {
      await ref.read(developerModeStoreProvider).write(enabled);
    } catch (error) {
      DeveloperLog.instance.warning('开发者模式', '保存本地开关失败：${errorText(error)}');
    }
  }
}

final developerModeProvider = NotifierProvider<DeveloperModeController, bool>(
  DeveloperModeController.new,
);
