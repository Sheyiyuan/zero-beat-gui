import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/storage.dart';

/// Clipboard seam; tests can record copied text without a platform channel.
abstract interface class DeveloperLogClipboard {
  Future<void> setText(String text);
}

class SystemDeveloperLogClipboard implements DeveloperLogClipboard {
  const SystemDeveloperLogClipboard();

  @override
  Future<void> setText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final developerLogClipboardProvider = Provider<DeveloperLogClipboard>(
  (ref) => const SystemDeveloperLogClipboard(),
);

class DeveloperLogExportResult {
  const DeveloperLogExportResult.exported(this.path) : cancelled = false;

  const DeveloperLogExportResult.cancelled() : path = '', cancelled = true;

  /// User-facing destination shown in the confirmation snackbar.
  final String path;
  final bool cancelled;
}

abstract interface class DeveloperLogExporter {
  Future<DeveloperLogExportResult> export({
    required String fileName,
    required String contents,
  });
}

typedef DeveloperLogSaveLocation =
    Future<String?> Function(String suggestedName);
typedef DeveloperLogWriteFile =
    Future<void> Function(String path, String contents);
typedef DeveloperLogAndroidExport = Future<bool> Function(String path);

/// Desktop uses the native save dialog; Android writes a temporary file and
/// hands it to the existing storage channel, which opens the system save UI.
class PlatformDeveloperLogFileExporter implements DeveloperLogExporter {
  PlatformDeveloperLogFileExporter({
    bool? android,
    Future<Directory> Function()? temporaryDirectory,
    DeveloperLogSaveLocation? chooseSaveLocation,
    DeveloperLogWriteFile? writeFile,
    DeveloperLogAndroidExport? exportToDownloads,
  }) : _android = android ?? (!kIsWeb && Platform.isAndroid),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _chooseSaveLocation = chooseSaveLocation ?? _defaultSaveLocation,
       _writeFile = writeFile ?? _defaultWriteFile,
       _exportToDownloads = exportToDownloads ?? _defaultAndroidExport;

  final bool _android;
  final Future<Directory> Function() _temporaryDirectory;
  final DeveloperLogSaveLocation _chooseSaveLocation;
  final DeveloperLogWriteFile _writeFile;
  final DeveloperLogAndroidExport _exportToDownloads;

  @override
  Future<DeveloperLogExportResult> export({
    required String fileName,
    required String contents,
  }) async {
    final safeName = fileName.trim().isEmpty ? 'zero-beat-log.txt' : fileName;
    if (_android) {
      final directory = await _temporaryDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}$safeName');
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await _writeFile(file.path, contents);
      final exported = await _exportToDownloads(file.path);
      if (!exported) return const DeveloperLogExportResult.cancelled();
      return DeveloperLogExportResult.exported('下载/$safeName');
    }
    final target = await _chooseSaveLocation(safeName);
    if (target == null || target.trim().isEmpty) {
      return const DeveloperLogExportResult.cancelled();
    }
    await _writeFile(target, contents);
    return DeveloperLogExportResult.exported(target);
  }

  static Future<String?> _defaultSaveLocation(String suggestedName) async {
    final location = await getSaveLocation(suggestedName: suggestedName);
    return location?.path;
  }

  static Future<void> _defaultWriteFile(String path, String contents) async {
    await File(path).writeAsString(contents, flush: true);
  }

  static Future<bool> _defaultAndroidExport(String path) =>
      AndroidStorage.exportDownload(path, saveAs: true);
}

final developerLogExporterProvider = Provider<DeveloperLogExporter>(
  (ref) => PlatformDeveloperLogFileExporter(),
);

String developerLogFileName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'zero-beat-log-${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}.txt';
}
