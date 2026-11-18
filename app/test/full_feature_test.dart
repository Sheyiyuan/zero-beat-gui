import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/features/lyrics_page.dart';
import 'package:zero_beat_gui/shared/playback.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/features/settings_page.dart';
import 'package:zero_beat_gui/platform/desktop_window.dart';
import 'package:zero_beat_gui/shared/song_tile.dart';
import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

class FeatureApi extends FakeCoreApi implements CoreFeatureTransport {
  final calls = <(String, Map<String, Object?>)>[];
  final updates = StreamController<String>.broadcast();
  GUISettings preferences = defaultGUISettings();
  @override
  Stream<String> get changes => updates.stream;
  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) async {
    calls.add((method, params));
    switch (method) {
      case 'settings.gui.get':
        return preferences.toJson();
      case 'settings.gui.set':
        preferences = GUISettings.fromJson(
          Map<String, Object?>.from(params['settings'] as Map),
        );
        return {};
      case 'library.batch':
        return BatchResult(
          succeeded: ['song-1'],
          skipped: [],
          failed: [],
        ).toJson();
      case 'library.batch.start':
      case 'download.batch.start':
        return Work(
          id: 'job-1',
          action: 'batch.add',
          state: 'running',
          message: '',
        ).toJson();
      case 'tasks.batch_result':
        return {
          'task': Work(
            id: 'job-1',
            action: 'batch.add',
            state: 'completed',
            message: '',
          ).toJson(),
          'result': BatchResult(
            succeeded: ['song-1'],
            skipped: [],
            failed: [],
          ).toJson(),
        };
      case 'player.clip.begin':
        return {
          'token': 'epoch-1',
          'clip': Clip(startMs: 1000, endMs: 8000).toJson(),
        };
      case 'player.clip.edit':
        return {};
      case 'auth.accounts':
        return {'sources': <Object>[]};
      case 'browse.roots':
        return {'entries': <Object>[]};
      case 'content.comments':
        return {
          'source': 'netease',
          'page': 1,
          'has_more': false,
          'total': '0',
          'comments': <Object>[],
          'notice': '',
        };
      default:
        throw UnsupportedError(method);
    }
  }

  @override
  Future<void> closeControllers() async {
    await updates.close();
    await super.closeControllers();
  }
}

void main() {
  testWidgets('clip editor stays invalid after another song then same song', (
    tester,
  ) async {
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
    api.emit(playerView(current: sampleSong(id: 'other')));
    api.emit(playerView(current: song));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存片段'))
          .onPressed,
      isNull,
    );
    expect(find.text('当前歌曲已切换，此编辑已停止。请返回后重新打开。'), findsOneWidget);
    expect(api.calls.where((c) => c.$1 == 'player.clip.edit'), isEmpty);
  });
  test('window restoration keeps controls on an available monitor', () {
    const screen = Rect.fromLTWH(0, 0, 1280, 720);
    final restored = DesktopWindow.fitBounds(
      const Rect.fromLTWH(-4000, 2000, 1440, 960),
      [screen],
    );
    expect(screen.contains(restored.topLeft), isTrue);
    expect(restored.right, lessThanOrEqualTo(screen.right));
    expect(restored.bottom, lessThanOrEqualTo(screen.bottom));
  });
  testWidgets('desktop track playback sends the full playlist identity', (
    tester,
  ) async {
    final api = FeatureApi()
      ..libraryPlaylists = [samplePlaylist()]
      ..librarySongs = [sampleSong()];
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.desktop);
    await tester.tap(
      find.descendant(
        of: find.byType(SongTile),
        matching: find.byTooltip('播放'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.$1 == 'library.batch'), isNotEmpty);
    final call = api.calls.lastWhere((c) => c.$1 == 'library.batch');
    expect(call.$2['playlist_id'], 'list-1');
    expect(call.$2['target'], 'song-1');
    expect(call.$2['songs'], isEmpty);
  });
  testWidgets('feature route keeps desktop library and player visible', (
    tester,
  ) async {
    final api = FeatureApi()
      ..libraryPlaylists = [samplePlaylist(title: '保留的歌单')];
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.desktop);
    await tester.tap(find.byTooltip('账号'));
    await tester.pumpAndSettle();
    expect(find.text('保留的歌单'), findsOneWidget);
    expect(find.byKey(const Key('play-pause')), findsOneWidget);
    expect(api.helloCalls, 0);
  });
  testWidgets('mobile tabs retain independent feature routes', (tester) async {
    final api = FeatureApi();
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号与登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-field')), findsOneWidget);
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('账号'), findsOneWidget);
    expect(find.byKey(const Key('play-pause')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('账号与登录'), findsOneWidget);
    expect(api.pauses, 0);
  });
  testWidgets('disconnect blocks the root full player route too', (
    tester,
  ) async {
    final api = FeatureApi();
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
    );
    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
    api.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('与核心的连接已断开，播放已停止'), findsOneWidget);
    final button = tester.getCenter(find.byKey(const Key('play-pause')));
    await tester.tapAt(button);
    await tester.pump();
    expect(api.toggles, 0);
  });
  testWidgets('saved shortcut replaces default and preserves text editing', (
    tester,
  ) async {
    final api = FeatureApi()
      ..preferences = GUISettings(
        theme: 'system',
        palette: 'zero-red',
        accent: '',
        closeAction: 'background',
        shortcuts: {'toggle': 'P'},
        window: '',
      );
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.desktop);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.toggles, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(api.toggles, 1);
    await tester.tap(find.byKey(const Key('search-field')));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(api.toggles, 1);
  });
  testWidgets(
    'narrow desktop opens library drawer without changing layout mode',
    (tester) async {
      final api = FeatureApi()
        ..libraryPlaylists = [samplePlaylist(title: '窄窗歌单')];
      addTearDown(api.closeControllers);
      await pumpApp(
        tester,
        api: api,
        layout: AppLayout.desktop,
        size: const Size(700, 800),
      );
      expect(find.byTooltip('展开曲库'), findsOneWidget);
      expect(find.text('我的'), findsNothing);
      await tester.tap(find.byTooltip('展开曲库'));
      await tester.pumpAndSettle();
      expect(find.text('窄窗歌单'), findsOneWidget);
      await tester.tap(find.text('窄窗歌单'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('saved dark blue theme reaches window content and player', (
    tester,
  ) async {
    final api = FeatureApi()
      ..preferences = GUISettings(
        theme: 'dark',
        palette: 'hanpai-blue',
        accent: '',
        closeAction: 'background',
        shortcuts: {},
        window: '',
      );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      size: const Size(900, 700),
    );
    final theme = Theme.of(tester.element(find.byKey(const Key('play-pause'))));
    expect(theme.brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
