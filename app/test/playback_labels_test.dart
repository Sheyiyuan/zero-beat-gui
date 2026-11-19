import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/icons.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/shared/playback.dart';
import 'package:zero_beat_gui/shared/player_bar.dart';

import 'support/fake_core.dart';
import 'support/fake_system_volume.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('buffering and playing labels follow the player snapshot', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        state: PlaybackStatus.valueBuffering,
        current: song,
        notice: '网络较慢',
        playWhenReady: true,
        durationMs: song.durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.desktop);

    expect(find.text('缓冲中'), findsOneWidget);
    expect(find.text('网络较慢'), findsOneWidget);
    expect(find.byIcon(AppIcons.pause), findsNothing);
    expect(_playPauseIcon(tester), AppIcons.play);

    api.emit(
      playerView(
        state: PlaybackStatus.valuePlaying,
        current: song,
        playWhenReady: true,
        durationMs: song.durationMs,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('缓冲中'), findsNothing);
    expect(_playPauseIcon(tester), AppIcons.pause);
    expect(find.byTooltip('暂停'), findsOneWidget);
  });

  testWidgets('playback errors toast and stay off the player card', (
    tester,
  ) async {
    const failure = '播放失败：无法打开音频';
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        playWhenReady: true,
        durationMs: song.durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(800, 900),
    );

    api.emit(
      playerView(
        current: song,
        playWhenReady: true,
        durationMs: song.durationMs,
        notice: failure,
        noticeLevel: 'error',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.descendant(
        of: find.byType(PlayerCard),
        matching: find.text(failure),
      ),
      findsNothing,
    );
    expect(find.widgetWithText(SnackBar, failure), findsOneWidget);
  });

  testWidgets('a restored paused snapshot does not show a playing icon', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        state: PlaybackStatus.valuePaused,
        current: song,
        playWhenReady: true,
        durationMs: song.durationMs,
        positionMs: 12000,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.desktop);

    expect(_playPauseIcon(tester), AppIcons.play);
    expect(find.byIcon(AppIcons.pause), findsNothing);
    expect(find.byTooltip('暂停'), findsNothing);
    expect(find.byTooltip('播放'), findsWidgets);
  });

  testWidgets('mobile full player follows the system media volume', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        // Deliberately different from the system volume: the mobile row must
        // not fall back to the core percent.
        volume: 0.8,
        durationMs: song.durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    final system = FakeSystemVolume(volume: 5, max: 100);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      systemVolume: system,
    );
    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('volume-label')), findsOneWidget);
    expect(find.text('5%'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('volume-slider')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    expect(system.writes, isNotEmpty);
    expect(system.writes.last, greaterThan(5));
    expect(api.volumes, isEmpty);
  });
}

IconData _playPauseIcon(WidgetTester tester) {
  final button = tester.widget<IconButton>(find.byKey(const Key('play-pause')));
  return (button.icon as Icon).icon!;
}
