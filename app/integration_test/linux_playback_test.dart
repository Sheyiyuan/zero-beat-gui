import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import 'package:zero_beat_gui/core/bootstrap.dart';
import 'package:zero_beat_gui/core/startup.dart';
import 'package:zero_beat_gui/platform/desktop_window.dart';

// Explicitly opt in with a fresh XDG directory; never open the normal music DB.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Linux playback, MPRIS, pause seek and reconnect',
    (tester) async {
      final root = Platform.environment['XDG_CONFIG_HOME'] ?? '';
      expect(
        root.contains('zero-gui-smoke-'),
        isTrue,
        reason: 'Run only with an isolated zero-gui-smoke-* XDG_CONFIG_HOME',
      );
      final media = await Directory('$root/fixture').create(recursive: true);
      final audio = File('${media.path}/零拍测试音 · 独立本地曲库.wav');
      await audio.writeAsBytes(_wave());
      final lrc = File(audio.path.replaceFirst(RegExp(r'\.wav$'), '.lrc'));
      await lrc.writeAsString('[00:01.00]Original line\n[00:04.00]Second line');
      await File(
        audio.path.replaceFirst(RegExp(r'\.wav$'), '.zh.lrc'),
      ).writeAsString('[00:01.00]译文\n[00:04.00]第二行');
      final repaint = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: repaint, child: const CoreStartup()),
      );
      final started = await CoreRuntime.instance.ensureStarted();
      addTearDown(() async {
        await DesktopWindow.instance.dispose();
        await CoreRuntime.instance.close();
      });
      final api = started.api;
      await api.folder('add', path: media.path);
      final playlists = await api.playlists();
      final folder = playlists.playlists.singleWhere(
        (p) => p.rootPath == media.path,
      );
      final songs = await api.songs(
        playlistId: folder.id,
        offset: 0,
        limit: 200,
      );
      expect(songs.songs, hasLength(1));
      await api.setVolume(0.15);
      await api.play(song: songs.songs.single, queue: songs.songs);
      await _until(tester, () async {
        final state = await api.playerState();
        return state.snapshot.state == PlaybackStatus.valuePlaying &&
            state.snapshot.positionMs > 500;
      });
      final sinks = await Process.run('pactl', ['list', 'sink-inputs']);
      expect(sinks.exitCode, 0);
      expect(sinks.stdout.toString(), contains('Sink Input #'));
      await File(
        '$root/pulse-sink-inputs.txt',
      ).writeAsString(sinks.stdout.toString());
      final mpris = Platform.environment['ZERO_MPRIS_NAME']!;
      Future<ProcessResult> bus(String method, List<String> args) =>
          Process.run('gdbus', [
            'call',
            '--session',
            '--dest',
            mpris,
            '--object-path',
            '/org/mpris/MediaPlayer2',
            '--method',
            method,
            ...args,
          ]);
      final status = await bus('org.freedesktop.DBus.Properties.Get', [
        'org.mpris.MediaPlayer2.Player',
        'PlaybackStatus',
      ]);
      expect(status.exitCode, 0, reason: '${status.stderr}');
      expect(status.stdout.toString(), contains('Playing'));
      await tester.pump(const Duration(milliseconds: 400));
      final boundary =
          repaint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final screenshot = await boundary.toImage();
      final png = await screenshot.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$root/linux-library.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      screenshot.dispose();
      final pause = await bus('org.mpris.MediaPlayer2.Player.Pause', []);
      expect(pause.exitCode, 0);
      await _until(
        tester,
        () async =>
            (await api.playerState()).snapshot.state ==
            PlaybackStatus.valuePaused,
      );
      await api.seek(4000);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        (await api.playerState()).snapshot.state,
        PlaybackStatus.valuePaused,
      );
      final song = songs.songs.single;
      final automatic = await api.lyrics(song);
      expect(automatic.lines.first.translation, '译文');
      final binding = LyricCandidate(
        kind: BindingKind.valueLocalFile,
        source: SourceID.valueLocal,
        externalId: '',
        page: 1,
        cid: BigInt.zero,
        lrclibId: BigInt.zero,
        path: lrc.path,
        songId: '',
        title: '本地歌词',
        artist: '',
        durationMs: 0,
        hasSynced: true,
        known: true,
        mark: '本',
      );
      expect((await api.previewLyrics(song, binding)).lines, hasLength(2));
      await api.bindLyrics(song, binding);
      final bound = await api.lyrics(song);
      expect(bound.bound, isTrue);
      await api.lyricOffset(song.id, bound.offsetKey, 250);
      expect((await api.lyrics(song)).offsetMs, 250);
      await api.unbindLyrics(song.id);
      expect((await api.lyrics(song)).bound, isFalse);
      final editor = await api.beginClip(song.id);
      await api.editClip(
        song.id,
        'save',
        token: editor.$1,
        clip: Clip(startMs: 2000, endMs: 8000),
      );
      await _until(
        tester,
        () async =>
            (await api.playerState()).snapshot.state ==
            PlaybackStatus.valuePaused,
      );
      await api.editClip(song.id, 'preview', token: editor.$1, positionMs: 500);
      await _until(
        tester,
        () async =>
            (await api.playerState()).snapshot.state ==
            PlaybackStatus.valuePaused,
      );
      await api.editClip(song.id, 'cancel', token: editor.$1);
      await _until(
        tester,
        () async =>
            (await api.playerState()).snapshot.state ==
            PlaybackStatus.valuePaused,
      );
      final restoredClip = await api.clip(song.id);
      expect(restoredClip.startMs, 2000);
      expect(restoredClip.endMs, 8000);
      expect((await api.playerState()).playWhenReady, isFalse);
      await api.resume();
      await _until(
        tester,
        () async =>
            (await api.playerState()).snapshot.state ==
            PlaybackStatus.valuePlaying,
      );
      await api.close();
      await tester.pump(const Duration(milliseconds: 300));
      final reconnected = await CoreRuntime.instance.reconnect();
      final restored = await reconnected.api.playerState();
      expect(restored.playWhenReady, isFalse);
      expect(restored.snapshot.state, isNot(PlaybackStatus.valuePlaying));
      expect(
        (await reconnected.api.playlists()).playlists.map((p) => p.id),
        contains(folder.id),
      );
      await CoreRuntime.instance.close();
      final starting = CoreRuntime.instance.ensureStarted();
      final closing = CoreRuntime.instance.close();
      await expectLater(starting, throwsStateError);
      await closing;
      final restarted = await CoreRuntime.instance.ensureStarted();
      expect(restarted.api.connected, isTrue);
      expect((await restarted.api.playerState()).playWhenReady, isFalse);
      await File('$root/result.txt').writeAsString(
        'PASS: local WAV through native core and media_kit; position advanced; PulseAudio stream present; MPRIS Playing/Pause; paused seek; lyrics translation/binding/offset/unbind; clip preview/cancel stayed paused; resume; reconnect stopped and retained library; close during startup and restart.\n',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _until(
  WidgetTester tester,
  Future<bool> Function() predicate,
) async {
  for (var n = 0; n < 100; n++) {
    if (await predicate()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('native playback did not reach expected state within 10 seconds');
}

Uint8List _wave() {
  const rate = 44100, samples = rate * 20;
  final data = ByteData(44 + samples * 2);
  void text(int offset, String text) {
    for (var n = 0; n < text.length; n++) {
      data.setUint8(offset + n, text.codeUnitAt(n));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var n = 0; n < samples; n++) {
    data.setInt16(
      44 + n * 2,
      (2400 * sin(2 * pi * 440 * n / rate)).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
