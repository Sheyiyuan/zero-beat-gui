import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('playlist detail header, count, and song rows share a grid', (
    tester,
  ) async {
    final api = FakeCoreApi()
      ..libraryPlaylists = [samplePlaylist(id: 'a', title: '歌单甲', count: 1)]
      ..librarySongs = [sampleSong(id: 'song-1')];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.tap(find.text('歌单甲'));
    await tester.pumpAndSettle();

    final headerX = tester.getTopLeft(find.text('本地 · 1 首')).dx;
    final countX = tester.getTopLeft(find.text('1 / 1 首')).dx;
    final songX = tester
        .getTopLeft(find.byKey(const ValueKey('song-cover-song-1')))
        .dx;

    expect(headerX, closeTo(20, 0.1));
    expect(countX, closeTo(headerX, 0.1));
    expect(songX, closeTo(headerX, 0.1));
    expect(find.byKey(const Key('library-refresh-pane')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop playlist detail does not overflow', (
    tester,
  ) async {
    final api = FakeCoreApi()
      ..libraryPlaylists = [samplePlaylist(id: 'a', title: '窄屏歌单')]
      ..librarySongs = [
        sampleSong(id: 'song-1', title: longTitle, artist: '很长的歌手名字'),
      ];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      size: const Size(640, 480),
    );

    expect(find.byKey(const Key('library-refresh-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('title-song-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
