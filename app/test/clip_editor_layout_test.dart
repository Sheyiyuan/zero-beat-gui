import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/features/lyrics_page.dart';
import 'package:zero_beat_gui/shared/playback.dart';

import 'full_feature_test.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('clip editor disables save for invalid range', (tester) async {
    final song = sampleSong();
    final api = FeatureApi()
      ..view = playerView(current: song, durationMs: 180000);
    addTearDown(api.closeControllers);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coreApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(body: ClipEditor(song: song)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '72');
    await tester.enterText(find.byType(TextField).last, '40');
    await tester.pump();
    expect(find.text('结束时间必须晚于开始时间。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存片段'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('clip editor can save when duration is not known yet', (
    tester,
  ) async {
    final song = sampleSong(durationMs: 0);
    final api = FeatureApi()..view = playerView(current: song, durationMs: 0);
    addTearDown(api.closeControllers);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coreApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(body: ClipEditor(song: song)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    api.emit(playerView(current: song, durationMs: 0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clip-start')), '10');
    await tester.enterText(find.byKey(const Key('clip-end')), '20');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存片段'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('clip editor in feature route survives view insets scroll', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FeatureApi()
      ..libraryPlaylists = [samplePlaylist()]
      ..view = playerView(current: song, durationMs: 180000);
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(390, 844),
    );
    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('片段'));
    await tester.pumpAndSettle();
    final previousInsets = tester.view.viewInsets;
    final previousSize = tester.view.physicalSize;
    addTearDown(() {
      tester.view.viewInsets = previousInsets;
      tester.view.physicalSize = previousSize;
    });
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('保存片段'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('保存片段'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('取消'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
