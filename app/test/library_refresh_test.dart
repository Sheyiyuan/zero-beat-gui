import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/features/session.dart';
import 'package:zero_beat_gui/mobile/library_page.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets(
    'mobile home pulls to refresh, keeps the selection, and works when short',
    (tester) async {
      final api = CountingApi()
        ..libraryPlaylists = [
          samplePlaylist(id: 'a', title: '歌单甲'),
          samplePlaylist(id: 'b', title: '歌单乙'),
        ]
        ..librarySongs = [sampleSong()];
      addTearDown(api.closeControllers);
      addTearDown(api.releaseBlock);
      await pumpApp(
        tester,
        api: api,
        layout: AppLayout.mobile,
        size: const Size(430, 900),
      );
      expect(api.playlistCalls, 1);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileLibraryPage)),
        listen: false,
      );
      await tester.tap(find.text('歌单乙'));
      await tester.pumpAndSettle();
      expect(container.read(libraryProvider).selectedPlaylistId, 'b');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      api.block = Completer<void>();
      final list = find.byKey(const PageStorageKey('mobile-playlists'));
      await tester.drag(list, const Offset(0, 320));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(api.playlistCalls, 2);
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-library-refresh-progress')),
        findsOneWidget,
      );

      api.block!.complete();
      await tester.pumpAndSettle();

      expect(api.playlistCalls, 2);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(
        find.byKey(const Key('mobile-library-refresh-progress')),
        findsNothing,
      );
      expect(container.read(libraryProvider).selectedPlaylistId, 'b');
      expect(find.text('歌单甲'), findsOneWidget);
      expect(find.text('歌单乙'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop sidebar refresh keeps selection and scroll offset', (
    tester,
  ) async {
    final api = CountingApi()
      ..libraryPlaylists = [
        for (var i = 0; i < 30; i++)
          samplePlaylist(id: 'list-$i', title: '歌单 $i'),
      ]
      ..librarySongs = [sampleSong()];
    addTearDown(api.closeControllers);
    addTearDown(api.releaseBlock);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      size: const Size(1280, 800),
    );
    expect(api.playlistCalls, 1);
    expect(find.byTooltip('刷新歌单'), findsWidgets);

    final sidebar = find.byKey(const PageStorageKey('desktop-playlists'));
    await tester.dragUntilVisible(
      find.text('歌单 15'),
      sidebar,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌单 15'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );
    expect(container.read(libraryProvider).selectedPlaylistId, 'list-15');
    final offsetBefore = _scrollOffset(tester, sidebar);
    expect(offsetBefore, greaterThan(0));

    api.block = Completer<void>();
    await tester.tap(find.byKey(const Key('library-refresh-sidebar')));
    await tester.pump();
    expect(api.playlistCalls, 2);
    expect(find.byKey(const Key('library-refresh-progress')), findsOneWidget);

    api.block!.complete();
    await tester.pumpAndSettle();

    expect(api.playlistCalls, 2);
    expect(find.byKey(const Key('library-refresh-progress')), findsNothing);
    expect(container.read(libraryProvider).selectedPlaylistId, 'list-15');
    expect(_scrollOffset(tester, sidebar), closeTo(offsetBefore, 0.5));
    expect(tester.takeException(), isNull);
  });
}

double _scrollOffset(WidgetTester tester, Finder list) {
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  return tester.state<ScrollableState>(scrollable).position.pixels;
}

class CountingApi extends FakeCoreApi {
  int playlistCalls = 0;
  int songCalls = 0;
  Completer<void>? block;

  void releaseBlock() {
    final pending = block;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  @override
  Future<PlaylistList> playlists() async {
    playlistCalls++;
    final pending = block;
    if (playlistCalls > 1 && pending != null) await pending.future;
    return PlaylistList(playlists: libraryPlaylists, warning: '');
  }

  @override
  Future<SongPage> songs({
    required String playlistId,
    required int offset,
    required int limit,
  }) async {
    songCalls++;
    return SongPage(
      songs: librarySongs,
      total: librarySongs.length,
      offset: offset,
      limit: limit,
    );
  }
}
