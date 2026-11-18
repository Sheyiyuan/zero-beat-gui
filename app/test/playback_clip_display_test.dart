import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/engine/playback_host.dart';
import 'package:zero_beat_gui/features/lyrics_page.dart';
import 'package:zero_beat_gui/features/playback_clip.dart';
import 'package:zero_beat_gui/features/session.dart';
import 'package:zero_beat_core/engine_contract.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart' show PlayerView;
import 'package:zero_beat_rpc/engine_host.dart';
import 'package:zero_beat_gui/shared/playback.dart';

import 'full_feature_test.dart';
import 'support/samples.dart';

EngineLoad _engineLoad(String id, {int clipEndMs = 0, int clipStartMs = 0}) {
  return EngineLoad(
    playbackId: id,
    stream: EngineStream(
      url: 'https://example.test/$id',
      headers: const {'Referer': 'https://example.test'},
      codec: 'mp3',
      durationMs: 180_000,
      quality: 'auto',
      clipStartMs: clipStartMs,
      clipEndMs: clipEndMs,
    ),
    startAtMs: 0,
    playWhenReady: true,
    volume: 0.8,
    compDb: 0,
    autoGain: false,
  );
}

PlaybackHost _testHost() {
  return PlaybackHost(
    createPlayer: () => throw UnimplementedError(),
    enablePositionClock: false,
  );
}

ProviderContainer _clipContainer({
  required FeatureApi api,
  required PlaybackHost host,
  required PlayerView view,
  PlayerController? player,
}) {
  final harness = player ?? (_HarnessPlayer()..seed(view));
  return ProviderContainer(
    overrides: [
      coreApiProvider.overrideWithValue(api),
      playbackHostProvider.overrideWithValue(host),
      playerProvider.overrideWith(() => harness),
    ],
  );
}

class _HarnessPlayer extends PlayerController {
  PlayerView _view = playerView();
  void seed(PlayerView view) => _view = view;
  @override
  PlayerView build() => _view;
  @override
  void show(PlayerView view) => state = view;
}

void main() {
  test('applyClipBounds updates host and notifies', () async {
    final host = _testHost();
    addTearDown(host.close);
    await host.load(_engineLoad('pb-1', clipEndMs: 80_000));
    host.applyClipBounds(startMs: 72_000, endMs: 168_000);
    expect(host.activeClipStartMs, 72_000);
    expect(host.activeClipEndMs, 168_000);
  });

  testWidgets('clear works with invalid start field', (tester) async {
    final song = sampleSong();
    final api = FeatureApi()
      ..view = playerView(current: song, durationMs: 180_000);
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

  test('afterClipEdit syncs override and host clip', () async {
    final song = sampleSong();
    final host = _testHost();
    addTearDown(host.close);
    await host.load(_engineLoad('live', clipEndMs: 0));
    final api = FeatureApi()
      ..view = playerView(
        current: song,
        durationMs: 180_000,
        playbackId: 'live',
      );
    addTearDown(api.closeControllers);
    final container = _clipContainer(api: api, host: host, view: api.view);
    addTearDown(container.dispose);
    container.read(displayedClipProvider);
    container
        .read(displayedClipProvider.notifier)
        .afterClipEdit(
          songId: song.id,
          action: 'save',
          startMs: 72_000,
          endMs: 168_000,
        );
    expect(container.read(displayedClipProvider)?.startMs, 72_000);
    final line = playbackClipSubtitle(
      clipStartMs: 72_000,
      clipEndMs: 168_000,
      positionMs: 0,
    );
    expect(line, contains('片段'));
    container
        .read(displayedClipProvider.notifier)
        .afterClipEdit(songId: song.id, action: 'clear', startMs: 0, endMs: 0);
    expect(container.read(displayedClipProvider), isNull);
  });

  test('clip override does not follow another song', () async {
    final song = sampleSong();
    final other = sampleSong(id: 'other', title: '另一首');
    final host = _testHost();
    addTearDown(host.close);
    await host.load(_engineLoad('live', clipEndMs: 0));
    final api = FeatureApi()
      ..view = playerView(
        current: song,
        durationMs: 180_000,
        playbackId: 'live',
      );
    addTearDown(api.closeControllers);
    final player = _HarnessPlayer()..seed(api.view);
    final container = _clipContainer(
      api: api,
      host: host,
      view: api.view,
      player: player,
    );
    addTearDown(container.dispose);
    container.read(displayedClipProvider);
    container
        .read(displayedClipProvider.notifier)
        .afterClipEdit(
          songId: song.id,
          action: 'save',
          startMs: 72_000,
          endMs: 168_000,
        );
    player.show(
      playerView(current: other, durationMs: 180_000, playbackId: 'live'),
    );
    expect(container.read(displayedClipProvider), isNull);
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
    player.show(playerView(current: song, durationMs: 180_000));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存片段'))
          .onPressed,
      isNotNull,
    );
  });
}
