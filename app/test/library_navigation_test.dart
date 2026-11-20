import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/features/session.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  test('opening a playable link cancels interruption auto-resume', () async {
    final api = LinkApi();
    final container = ProviderContainer(
      overrides: [coreApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    addTearDown(api.closeControllers);
    final policy = container.read(interruptionPolicyProvider);
    policy.onBegin(active: true);
    await container
        .read(searchProvider.notifier)
        .openLink('https://example.test/song');
    expect(api.played, ['song-1']);
    expect(policy.shouldResume(temporary: true), isFalse);
  });

  test(
    'old playlist completion cannot overwrite the selected playlist',
    () async {
      final api = PagingApi()
        ..libraryPlaylists = [samplePlaylist(id: 'a'), samplePlaylist(id: 'b')];
      final container = ProviderContainer(
        overrides: [coreApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      addTearDown(api.closeControllers);
      container.read(libraryProvider);
      await Future<void>.delayed(Duration.zero);
      api.blockA = Completer<SongPage>();
      final controller = container.read(libraryProvider.notifier);
      final a = controller.selectPlaylist('a');
      await controller.selectPlaylist('b');
      api.blockA!.complete(
        SongPage(
          songs: [sampleSong(id: 'old-a')],
          total: 1,
          offset: 0,
          limit: 200,
        ),
      );
      await a;
      final state = container.read(libraryProvider);
      expect(state.selectedPlaylistId, 'b');
      expect(state.songs.first.id, 'b-0');
    },
  );

  test(
    'large playlist loads beyond 200 and keeps rows after append failure',
    () async {
      final api = PagingApi()..libraryPlaylists = [samplePlaylist(id: 'a')];
      final container = ProviderContainer(
        overrides: [coreApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      addTearDown(api.closeControllers);
      container.read(libraryProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(libraryProvider).songs, hasLength(200));
      final controller = container.read(libraryProvider.notifier);
      api.failMore = true;
      await controller.loadMore();
      expect(container.read(libraryProvider).songs, hasLength(200));
      expect(container.read(libraryProvider).moreError, isNotEmpty);
      api.failMore = false;
      await controller.loadMore();
      expect(container.read(libraryProvider).songs, hasLength(205));
      expect(container.read(libraryProvider).hasMore, isFalse);
    },
  );

  test(
    'search pagination retries the failed page and resets on new query',
    () async {
      final api = PagingApi();
      final container = ProviderContainer(
        overrides: [coreApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      addTearDown(api.closeControllers);
      final controller = container.read(searchProvider.notifier);
      controller.setKeyword('music');
      await controller.submit();
      api.searchError = 'failed';
      await controller.goToPage(2);
      expect(container.read(searchProvider).page, 2);
      expect(container.read(searchProvider).error, isNotEmpty);
      api.searchError = null;
      await controller.retry();
      expect(api.pagesRequested, [1, 2, 2]);
      controller.setKeyword('new');
      await controller.submit();
      expect(api.pagesRequested.last, 1);
    },
  );

  testWidgets(
    'desktop playlist leaves search, even when search was in flight',
    (tester) async {
      final api = PagingApi()
        ..libraryPlaylists = [samplePlaylist(title: '歌单甲')];
      addTearDown(api.closeControllers);
      await pumpApp(tester, api: api, layout: AppLayout.desktop);
      await tester.enterText(find.byKey(const Key('search-field')), 'music');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-next')), findsOneWidget);
      api.pendingSearch = Completer<SearchView>();
      await tester.tap(find.byKey(const Key('search-next')));
      await tester.pump();
      await tester.tap(find.text('歌单甲'));
      await tester.pumpAndSettle();
      api.pendingSearch!.complete(
        SearchView(candidates: [], pages: 3, hasWarning: false, warning: ''),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-next')), findsNothing);
      expect(find.byKey(const ValueKey('title-list-1-0')), findsOneWidget);
    },
  );

  testWidgets('mobile opens either playlist and back preserves playback', (
    tester,
  ) async {
    final api = PagingApi()
      ..libraryPlaylists = [
        samplePlaylist(id: 'a', title: '歌单甲'),
        samplePlaylist(id: 'b', title: '歌单乙'),
      ];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await tester.tap(find.text('歌单乙'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('title-b-0')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('歌单甲'), findsOneWidget);
    expect(find.text('歌单乙'), findsOneWidget);
    expect(api.pauses, 0);
  });

  testWidgets('mine uses cached hello and disconnect blocks transport', (
    tester,
  ) async {
    final api = FakeCoreApi();
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.mobile);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    // Version details moved to their own page; the mine body still reuses the
    // cached hello snapshot for account rows.
    expect(find.text('哔哩哔哩 未登录 · 网易云 未登录'), findsOneWidget);
    expect(find.text('版本信息'), findsOneWidget);
    expect(api.helloCalls, 0);
    api.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('重新连接'), findsOneWidget);
    expect(api.toggles, 0);
  });
}

class PagingApi extends FakeCoreApi {
  Completer<SongPage>? blockA;
  bool failMore = false;
  final pagesRequested = <int>[];
  Completer<SearchView>? pendingSearch;
  @override
  Future<SongPage> songs({
    required String playlistId,
    required int offset,
    required int limit,
  }) async {
    if (playlistId == 'a' && blockA != null) return blockA!.future;
    if (offset > 0 && failMore) throw StateError('追加失败');
    return SongPage(
      songs: List.generate(
        (205 - offset).clamp(0, limit),
        (i) => sampleSong(id: '$playlistId-${offset + i}'),
      ),
      total: 205,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<SearchView> search({
    required String keyword,
    required int page,
    String source = '',
  }) async {
    pagesRequested.add(page);
    if (searchError != null) throw StateError(searchError!);
    if (pendingSearch != null) return pendingSearch!.future;
    return SearchView(candidates: [], pages: 3, hasWarning: false, warning: '');
  }
}

class LinkApi extends FakeCoreApi {
  @override
  Future<LinkView> openLink(String text) async =>
      LinkView(matched: true, kind: 'track', ref: null, song: sampleSong());
}
