import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/features/session.dart';
import 'package:zero_beat_gui/shared/library_pane.dart';
import 'package:zero_beat_gui/shared/playback.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets(
    'song rows use a compact source icon while details keep the full name',
    (tester) async {
      final api = FakeCoreApi()
        ..libraryPlaylists = [
          remotePlaylist(
            id: 'bili-1',
            title: 'B 站收藏',
            source: SourceID.valueBilibili,
          ),
        ]
        ..librarySongs = [
          sampleSong(id: 'song-1', source: SourceID.valueNetease),
        ];
      addTearDown(api.closeControllers);
      await pumpApp(
        tester,
        api: api,
        layout: AppLayout.mobile,
        size: const Size(430, 900),
      );

      expect(
        find.byKey(const ValueKey('playlist-row-source-bili-1')),
        findsOneWidget,
      );
      expect(find.byTooltip('哔哩哔哩'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('playlist-row-bili-1')),
          matching: find.text('哔哩哔哩'),
        ),
        findsNothing,
      );

      await tester.tap(find.text('B 站收藏'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('playlist-header-source-bili-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('song-source-song-1')), findsOneWidget);
      expect(find.byTooltip('网易云'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('song-source-song-1')),
          matching: find.text('网易云'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('now playing keeps the full source label for detail views', (
    tester,
  ) async {
    final song = sampleSong(id: 'song-1', source: SourceID.valueNetease);
    final api =
        FakeCoreApi(
            view: playerView(
              current: song,
              durationMs: song.durationMs,
              state: PlaybackStatus.valuePaused,
              playWhenReady: true,
            ),
          )
          ..libraryPlaylists = [samplePlaylist(id: 'list-1', title: '本地歌单')]
          ..librarySongs = [song];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.tap(find.text('本地歌单'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('song-source-song-1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('song-source-song-1')),
        matching: find.text('网易云'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('now-playing-source')),
        matching: find.text('网易云'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sidebar and detail header use platform icons', (
    tester,
  ) async {
    final api = FakeCoreApi()
      ..libraryPlaylists = [
        remotePlaylist(
          id: 'bili-1',
          title: 'B 站收藏',
          source: SourceID.valueBilibili,
        ),
      ]
      ..librarySongs = [sampleSong(id: 'song-1')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      size: const Size(1280, 900),
    );

    expect(
      find.byKey(const ValueKey('playlist-row-source-bili-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('playlist-header-source-bili-1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('playlist-row-bili-1')),
        matching: find.text('哔哩哔哩'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('playlist long press menu and overflow menu share actions', (
    tester,
  ) async {
    final api = FeatureApi()
      ..libraryPlaylists = [remotePlaylist(id: 'remote-1', title: '平台歌单')]
      ..librarySongs = [sampleSong(id: 'song-1')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.longPress(find.byKey(const ValueKey('playlist-row-remote-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('playlist-menu-play')), findsOneWidget);
    expect(find.text('播放歌单'), findsOneWidget);
    expect(find.text('刷新歌单'), findsOneWidget);
    expect(find.text('转为本地歌单'), findsOneWidget);
    expect(find.text('移除歌单'), findsOneWidget);
    expect(find.text('重命名'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('playlist-menu-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-menu-play')), findsNothing);
    expect(api.featureCalls, contains('library.refresh'));

    await tester.tap(find.text('平台歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理曲库'));
    await tester.pumpAndSettle();
    expect(find.text('播放歌单'), findsOneWidget);
    expect(find.text('移除歌单'), findsOneWidget);

    await tester.tap(find.text('播放歌单'));
    await tester.pumpAndSettle();
    expect(api.played, ['song-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop playlist right click opens the shared menu', (
    tester,
  ) async {
    final api = FeatureApi()
      ..libraryPlaylists = [samplePlaylist(id: 'list-1', title: '本地歌单')]
      ..librarySongs = [sampleSong(id: 'song-1')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      size: const Size(1280, 900),
    );

    await tester.tap(
      find.byKey(const ValueKey('playlist-row-list-1')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('playlist-menu-play')), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-menu-play')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping a song confirms removal without deleting audio', (
    tester,
  ) async {
    final api = FeatureApi()
      ..libraryPlaylists = [samplePlaylist(id: 'list-1', title: '本地歌单')]
      ..librarySongs = [sampleSong(id: 'song-1')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.tap(find.text('本地歌单'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('title-song-1')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('不会删除音频文件'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(api.featureCalls, contains('library.batch.start'));
    final params = api.featureParams['library.batch.start']!;
    expect(params['action'], 'remove');
    expect(params['playlist_id'], 'list-1');
    final songs = params['songs'] as List<Object?>;
    expect((songs.single as Map<String, Object?>)['id'], 'song-1');
    expect(find.byKey(const ValueKey('title-song-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping a playlist confirms mirror-only deletion', (
    tester,
  ) async {
    final api = FeatureApi()
      ..libraryPlaylists = [remotePlaylist(id: 'remote-1', title: '平台歌单')]
      ..librarySongs = [sampleSong(id: 'song-1')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.drag(
      find.byKey(const ValueKey('playlist-row-remote-1')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('平台上的原歌单'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(api.featureCalls, contains('library.delete'));
    expect(find.byKey(const ValueKey('playlist-row-remote-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('play playlist button starts the current playlist', (
    tester,
  ) async {
    final api = FakeCoreApi()
      ..libraryPlaylists = [samplePlaylist(id: 'list-1', title: '本地歌单')]
      ..librarySongs = [sampleSong(id: 'song-1'), sampleSong(id: 'song-2')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.tap(find.text('本地歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-playlist')));
    await tester.pumpAndSettle();

    expect(api.played, ['song-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop playlist header can start the playlist', (tester) async {
    final api = FakeCoreApi()
      ..libraryPlaylists = [samplePlaylist(id: 'list-1', title: '本地歌单')]
      ..librarySongs = [sampleSong(id: 'song-1')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      size: const Size(1280, 900),
    );

    expect(find.byKey(const Key('play-playlist')), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-playlist')));
    await tester.pumpAndSettle();

    expect(api.played, ['song-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library pane refresh keeps song selection and scroll offset', (
    tester,
  ) async {
    final api = FeatureApi()
      ..libraryPlaylists = [samplePlaylist(id: 'list-1', title: '本地歌单')]
      ..librarySongs = [
        for (var i = 0; i < 30; i++) sampleSong(id: 'song-$i', title: '歌曲 $i'),
      ];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      size: const Size(1280, 900),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );
    final list = find.descendant(
      of: find.byType(LibraryPane),
      matching: find.byType(ListView),
    );
    expect(find.byKey(const Key('library-pane-refresh')), findsOneWidget);
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    final offset = _scrollOffset(tester, list);
    expect(offset, greaterThan(0));

    container.read(libraryProvider.notifier).selectSong('song-5');
    await tester.pump();
    final selected = container.read(libraryProvider).selectedSongId;
    expect(selected, 'song-5');

    await container.read(libraryProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(container.read(libraryProvider).selectedSongId, selected);
    expect(_scrollOffset(tester, list), closeTo(offset, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press song menu disappears when the route is popped', (
    tester,
  ) async {
    final api = FakeCoreApi()
      ..libraryPlaylists = [samplePlaylist(id: 'list-1', title: '本地歌单')]
      ..librarySongs = [sampleSong(id: 'song-1')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.tap(find.text('本地歌单'));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('title-song-1')));
    await tester.pumpAndSettle();
    expect(find.text('加入队列'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('加入队列'), findsNothing);
    expect(find.byKey(const ValueKey('title-song-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Records typed feature calls so the menu/batch tests can assert that the
/// shared action table executed exactly the expected core request.
class FeatureApi extends FakeCoreApi implements CoreFeatureTransport {
  final featureCalls = <String>[];
  final featureParams = <String, Map<String, Object?>>{};
  final _batchSongs = <String>[];

  @override
  Stream<String> get changes => const Stream.empty();

  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) async {
    featureCalls.add(method);
    featureParams[method] = params;
    switch (method) {
      case 'library.batch.start':
        _batchSongs
          ..clear()
          ..addAll([
            for (final item
                in (params['songs'] as List<Object?>? ?? const <Object?>[]))
              ((item! as Map<Object?, Object?>)['id'] as String?) ?? '',
          ]);
        return Work(
          id: 'batch-1',
          action: 'batch',
          state: 'completed',
          message: '',
        ).toJson();
      case 'library.batch':
        final target = params['target'] as String? ?? '';
        if (target.isNotEmpty) played.add(target);
        return BatchResult(
          succeeded: [if (target.isNotEmpty) target],
          skipped: const [],
          failed: const [],
        ).toJson();
      case 'tasks.batch_result':
        return {
          'task': Work(
            id: 'batch-1',
            action: 'batch',
            state: 'completed',
            message: '',
          ).toJson(),
          'result': BatchResult(
            succeeded: List<String>.of(_batchSongs),
            skipped: const [],
            failed: const [],
          ).toJson(),
        };
      default:
        return const <String, Object?>{};
    }
  }
}

Playlist remotePlaylist({
  required String id,
  required String title,
  SourceID source = SourceID.valueBilibili,
  int count = 1,
}) => Playlist(
  id: id,
  source: source,
  title: title,
  kind: PlaylistKind.valueRemote,
  remoteId: 'remote-$id',
  count: count,
  frozen: false,
  syncExcluded: false,
  rootPath: '',
  scanStatus: '',
  hasScanError: false,
);

double _scrollOffset(WidgetTester tester, Finder list) {
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  return tester.state<ScrollableState>(scrollable).position.pixels;
}
