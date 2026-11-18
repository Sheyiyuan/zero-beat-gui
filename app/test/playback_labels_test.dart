import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/shared/playback.dart';

import 'support/fake_core.dart';
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
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(_playPauseIcon(tester), Icons.play_arrow);

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
    expect(_playPauseIcon(tester), Icons.pause);
    expect(find.byTooltip('暂停'), findsOneWidget);
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

    expect(_playPauseIcon(tester), Icons.play_arrow);
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(find.byTooltip('暂停'), findsNothing);
    expect(find.byTooltip('播放'), findsWidgets);
  });
}

IconData _playPauseIcon(WidgetTester tester) {
  final button = tester.widget<IconButton>(find.byKey(const Key('play-pause')));
  return (button.icon as Icon).icon!;
}
