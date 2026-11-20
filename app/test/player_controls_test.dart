import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/icons.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/desktop/desktop_now_playing.dart';
import 'package:zero_beat_gui/desktop/desktop_player_bar.dart';
import 'package:zero_beat_gui/shared/playback.dart';
import 'package:zero_beat_gui/shared/player_bar.dart';
import 'package:zero_beat_gui/shared/progress_ring.dart';
import 'package:zero_beat_gui/shared/queue_panel.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  Future<void> openFullPlayer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
  }

  testWidgets('compact player bar draws progress around play/pause', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        durationMs: 180000,
        positionMs: 45000,
        state: PlaybackStatus.valuePlaying,
        playWhenReady: true,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    final bar = find.byType(PlayerBar);
    final ringFinder = find.descendant(
      of: bar,
      matching: find.byKey(const Key('play-progress-ring')),
    );
    final buttonFinder = find.descendant(
      of: bar,
      matching: find.byKey(const Key('play-pause')),
    );
    expect(ringFinder, findsOneWidget);
    expect(buttonFinder, findsOneWidget);
    expect(
      tester.widget<PlayProgressRing>(ringFinder).progress,
      closeTo(0.25, 0.0001),
    );
    // The compact bar uses a lighter 38px control than the detail page.
    expect(tester.getSize(ringFinder), const Size(32, 32));
    expect(tester.getSize(buttonFinder), const Size(32, 32));
    expect(tester.getCenter(buttonFinder), tester.getCenter(ringFinder));
    expect(find.byTooltip('暂停'), findsOneWidget);
    final restart = tester.getCenter(
      find.byKey(const Key('player-bar-restart')),
    );
    final play = tester.getCenter(buttonFinder);
    final queue = tester.getCenter(find.byKey(const Key('queue-button')));
    expect(restart.dx, lessThan(play.dx));
    expect(play.dx, lessThan(queue.dx));
    expect(tester.getSize(bar).height, 82);

    api.emit(playerView(current: song, durationMs: 0, positionMs: 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PlayProgressRing>(ringFinder).progress, isNull);
    expect(
      find.descendant(of: ringFinder, matching: find.byType(CustomPaint)),
      findsNothing,
    );

    api.emit(
      playerView(
        current: song,
        durationMs: 180000,
        positionMs: 90000,
        state: PlaybackStatus.valuePaused,
        playWhenReady: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<PlayProgressRing>(ringFinder).progress,
      closeTo(0.5, 0.0001),
    );
    expect(find.byIcon(AppIcons.play), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping empty space on the compact bar opens the player', (
    tester,
  ) async {
    final song = sampleSong(title: '短');
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

    final track = tester.getRect(find.byKey(const Key('player-bar-track')));
    // Right of the short title, left of the transport buttons.
    await tester.tapAt(Offset(track.right - 12, track.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('now playing uses a plain play/pause button without a ring', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        durationMs: 180000,
        positionMs: 45000,
        state: PlaybackStatus.valuePlaying,
        playWhenReady: true,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await openFullPlayer(tester);

    final body = find.byType(NowPlayingBody);
    final buttonFinder = find.descendant(
      of: body,
      matching: find.byKey(const Key('play-pause')),
    );
    expect(buttonFinder, findsOneWidget);
    expect(
      find.descendant(
        of: body,
        matching: find.byKey(const Key('play-progress-ring')),
      ),
      findsNothing,
    );
    // The compact bar underneath is offstage, so the detail page is the only
    // onstage owner of the play control.
    expect(find.byKey(const Key('play-progress-ring')), findsNothing);
    // The detail page uses a larger filled disc as the primary control.
    expect(tester.getSize(buttonFinder), const Size(68, 68));
    expect(find.byIcon(AppIcons.pause), findsOneWidget);

    await tester.tap(buttonFinder);
    await tester.pump();
    expect(api.toggles, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop now playing leaves transport in the docked bar', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        durationMs: 120000,
        positionMs: 30000,
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
    await openFullPlayer(tester);

    final view = find.byType(DesktopNowPlaying);
    expect(view, findsOneWidget);
    expect(
      find.descendant(of: view, matching: find.byKey(const Key('play-pause'))),
      findsNothing,
    );
    final bar = find.byType(DesktopPlayerBar);
    double x(Finder finder) =>
        tester.getCenter(find.descendant(of: bar, matching: finder)).dx;
    final restart = x(find.byKey(const Key('player-bar-restart')));
    final previous = x(find.byTooltip('上一首'));
    final play = x(find.byKey(const Key('play-pause')));
    final next = x(find.byTooltip('下一首'));
    final mode = x(find.byKey(const Key('playback-mode')));
    expect(restart, lessThan(previous));
    expect(previous, lessThan(play));
    expect(play, lessThan(next));
    expect(next, lessThan(mode));

    await tester.tap(find.byKey(const Key('now-playing-close')));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopNowPlaying), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('now playing puts restart before previous and mode after next', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        durationMs: song.durationMs,
        mode: PlaybackMode.valueListLoop,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await openFullPlayer(tester);
    await expectNowPlayingControlOrder(tester);

    final mode = find.descendant(
      of: find.byType(NowPlayingBody),
      matching: find.byKey(const Key('playback-mode')),
    );
    expect(mode, findsOneWidget);
    // Phones show the mode as an icon so the play disc stays centred.
    expect(find.byKey(const Key('playback-mode-label')), findsNothing);
    expect(find.byTooltip('列表循环'), findsOneWidget);

    await tester.tap(mode);
    await tester.pumpAndSettle();
    expect(api.modes, ['loop_one']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow now playing keeps the mode as a compact icon', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        durationMs: song.durationMs,
        mode: PlaybackMode.valueListLoop,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(360, 800),
    );
    await openFullPlayer(tester);

    final body = find.byType(NowPlayingBody);
    final mode = find.descendant(
      of: body,
      matching: find.byKey(const Key('playback-mode')),
    );
    await tester.ensureVisible(mode);
    await tester.pumpAndSettle();
    expect(mode, findsOneWidget);
    expect(find.byKey(const Key('playback-mode-label')), findsNothing);
    expect(find.byTooltip('列表循环'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restart button seeks the current track back to zero', (
    tester,
  ) async {
    final song = sampleSong();
    final api = FakeCoreApi(
      view: playerView(
        current: song,
        durationMs: song.durationMs,
        positionMs: 42000,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    // The compact bar has its own restart control.
    expect(find.byTooltip('从头播放'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-bar-restart')));
    await tester.pump();
    expect(api.seekPositions, [0]);

    await openFullPlayer(tester);
    await tester.tap(find.byKey(const Key('now-playing-restart')));
    await tester.pump();
    expect(api.seekPositions, [0, 0]);
    expect(find.byTooltip('从头播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the cover follows the finger and commits next', (
    tester,
  ) async {
    final songs = sampleQueue();
    final api = FakeCoreApi(
      view: playerView(
        queue: songs,
        index: 1,
        current: songs[1],
        durationMs: songs[1].durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await openFullPlayer(tester);

    final swipe = find.byKey(const Key('now-playing-swipe'));
    final current = find.byKey(const Key('now-playing-current-cover'));
    expect(swipe, findsOneWidget);
    expect(current, findsOneWidget);
    expect(find.byKey(const Key('now-playing-next-cover')), findsOneWidget);
    expect(find.byKey(const Key('now-playing-previous-cover')), findsOneWidget);
    expect(
      find.descendant(
        of: current,
        matching: find.byKey(const ValueKey('now-playing-cover-song-b')),
      ),
      findsOneWidget,
    );

    final start = tester.getCenter(current);
    final gesture = await tester.startGesture(tester.getCenter(swipe));
    await tester.pump();
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump();
    final dragged = tester.getCenter(current);
    expect(dragged.dx, lessThan(start.dx - 60));

    await gesture.up();
    await tester.pump();
    // The card animates out before the transport call, so the switch is not a
    // hard cut.
    expect(api.nexts, 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(api.nexts, 0);
    await tester.pumpAndSettle();
    expect(api.nexts, 1);
    expect(api.previouses, 0);
    // Optimistic target: the cover switches even before the fake core emits.
    expect(
      find.descendant(
        of: current,
        matching: find.byKey(const ValueKey('now-playing-cover-song-c')),
      ),
      findsOneWidget,
    );
    expect(tester.getCenter(current).dx, closeTo(start.dx, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the cover right commits to the previous track', (
    tester,
  ) async {
    final songs = sampleQueue();
    final api = FakeCoreApi(
      view: playerView(
        queue: songs,
        index: 1,
        current: songs[1],
        durationMs: songs[1].durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await openFullPlayer(tester);

    final current = find.byKey(const Key('now-playing-current-cover'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('now-playing-swipe'))),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(api.previouses, 1);
    expect(api.nexts, 0);
    expect(
      find.descendant(
        of: current,
        matching: find.byKey(const ValueKey('now-playing-cover-song-a')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short cover drag springs back without switching', (
    tester,
  ) async {
    final songs = sampleQueue();
    final api = FakeCoreApi(
      view: playerView(
        queue: songs,
        index: 1,
        current: songs[1],
        durationMs: songs[1].durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await openFullPlayer(tester);

    final swipe = find.byKey(const Key('now-playing-swipe'));
    final current = find.byKey(const Key('now-playing-current-cover'));
    final start = tester.getCenter(current);
    final gesture = await tester.startGesture(tester.getCenter(swipe));
    await tester.pump();
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getCenter(current).dx, lessThan(start.dx - 10));

    // Pause so the release has no fling velocity, then let the spring settle.
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(api.nexts, 0);
    expect(api.previouses, 0);
    expect(tester.getCenter(current).dx, closeTo(start.dx, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cover drag with no adjacent track only bounces', (
    tester,
  ) async {
    final song = sampleSong(id: 'only-song', title: '唯一歌曲');
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
    await openFullPlayer(tester);

    expect(find.byKey(const Key('now-playing-next-cover')), findsNothing);
    expect(find.byKey(const Key('now-playing-previous-cover')), findsNothing);
    final swipe = find.byKey(const Key('now-playing-swipe'));
    final current = find.byKey(const Key('now-playing-current-cover'));
    final start = tester.getCenter(current);
    final gesture = await tester.startGesture(tester.getCenter(swipe));
    await tester.pump();
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-176, 0));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getCenter(current).dx, lessThan(start.dx - 10));

    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(api.nexts, 0);
    expect(api.previouses, 0);
    expect(tester.getCenter(current).dx, closeTo(start.dx, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fast flick commits with little cover travel', (tester) async {
    final songs = sampleQueue();
    final api = FakeCoreApi(
      view: playerView(
        queue: songs,
        index: 1,
        current: songs[1],
        durationMs: songs[1].durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await openFullPlayer(tester);

    await tester.fling(
      find.byKey(const Key('now-playing-swipe')),
      const Offset(-36, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(api.nexts, 1);
    expect(api.previouses, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping the compact bar follows the finger and switches', (
    tester,
  ) async {
    final songs = sampleQueue();
    final api = FakeCoreApi(
      view: playerView(
        queue: songs,
        index: 1,
        current: songs[1],
        durationMs: songs[1].durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    final playerBar = find.byType(PlayerBar);
    final navigation = find.byType(NavigationBar);
    expect(playerBar, findsOneWidget);
    expect(navigation, findsOneWidget);
    expect(
      tester.getBottomLeft(playerBar).dy,
      lessThanOrEqualTo(tester.getTopLeft(navigation).dy),
    );
    final cardMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(PlayerCard),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      (cardMaterial.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(22),
    );

    final swipe = find.byKey(const Key('player-bar-swipe'));
    final track = find.byKey(const Key('player-bar-track'));
    expect(swipe, findsOneWidget);
    expect(track, findsOneWidget);
    expect(find.text('歌曲 B'), findsOneWidget);
    final start = tester.getCenter(track);
    final gesture = await tester.startGesture(tester.getCenter(swipe));
    await tester.pump();
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump();
    expect(tester.getCenter(track).dx, lessThan(start.dx - 5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(api.nexts, 1);
    expect(api.previouses, 0);
    // The title follows the optimistic track while the core catches up.
    expect(find.text('歌曲 C'), findsOneWidget);
    expect(tester.getCenter(track).dx, closeTo(start.dx, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue opens on the current track and drag handle reorders', (
    tester,
  ) async {
    final songs = [
      for (var i = 0; i < 20; i++) sampleSong(id: 'queue-$i', title: '队列歌曲 $i'),
    ];
    final api = FakeCoreApi(
      view: playerView(
        queue: songs,
        index: 12,
        current: songs[12],
        durationMs: songs[12].durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );

    await tester.tap(find.byKey(const Key('queue-button')));
    await tester.pumpAndSettle();

    final panel = find.byType(QueuePanel);
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('队列歌曲 12')),
      findsOneWidget,
    );
    // The first row is off-screen, proving the list opened around index 12.
    expect(
      find.descendant(of: panel, matching: find.text('队列歌曲 0')),
      findsNothing,
    );

    final handle = find.descendant(
      of: panel,
      matching: find.byKey(const Key('queue-drag-handle-12')),
    );
    expect(handle, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveBy(const Offset(0, 110));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(api.moves, isNotEmpty);
    expect(api.moves.first.$1, 12);
    expect(tester.takeException(), isNull);
  });
}

/// Three queue entries so the middle track has both neighbours.
List<Song> sampleQueue() => [
  sampleSong(id: 'song-a', title: '歌曲 A'),
  sampleSong(id: 'song-b', title: '歌曲 B'),
  sampleSong(id: 'song-c', title: '歌曲 C'),
];

/// The shared [NowPlayingBody] order: restart, previous, play/pause, next,
/// playback mode. Uses the rendered x positions so a relayout that produces
/// overflow is still caught.
Future<void> expectNowPlayingControlOrder(WidgetTester tester) async {
  final body = find.byType(NowPlayingBody);
  expect(body, findsOneWidget);
  Finder inBody(Finder finder) => find.descendant(of: body, matching: finder);

  final mode = inBody(find.byKey(const Key('playback-mode')));
  await tester.ensureVisible(mode);
  await tester.pumpAndSettle();
  expect(mode, findsOneWidget);

  final restart = tester.getCenter(
    inBody(find.byKey(const Key('now-playing-restart'))),
  );
  final previous = tester.getCenter(inBody(find.byTooltip('上一首')));
  final play = tester.getCenter(inBody(find.byKey(const Key('play-pause'))));
  final next = tester.getCenter(inBody(find.byTooltip('下一首')));
  final modeCenter = tester.getCenter(mode);

  expect(restart.dx, lessThan(previous.dx));
  expect(previous.dx, lessThan(play.dx));
  expect(play.dx, lessThan(next.dx));
  expect(next.dx, lessThan(modeCenter.dx));
}
