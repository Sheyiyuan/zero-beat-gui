import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/core/developer_log.dart';
import 'package:zero_beat_gui/features/developer_log_export.dart';

void main() {
  group('DeveloperLog ring buffer', () {
    test('keeps the newest entries in chronological order', () {
      final log = DeveloperLog(
        capacity: 3,
        clock: () => DateTime(2026, 1, 1, 12),
      );
      for (var i = 0; i < 5; i++) {
        log.info('来源', '消息 $i');
      }
      expect(log.length, 3);
      expect(log.snapshot().map((e) => e.message), ['消息 2', '消息 3', '消息 4']);
      expect(log.revision, 5);
    });

    test('clear empties the buffer and notifies listeners', () {
      final log = DeveloperLog(capacity: 3);
      var notified = 0;
      log.addListener(() => notified++);
      log.info('来源', '一');
      log.info('来源', '二');
      log.clear();
      expect(log.isEmpty, isTrue);
      expect(log.snapshot(), isEmpty);
      expect(notified, 3);
      expect(log.asText(), '# 零拍运行日志');
    });

    test('records time, level and source', () {
      final time = DateTime(2026, 11, 19, 21, 22, 7, 123);
      final log = DeveloperLog(capacity: 2, clock: () => time);
      log.warning('同步', '推送失败');
      final entry = log.snapshot().single;
      expect(entry.time, time);
      expect(entry.level, DeveloperLogLevel.warning);
      expect(entry.source, '同步');
      expect(entry.timeLabel, '21:22:07.123');
      expect(entry.exportLine, contains('2026-11-19 21:22:07.123 [警告] 同步'));
    });

    test('a burst of writes cannot exceed capacity', () {
      final log = DeveloperLog(capacity: 2000);
      for (var i = 0; i < 5000; i++) {
        log.debug('循环', '第 $i 条');
      }
      expect(log.length, 2000);
      expect(log.snapshot().first.message, '第 3000 条');
      expect(log.snapshot().last.message, '第 4999 条');
    });

    test('add redacts before storing', () {
      final log = DeveloperLog(capacity: 2);
      log.info('登录', 'Authorization: Bearer abcdefghijklmnop');
      log.info('登录', 'token=abc123456789&x=1');
      final text = log.asText();
      expect(text, isNot(contains('abcdefghijklmnop')));
      expect(text, isNot(contains('abc123456789')));
    });
  });

  group('redactSensitive', () {
    test('redacts headers, key/value pairs and bearer credentials', () {
      const raw =
          'Authorization: Bearer abc.def.ghi\n'
          'Cookie: SESSDATA=secret; bili_jct=csrf\n'
          '{"access_token":"tok-123456789","password":"hunter2"} '
          'token=abc123&x=1';
      final clean = redactSensitive(raw);
      expect(clean, isNot(contains('abc.def.ghi')));
      expect(clean, isNot(contains('SESSDATA=secret')));
      expect(clean, isNot(contains('bili_jct=csrf')));
      expect(clean, isNot(contains('tok-123456789')));
      expect(clean, isNot(contains('hunter2')));
      expect(clean, isNot(contains('abc123')));
    });

    test('redacts common platform cookie keys', () {
      final clean = redactSensitive(
        'MUSIC_U=abcdef123456; __csrf=csrf-token; '
        'bili_ticket=ticket123; SESSDATA=sess',
      );
      expect(clean, isNot(contains('abcdef123456')));
      expect(clean, isNot(contains('csrf-token')));
      expect(clean, isNot(contains('ticket123')));
      expect(clean, isNot(contains('sess')));
    });

    test('redacts JWTs, long opaque tokens and Chinese password labels', () {
      const raw =
          'jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
          'c2lnbmF0dXJlMTIzNDU2Nzg5MA '
          'opaque abcdefghijklmnopqrstuvwxyz012345 '
          '密码：hunter2';
      final clean = redactSensitive(raw);
      expect(clean, isNot(contains('eyJhbGci')));
      expect(clean, isNot(contains('abcdefghijklmnopqrstuvwxyz012345')));
      expect(clean, isNot(contains('hunter2')));
    });

    test('keeps ordinary diagnostics readable', () {
      const raw =
          '无法连接播放服务：Connection refused\n'
          '数据目录 /home/user/Music\n'
          '版本 0.8.0-development-build\n'
          '同步失败：远端分支不存在\n'
          'token invalid';
      final clean = redactSensitive(raw);
      expect(clean, contains('Connection refused'));
      expect(clean, contains('/home/user/Music'));
      expect(clean, contains('0.8.0-development-build'));
      expect(clean, contains('同步失败：远端分支不存在'));
      expect(clean, contains('token invalid'));
    });

    test('bare token-like values are redacted only when they look secret', () {
      expect(redactSensitive('token abc123456'), 'token <redacted>');
      expect(redactSensitive('token invalid'), 'token invalid');
    });
  });

  group('PlatformDeveloperLogExporter', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('zero-beat-log-');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('desktop writes the selected path and reports it', () async {
      String? written;
      final exporter = PlatformDeveloperLogFileExporter(
        android: false,
        chooseSaveLocation: (name) async => '${directory.path}/$name',
        writeFile: (path, contents) async {
          written = contents;
          await File(path).writeAsString(contents);
        },
      );
      final result = await exporter.export(
        fileName: 'zero-beat-log.txt',
        contents: 'hello',
      );
      expect(result.cancelled, isFalse);
      expect(result.path, '${directory.path}/zero-beat-log.txt');
      expect(written, 'hello');
      expect(
        await File('${directory.path}/zero-beat-log.txt').readAsString(),
        'hello',
      );
    });

    test('desktop cancellation returns a cancelled result', () async {
      final exporter = PlatformDeveloperLogFileExporter(
        android: false,
        chooseSaveLocation: (name) async => null,
      );
      final result = await exporter.export(
        fileName: 'zero-beat-log.txt',
        contents: 'hello',
      );
      expect(result.cancelled, isTrue);
      expect(result.path, isEmpty);
    });

    test('android writes a temp file and exports it to Downloads', () async {
      String? exportedSource;
      final exporter = PlatformDeveloperLogFileExporter(
        android: true,
        temporaryDirectory: () async => directory,
        exportToDownloads: (path) async {
          exportedSource = path;
          return true;
        },
      );
      final result = await exporter.export(
        fileName: 'zero-beat-log.txt',
        contents: 'android log',
      );
      expect(result.cancelled, isFalse);
      expect(result.path, '下载/zero-beat-log.txt');
      expect(exportedSource, isNotNull);
      expect(await File(exportedSource!).readAsString(), 'android log');
    });

    test('android cancellation returns a cancelled result', () async {
      final exporter = PlatformDeveloperLogFileExporter(
        android: true,
        temporaryDirectory: () async => directory,
        exportToDownloads: (path) async => false,
      );
      final result = await exporter.export(
        fileName: 'zero-beat-log.txt',
        contents: 'android log',
      );
      expect(result.cancelled, isTrue);
    });

    test('file name uses a sortable local timestamp', () {
      expect(
        developerLogFileName(DateTime(2026, 11, 19, 21, 22, 7)),
        'zero-beat-log-20261119-212207.txt',
      );
    });
  });
}
