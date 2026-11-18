import 'dart:async';
import 'package:flutter/services.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

class AndroidScanCancellation {
  final String id = DateTime.now().microsecondsSinceEpoch.toString();
  final _cancelled = Completer<void>();
  bool get cancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (cancelled) return;
    _cancelled.complete();
    unawaited(
      AndroidStorage.channel
          .invokeMethod<void>('cancelScan', {'scan': id})
          .catchError((Object _) {}),
    );
  }
}

class AndroidStorage {
  static const channel = MethodChannel('zero_beat/storage');
  static Future<String?> pickDirectory() =>
      channel.invokeMethod<String>('pickDirectory');
  static Future<int> openDescriptor(String uri) async =>
      (await channel.invokeMethod<int>('open', {'uri': uri}))!;
  static Future<void> closeDescriptor(int fd) =>
      channel.invokeMethod('close', {'fd': fd});
  static Future<bool> exportDownload(
    String path, {
    bool saveAs = false,
  }) async =>
      await channel.invokeMethod<bool>('export', {
        'path': path,
        'save_as': saveAs,
      }) ??
      false;
  static Future<void> release(String uri) =>
      channel.invokeMethod('release', {'uri': uri});
  static Future<void> releaseUnused(CoreApi api, String uri) async {
    // A grant can be shared by several folder playlists.
    final lists = await api.playlists();
    if (!lists.playlists.any((p) => p.rootPath == uri)) await release(uri);
  }

  static Future<LibraryScan?> scan(
    CoreApi api, {
    Playlist? playlist,
    bool replace = false,
    AndroidScanCancellation? cancellation,
    void Function(int, int, String)? progress,
  }) async {
    final cancel = cancellation ?? AndroidScanCancellation();
    final grants = (await channel.invokeListMethod<String>('grants')) ?? [];
    final uri = playlist == null || replace
        ? await pickDirectory()
        : playlist.rootPath;
    if (uri == null) return null;
    var committed = false;
    String? token;
    try {
      if (cancel.cancelled) return null;
      Map<String, dynamic>? data;
      try {
        data = await channel.invokeMapMethod<String, dynamic>('enumerate', {
          'uri': uri,
          'scan': cancel.id,
        });
      } catch (_) {
        if (cancel.cancelled) return null;
        if (playlist != null && !replace) {
          await api.resourceUnavailable(playlist.id);
        }
        rethrow;
      }
      if (cancel.cancelled) return null;
      token = await api.resourceBegin(
        uri,
        data!['title'] as String,
        id: playlist?.id ?? '',
        subdirs: data['subdirs'] as int? ?? 0,
      );
      final sidecars = Map<String, dynamic>.from(data['lyrics'] as Map? ?? {});
      for (final entry in sidecars.entries) {
        if (cancel.cancelled) return null;
        progress?.call(0, 0, '读取歌词：${entry.key}');
        int? fd;
        try {
          fd = await openDescriptor(entry.value as String);
          await api.resourceLyrics(token, entry.key, fd);
        } catch (_) {
          await api.resourceSkip(token, entry.key);
        } finally {
          if (fd != null) await closeDescriptor(fd);
        }
      }
      final files = data['files'] as List;
      for (var index = 0; index < files.length; index++) {
        if (cancel.cancelled) return null;
        final file = Map<String, dynamic>.from(files[index] as Map);
        progress?.call(index, files.length, file['name'] as String);
        int? fd;
        try {
          final fileUri = file['uri'] as String;
          final duration = await channel.invokeMethod<int>('duration', {
            'uri': fileUri,
          });
          if (cancel.cancelled) return null;
          fd = await openDescriptor(fileUri);
          await api.resourceInspect(
            token,
            fd: fd,
            uri: fileUri,
            name: file['name'] as String,
            duration: duration ?? 0,
          );
        } catch (_) {
          await api.resourceSkip(token, file['name'] as String);
        } finally {
          if (fd != null) await closeDescriptor(fd);
        }
      }
      if (cancel.cancelled) return null;
      final result = await api.resourceCommit(token);
      committed = true;
      if (replace && playlist != null && playlist.rootPath != uri) {
        try {
          await releaseUnused(api, playlist.rootPath);
        } catch (_) {}
      }
      return result;
    } finally {
      if (token != null) {
        try {
          await api.resourceCancel(token);
        } catch (_) {}
      }
      if (!committed && !grants.contains(uri)) {
        try {
          await releaseUnused(api, uri);
        } catch (_) {}
      }
    }
  }
}
