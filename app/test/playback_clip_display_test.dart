import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/engine/engine_player.dart';
import 'package:zero_beat_gui/engine/playback_host.dart';
import 'package:zero_beat_gui/features/lyrics_page.dart';
import 'package:zero_beat_gui/features/playback_clip.dart';
import 'package:zero_beat_gui/features/session.dart';
import 'package:zero_beat_core/engine_contract.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart' show CoreApi, PlayerView;
import 'package:zero_beat_rpc/engine_host.dart';
import 'package:zero_beat_gui/shared/playback.dart';

import 'full_feature_test.dart';
import 'support/samples.dart';

EngineLoad _engineLoad(
  String id, {
  int clipEndMs = 0,
  int clipStartMs = 0,
  int durationMs = 180000,
}) {
  return EngineLoad(
    playbackId: id,
    stream: EngineStream(
      url: 'https://example.test/$id',
      headers: const {'Referer': 'https://example.test'},
      codec: 'mp3',
      durationMs: durationMs,
      quality: 'auto',
      clipStartMs: clipStartMs,
      clipEndMs: clipEndMs,
    ),
    startAtMs: 0,
    playWhenReady: false,
    volume: 0.8,
    compDb: 0,
    autoGain: false,
  );
}

class _Rec implements EnginePlayer {
  EnginePlayerListener? listener;
  Duration? end;
  int stopCalls = 0;
  bool disposed = false;

  @override
  Future<void> open({
    required String url,
    required Map<String, String> headers,
    Duration? start,
    Duration? end,
    required bool play,
  }) async {
    this.end = end;
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double percent) async {}

  @override
  Future<bool> trySetFilter(String filter) async => true;

  @override
  void listen(EnginePlayerListener listener) {
    this.listener = listener;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _HarnessPlayer extends PlayerController {
  PlayerView _view = playerView();
  void seed(PlayerView view) => _view = view;

  @override
  PlayerView build() => _view;

  @override
  void show(PlayerView view) => state = view;
}

class _Opened {
  _Opened({
    required this.host,
    required this.players,
    required this.container,
    required this.player,
  });

  final PlaybackHost host;
  final List<_Rec> players;
  final ProviderContainer container;
  final _HarnessPlayer player;

  _Rec get media => players.last;
}

Future<_Opened> _openHost({
  required String playbackId,
  required PlayerView view,
  int clipStartMs = 0,
  int clipEndMs = 0,
  CoreApi? api,
  // Widget tests must close the host before returning. tearDown runs after
  // FakeAsync is gone, and PlaybackHost.close then waits on the load queue
  // created in that zone.
  bool closeInTearDown = true,
}) async {
  final players = <_Rec>[];
  final host = PlaybackHost(
    createPlayer: () {
      final player = _Rec();
      players.add(player);
      return player;
    },
    enablePositionClock: false,
  );
  if (closeInTearDown) addTearDown(host.close);
  await host.load(
    _engineLoad(playbackId, clipStartMs: clipStartMs, clipEndMs: clipEndMs),
  );
  await _flush();
  final harness = _HarnessPlayer()..seed(view);
  final container = ProviderContainer(
    overrides: [
      if (api != null) coreApiProvider.overrideWithValue(api),
      playbackHostProvider.overrideWithValue(host),
      playerProvider.overrideWith(() => harness),
    ],
  );
  addTearDown(container.dispose);
  container.read(displayedClipProvider);
  return _Opened(
    host: host,
    players: players,
    container: container,
    player: harness,
  );
}

void _at(_Rec player, int positionMs, {int durationMs = 180000}) {
  player.listener!.onPosition(
    Duration(milliseconds: positionMs),
    Duration(milliseconds: durationMs),
  );
}

void main() {
  test('engine load keeps the host end equal to the opened end', () async {
    final opened = await _openHost(
      playbackId: 'live',
      clipEndMs: 180000,
      view: playerView(current: sampleSong(), playbackId: 'live'),
    );
    expect(opened.host.activeClipEndMs, 180000);
    expect(opened.media.end, const Duration(milliseconds: 180000));
    _at(opened.media, 179999);
    expect(opened.host.terminalEvents, isEmpty);
    _at(opened.media, 180000);
    expect(opened.host.terminalEvents, hasLength(1));
    expect(opened.host.terminalEvents.single.playbackId, 'live');
    expect(opened.host.terminalEvents.single.state, 'ended');
    expect(opened.media.stopCalls, 1);
  });

  test(
    'save updates the subtitle only; playback end changes on the next load',
    () async {
      final song = sampleSong();
      final opened = await _openHost(
        playbackId: 'live',
        clipEndMs: 180000,
        view: playerView(current: song, durationMs: 180000, playbackId: 'live'),
      );
      var hostNotes = 0;
      opened.host.addListener(() => hostNotes++);
      final applied = opened.container
          .read(displayedClipProvider.notifier)
          .afterClipEdit(
            songId: song.id,
            playbackId: 'live',
            action: 'save',
            startMs: 72000,
            endMs: 90000,
          );
      expect(applied, isTrue);
      expect(hostNotes, 0);
      expect(opened.container.read(displayedClipProvider)?.endMs, 90000);
      expect(opened.host.activeClipStartMs, 0);
      expect(opened.host.activeClipEndMs, 180000);
      expect(opened.media.end, const Duration(milliseconds: 180000));
      _at(opened.media, 100000);
      expect(opened.host.terminalEvents, isEmpty);
      expect(opened.media.stopCalls, 0);

      await opened.host.load(
        _engineLoad('pb-2', clipStartMs: 72000, clipEndMs: 90000),
      );
      await _flush();
      opened.player.show(
        playerView(current: song, durationMs: 180000, playbackId: 'pb-2'),
      );
      expect(opened.host.activePlaybackId, 'pb-2');
      expect(opened.host.activeClipStartMs, 72000);
      expect(opened.host.activeClipEndMs, 90000);
      expect(opened.media.end, const Duration(milliseconds: 90000));
      expect(opened.container.read(displayedClipProvider)?.endMs, 90000);
      expect(opened.container.read(displayedClipProvider)?.startMs, 72000);
      _at(opened.media, 90000);
      expect(
        opened.host.terminalEvents.where((event) => event.playbackId == 'pb-2'),
        hasLength(1),
      );
      expect(opened.media.stopCalls, 1);
    },
  );

  test(
    'clear keeps the opened end until core reloads without a clip',
    () async {
      final song = sampleSong();
      final opened = await _openHost(
        playbackId: 'live',
        clipStartMs: 1000,
        clipEndMs: 80000,
        view: playerView(current: song, durationMs: 180000, playbackId: 'live'),
      );
      final applied = opened.container
          .read(displayedClipProvider.notifier)
          .afterClipEdit(
            songId: song.id,
            playbackId: 'live',
            action: 'clear',
            startMs: 0,
            endMs: 0,
          );
      expect(applied, isTrue);
      expect(opened.container.read(displayedClipProvider), isNull);
      expect(opened.host.activeClipEndMs, 80000);
      expect(opened.media.end, const Duration(milliseconds: 80000));
      _at(opened.media, 80000);
      expect(opened.host.terminalEvents, hasLength(1));
      expect(opened.media.stopCalls, 1);

      await opened.host.load(_engineLoad('pb-clear', clipEndMs: 0));
      await _flush();
      opened.player.show(
        playerView(current: song, durationMs: 180000, playbackId: 'pb-clear'),
      );
      expect(opened.host.activeClipEndMs, 0);
      expect(opened.media.end, isNull);
      expect(opened.container.read(displayedClipProvider), isNull);
      _at(opened.media, 80000);
      expect(
        opened.host.terminalEvents.where(
          (event) => event.playbackId == 'pb-clear',
        ),
        isEmpty,
      );
      expect(opened.media.stopCalls, 0);
    },
  );

  test(
    'a late edit does not rewrite a binding the host already replaced',
    () async {
      final song = sampleSong();
      final other = sampleSong(id: 'other', title: '下一首');
      final opened = await _openHost(
        playbackId: 'pb-1',
        clipEndMs: 180000,
        view: playerView(current: song, durationMs: 180000, playbackId: 'pb-1'),
      );
      await opened.host.load(_engineLoad('pb-2', clipEndMs: 5000));
      await _flush();
      final applied = opened.container
          .read(displayedClipProvider.notifier)
          .afterClipEdit(
            songId: song.id,
            playbackId: 'pb-1',
            action: 'preview',
            startMs: 72000,
            endMs: 90000,
          );
      expect(applied, isFalse);
      expect(opened.host.activePlaybackId, 'pb-2');
      expect(opened.host.activeClipEndMs, 5000);
      expect(opened.media.end, const Duration(milliseconds: 5000));
      expect(opened.media.stopCalls, 0);
      expect(opened.host.terminalEvents, isEmpty);
      _at(opened.media, 1000);
      expect(opened.host.terminalEvents, isEmpty);

      opened.player.show(
        playerView(current: other, durationMs: 180000, playbackId: 'pb-2'),
      );
      final shown = opened.container.read(displayedClipProvider);
      expect(shown?.endMs, isNot(90000));
      expect(opened.host.activeClipEndMs, 5000);
    },
  );

  test('a late edit does not follow a same-song reload', () async {
    final song = sampleSong();
    final opened = await _openHost(
      playbackId: 'pb-1',
      clipEndMs: 180000,
      view: playerView(current: song, durationMs: 180000, playbackId: 'pb-1'),
    );
    await opened.host.load(_engineLoad('pb-2', clipEndMs: 50000));
    await _flush();
    opened.player.show(
      playerView(current: song, durationMs: 180000, playbackId: 'pb-2'),
    );
    final applied = opened.container
        .read(displayedClipProvider.notifier)
        .afterClipEdit(
          songId: song.id,
          playbackId: 'pb-1',
          action: 'save',
          startMs: 72000,
          endMs: 90000,
        );
    expect(applied, isFalse);
    expect(opened.host.activeClipEndMs, 50000);
    expect(opened.media.end, const Duration(milliseconds: 50000));
    expect(opened.container.read(displayedClipProvider)?.endMs, 50000);
    expect(opened.host.terminalEvents, isEmpty);
    _at(opened.media, 50000);
    expect(opened.host.terminalEvents.single.playbackId, 'pb-2');
  });

  test(
    'rollbackPreview restores the subtitle and leaves the open end',
    () async {
      final song = sampleSong();
      final opened = await _openHost(
        playbackId: 'live',
        clipStartMs: 1000,
        clipEndMs: 8000,
        view: playerView(current: song, durationMs: 180000, playbackId: 'live'),
      );
      final notifier = opened.container.read(displayedClipProvider.notifier);
      expect(
        notifier.afterClipEdit(
          songId: song.id,
          playbackId: 'live',
          action: 'preview',
          startMs: 72000,
          endMs: 90000,
        ),
        isTrue,
      );
      expect(opened.container.read(displayedClipProvider)?.endMs, 90000);
      notifier.rollbackPreview(
        songId: song.id,
        playbackId: 'live',
        previous: null,
      );
      expect(opened.container.read(displayedClipProvider)?.startMs, 1000);
      expect(opened.container.read(displayedClipProvider)?.endMs, 8000);
      expect(opened.host.activeClipEndMs, 8000);
      expect(opened.media.end, const Duration(milliseconds: 8000));
      expect(opened.host.terminalEvents, isEmpty);
      expect(opened.media.stopCalls, 0);
    },
  );

  test(
    'rollbackPreview does not install the old range on the next playback',
    () async {
      final song = sampleSong();
      final opened = await _openHost(
        playbackId: 'pb-1',
        clipEndMs: 180000,
        view: playerView(current: song, durationMs: 180000, playbackId: 'pb-1'),
      );
      final notifier = opened.container.read(displayedClipProvider.notifier);
      expect(
        notifier.afterClipEdit(
          songId: song.id,
          playbackId: 'pb-1',
          action: 'preview',
          startMs: 72000,
          endMs: 90000,
        ),
        isTrue,
      );
      await opened.host.load(_engineLoad('pb-2', clipEndMs: 5000));
      await _flush();
      notifier.rollbackPreview(
        songId: song.id,
        playbackId: 'pb-1',
        previous: const ClipUiOverride(
          songId: 'song-1',
          playbackId: 'pb-1',
          startMs: 1000,
          endMs: 8000,
        ),
      );
      expect(opened.host.activePlaybackId, 'pb-2');
      expect(opened.host.activeClipEndMs, 5000);
      expect(opened.media.end, const Duration(milliseconds: 5000));
      expect(opened.media.stopCalls, 0);
      opened.player.show(
        playerView(current: song, durationMs: 180000, playbackId: 'pb-2'),
      );
      expect(opened.container.read(displayedClipProvider)?.endMs, isNot(90000));
      expect(opened.container.read(displayedClipProvider)?.endMs, isNot(8000));
      expect(opened.host.activeClipEndMs, 5000);
    },
  );

  test('clip override does not follow another song', () async {
    final song = sampleSong();
    final other = sampleSong(id: 'other', title: '另一首');
    final opened = await _openHost(
      playbackId: 'live',
      view: playerView(current: song, durationMs: 180000, playbackId: 'live'),
    );
    final applied = opened.container
        .read(displayedClipProvider.notifier)
        .afterClipEdit(
          songId: song.id,
          playbackId: 'live',
          action: 'save',
          startMs: 72000,
          endMs: 168000,
        );
    expect(applied, isTrue);
    expect(opened.host.activeClipEndMs, 0);
    expect(opened.media.end, isNull);
    opened.player.show(
      playerView(current: other, durationMs: 180000, playbackId: 'live'),
    );
    expect(opened.container.read(displayedClipProvider), isNull);
    expect(opened.host.activeClipEndMs, 0);
  });

  testWidgets('clear works with invalid start field', (tester) async {
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
    await tester.enterText(find.byType(TextField).first, '');
    await tester.enterText(find.byType(TextField).last, '40');
    await tester.pump();
    await tester.tap(find.text('清除片段'));
    await tester.pumpAndSettle();
    expect(
      api.calls.where(
        (c) => c.$1 == 'player.clip.edit' && c.$2['action'] == 'clear',
      ),
      isNotEmpty,
    );
    expect(find.text('请输入有效秒数'), findsNothing);
  });

  testWidgets('unknown duration disables save until length arrives', (
    tester,
  ) async {
    final song = Song(
      id: 'song-1',
      source: SourceID.valueNetease,
      remoteId: 'song-1',
      page: 1,
      cid: BigInt.zero,
      title: '示例歌曲',
      artist: '示例歌手',
      album: '',
      durationMs: 0,
      cover: '',
    );
    final api = FeatureApi()..view = playerView(current: song, durationMs: 0);
    addTearDown(api.closeControllers);
    final player = _HarnessPlayer()
      ..seed(playerView(current: song, durationMs: 0));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreApiProvider.overrideWithValue(api),
          playerProvider.overrideWith(() => player),
        ],
        child: MaterialApp(
          home: Scaffold(body: ClipEditor(song: song)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存片段'))
          .onPressed,
      isNull,
    );
    player.show(playerView(current: song, durationMs: 180000));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存片段'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('preview then cancel restores the opened clip', (tester) async {
    final song = sampleSong();
    final api = FeatureApi()
      ..view = playerView(
        current: song,
        durationMs: 180000,
        playbackId: 'live',
      );
    addTearDown(api.closeControllers);
    final opened = await _openHost(
      playbackId: 'live',
      clipStartMs: 1000,
      clipEndMs: 8000,
      view: api.view,
      api: api,
      closeInTearDown: false,
    );
    await _pushEditor(tester, opened.container, song);
    expect(opened.container.read(displayedClipProvider)?.endMs, 8000);
    await _setClipFields(tester, '72', '90');
    final previewButton = find.widgetWithText(OutlinedButton, '从起点试听整首');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pump();
    await tester.pump();
    expect(
      api.calls.where(
        (call) =>
            call.$1 == 'player.clip.edit' && call.$2['action'] == 'preview',
      ),
      hasLength(1),
    );
    expect(opened.container.read(displayedClipProvider)?.endMs, 90000);
    expect(opened.host.activeClipStartMs, 1000);
    expect(opened.host.activeClipEndMs, 8000);
    expect(opened.media.end, const Duration(milliseconds: 8000));
    expect(opened.host.terminalEvents, isEmpty);
    expect(opened.media.stopCalls, 0);

    final cancel = find.widgetWithText(TextButton, '取消');
    await tester.ensureVisible(cancel);
    final cancelButton = tester.widget<TextButton>(cancel);
    expect(cancelButton.onPressed, isNotNull);
    cancelButton.onPressed!.call();
    await tester.pump();
    await tester.pump();
    expect(find.text('从起点试听整首'), findsNothing);
    expect(
      api.calls.where(
        (call) =>
            call.$1 == 'player.clip.edit' && call.$2['action'] == 'cancel',
      ),
      hasLength(1),
    );
    expect(opened.container.read(displayedClipProvider)?.startMs, 1000);
    expect(opened.container.read(displayedClipProvider)?.endMs, 8000);
    expect(opened.host.activeClipEndMs, 8000);
    expect(opened.media.end, const Duration(milliseconds: 8000));
    expect(opened.host.terminalEvents, isEmpty);
    expect(opened.media.stopCalls, 0);
    await opened.host.close();
  });

  testWidgets(
    'a preview result that returns after reload does not retarget the new open',
    (tester) async {
      final song = sampleSong();
      final api = _GatedApi()
        ..view = playerView(
          current: song,
          durationMs: 180000,
          playbackId: 'pb-1',
        );
      addTearDown(api.closeControllers);
      final opened = await _openHost(
        playbackId: 'pb-1',
        clipEndMs: 180000,
        view: api.view,
        api: api,
        closeInTearDown: false,
      );
      await _pushEditor(tester, opened.container, song);
      await _setClipFields(tester, '72', '90');
      final previewButton = find.widgetWithText(OutlinedButton, '从起点试听整首');
      await tester.ensureVisible(previewButton);
      await tester.tap(previewButton);
      for (var i = 0; i < 20 && api.gates.isEmpty; i++) {
        await tester.pump();
      }
      expect(api.gates, hasLength(1));

      await opened.host.load(_engineLoad('pb-2', clipEndMs: 50000));
      await _flush();
      opened.player.show(
        playerView(current: song, durationMs: 180000, playbackId: 'pb-2'),
      );
      await tester.pump();
      api.gates.single.complete();
      await tester.pump();
      await tester.pump();

      expect(opened.host.activePlaybackId, 'pb-2');
      expect(opened.host.activeClipEndMs, 50000);
      expect(opened.media.end, const Duration(milliseconds: 50000));
      expect(opened.container.read(displayedClipProvider)?.endMs, 50000);
      expect(opened.host.terminalEvents, isEmpty);
      expect(opened.media.stopCalls, 0);
      expect(api.calls.where((call) => call.$2['action'] == 'cancel'), isEmpty);
      await opened.host.close();
    },
  );
}

Future<void> _setClipFields(
  WidgetTester tester,
  String start,
  String end,
) async {
  final inputs = tester.widgetList<TextField>(find.byType(TextField)).toList();
  expect(inputs, hasLength(2));
  inputs[0].controller!.text = start;
  inputs[1].controller!.text = end;
  inputs[0].onChanged?.call(start);
  await tester.pump();
}

/// Flushes host open microtasks without scheduling a [Timer].
/// Widget tests freeze timers until [WidgetTester.pump], so [Future.delayed]
/// would never complete there.
Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.value();
  }
}

Future<void> _pushEditor(
  WidgetTester tester,
  ProviderContainer container,
  Song song,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    _InstantRoute<void>(
                      builder: (_) => Scaffold(body: ClipEditor(song: song)),
                    ),
                  );
                },
                child: const Text('打开片段'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开片段'));
  await tester.pump();
  await tester.pump();
  final error = tester.takeException();
  if (error != null) {
    fail('editor failed to open: $error');
  }
  expect(find.text('保存片段'), findsOneWidget);
}

class _InstantRoute<T> extends MaterialPageRoute<T> {
  _InstantRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

class _GatedApi extends FeatureApi {
  final gates = <Completer<void>>[];

  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) async {
    final result = await super.featureCall(method, params);
    if (method == 'player.clip.edit') {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    return result;
  }
}
