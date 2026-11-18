import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/features/content_pages.dart';
import 'package:zero_beat_gui/features/song_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/app/theme.dart';
import 'full_feature_test.dart' show FeatureApi;
import 'support/samples.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets(
    'song action is immediate and desktop double tap is independent',
    (tester) async {
      final api = FeatureApi()
        ..libraryPlaylists = [samplePlaylist()]
        ..librarySongs = [sampleSong()];
      addTearDown(api.closeControllers);
      await pumpApp(tester, api: api, layout: AppLayout.desktop);
      final title = find.byKey(const ValueKey('title-song-1'));
      await tester.tap(title);
      await tester.pump(const Duration(milliseconds: 350));
      expect(api.calls.where((c) => c.$1 == 'library.batch'), isEmpty);
      await tester.tap(title);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(title);
      await tester.pump();
      expect(api.calls.where((c) => c.$1 == 'library.batch'), hasLength(1));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('content selection persists across pages and resets on target', (
    tester,
  ) async {
    final api = FeatureApi();
    addTearDown(api.closeControllers);
    int page = 1;
    String target = 'artist-a';
    late StateSetter change;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coreApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: buildZeroTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                change = setState;
                return SongSelectionScope(
                  target: target,
                  child: Column(
                    children: [
                      const SongSelectionBar(),
                      FeatureSong(song: sampleSong(id: 'song-$page')),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('title-song-1')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 首 · 可跨页选择'), findsOneWidget);
    change(() => page = 2);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 首 · 可跨页选择'), findsOneWidget);
    await tester.tap(find.byTooltip('批量操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入队列'));
    await tester.pumpAndSettle();
    final call = api.calls.lastWhere((c) => c.$1 == 'library.batch');
    expect((call.$2['songs'] as List).map((s) => (s as Map)['id']), [
      'song-1',
      'song-2',
    ]);
    await tester.longPress(find.byKey(const ValueKey('title-song-2')));
    await tester.pumpAndSettle();
    change(() => target = 'artist-b');
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
