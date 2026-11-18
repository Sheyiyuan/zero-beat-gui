import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/client.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import 'client_test.dart' show FakeHost;

void main() {
  test(
    'TUI and GUI alternate isolated data; mixed exclusions sync and local data stays local',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'zero-tui-gui-interop-',
      );
      var passed = false;
      addTearDown(() async {
        if (passed) {
          await root.delete(recursive: true);
        } else {
          print('Retained isolated failure evidence: ${root.path}');
        }
      });
      final binary = Platform.environment['ZERO_BEAT_TUI_BINARY']!;
      final first = '${root.path}/first';
      final second = '${root.path}/second';
      final remote = '${root.path}/remote.git';
      final music = await Directory('${root.path}/music').create();
      await File('${music.path}/local.mp3').writeAsBytes(List.filled(1024, 0));
      Future<String> git(List<String> args) async {
        final result = await Process.run(
          'git',
          args,
          environment: {
            'GIT_CONFIG_GLOBAL': '/dev/null',
            'GIT_CONFIG_NOSYSTEM': '1',
          },
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return result.stdout.toString().trim();
      }

      Future<String> tui(List<String> args) async {
        final result = await Process.run(
          binary,
          args,
          environment: {
            'XDG_CONFIG_HOME': first,
            'GIT_CONFIG_GLOBAL': '/dev/null',
            'GIT_CONFIG_NOSYSTEM': '1',
          },
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return result.stdout.toString();
      }

      Future<(NativeCore, CoreApi)> open(String directory) async {
        final native = await NativeCore.start(
          platform: 'linux',
          dataDir: '$directory/zero-beat',
        );
        addTearDown(native.close);
        return (native, await native.connect(host: FakeHost()));
      }

      Future<void> sync(
        CoreApi api,
        String action, {
        String remote = '',
      }) async {
        final work = await api.syncAction(action, remote: remote);
        try {
          await api.waitTask(work.id);
        } catch (error) {
          for (final dir in [first, second]) {
            final state = File('$dir/zero-beat/sync/state.json');
            if (await state.exists()) {
              final details = jsonDecode(await state.readAsString()) as Map;
              if (details['last_error'] != null)
                fail('$error: ${details['last_error']}');
            }
          }
          rethrow;
        }
      }

      Song song(String id) => Song(
        id: 'netease:$id:1',
        source: SourceID.valueNetease,
        remoteId: id,
        page: 1,
        cid: BigInt.zero,
        title: '测试 $id',
        artist: '测试作者',
        album: '',
        durationMs: 180000,
        cover: '',
      );
      await git(['init', '--bare', '--initial-branch=main', remote]);
      await tui(['library', 'add', music.path]);
      var core = await open(first);
      var api = core.$2;
      final folder = (await api.playlists()).playlists.singleWhere(
        (p) => p.rootPath == music.path,
      );
      final shared = await api.createPlaylist('共同歌单');
      final private = await api.createPlaylist('仅设备 A', localOnly: true);
      final tracks = [song('9000001'), song('9000002')];
      expect(
        (await api.batch('add', target: shared.id, songs: tracks)).failed,
        isEmpty,
      );
      final mix = await api.createPlaylist(
        '混合排除',
        kind: 'mixin',
        refs: [shared.id],
      );
      expect(
        (await api.batch(
          'remove',
          target: mix.id,
          songs: [tracks.first],
        )).failed,
        isEmpty,
      );
      await sync(api, 'init', remote: remote);
      expect((await api.syncStatus()).syncAccounts, isFalse);
      await api.close();
      await core.$1.close();
      final initialHead = await git(['--git-dir=$remote', 'rev-parse', 'main']);
      final meta =
          jsonDecode(await git(['--git-dir=$remote', 'show', 'main:meta.json']))
              as Map;
      expect(meta['v'], 3);
      expect(await tui(['library', 'list']), contains(folder.id));
      final status = await tui(['sync', 'status']);
      expect(status, contains('登录态同步: 关闭'));
      expect(status, isNot(contains('缺少密钥')));
      await tui(['sync', 'push']);
      expect(
        await git(['--git-dir=$remote', 'rev-parse', 'main']),
        initialHead,
        reason: 'unchanged TUI sync created a commit',
      );
      core = await open(second);
      api = core.$2;
      final own = await api.createPlaylist('仅设备 B', localOnly: true);
      await sync(api, 'init', remote: remote);
      final ids = (await api.playlists()).playlists.map((p) => p.id).toList();
      expect(ids, containsAll([shared.id, mix.id, own.id]));
      expect(ids, isNot(contains(private.id)));
      expect(ids, isNot(contains(folder.id)));
      final mixedSongs = await api.songs(
        playlistId: mix.id,
        offset: 0,
        limit: 200,
      );
      expect(mixedSongs.songs.map((s) => s.remoteId), ['9000002']);
      await api.close();
      await core.$1.close();
      await tui(['sync', 'pull']);
      core = await open(first);
      api = core.$2;
      expect(
        (await api.playlists()).playlists.map((p) => p.id),
        containsAll([folder.id, private.id, mix.id]),
      );
      final before = await git(['--git-dir=$remote', 'rev-parse', 'main']);
      await sync(api, 'now');
      expect(await git(['--git-dir=$remote', 'rev-parse', 'main']), before);
      await api.close();
      await core.$1.close();
      passed = true;
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip:
        Platform.environment['ZERO_BEAT_TUI_BINARY'] == null ||
        Platform.environment['ZERO_BEAT_NATIVE_TEST'] != '1',
  );
}
