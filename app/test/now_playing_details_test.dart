import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/shared/playback.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('desktop now-playing overlay shows the source platform', (
    tester,
  ) async {
    final song = sampleSong(source: SourceID.valueBilibili);
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        durationMs: song.durationMs,
        state: PlaybackStatus.valuePaused,
        playWhenReady: true,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      size: const Size(1280, 900),
    );

    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('now-playing-source')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('now-playing-source')),
        matching: find.text('哔哩哔哩'),
      ),
      findsOneWidget,
    );
    expect(find.text('bilibili'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile full player shows the source platform', (tester) async {
    final song = sampleSong(source: SourceID.valueNetease);
    final api = FakeCoreApi(
      view: playerView(current: song, durationMs: song.durationMs),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('now-playing-source')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('now-playing-source')),
        matching: find.text('网易云'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('long bilibili title collapses, expands, and collapses again', (
    tester,
  ) async {
    final song = sampleSong(
      id: 'bilibili-long',
      title: longBilibiliTitle,
      source: SourceID.valueBilibili,
    );
    final api = FakeCoreApi(
      view: playerView(current: song, durationMs: song.durationMs),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();

    final titleFinder = find.byKey(const Key('now-playing-title'));
    final collapsed = tester.widget<Text>(titleFinder);
    expect(collapsed.data, longBilibiliTitle);
    expect(collapsed.maxLines, 2);
    expect(collapsed.overflow, TextOverflow.ellipsis);
    expect(
      tester.getSize(titleFinder).height,
      lessThan(70),
      reason: 'two lines at 26px with 1.2 height stay under 70px',
    );
    expect(find.byKey(const Key('now-playing-title-toggle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('now-playing-title-toggle')));
    await tester.pumpAndSettle();

    final expanded = tester.widget<Text>(titleFinder);
    expect(expanded.data, longBilibiliTitle);
    expect(expanded.maxLines, isNull);
    expect(find.byKey(const Key('now-playing-title-scroll')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('now-playing-title-scroll'))).height,
      lessThanOrEqualTo(160),
    );
    expect(find.byTooltip('收起标题'), findsOneWidget);
    expect(find.byKey(const Key('play-pause')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('now-playing-title-toggle')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(titleFinder).maxLines, 2);
    expect(find.byTooltip('展开完整标题'), findsOneWidget);
  });
}
