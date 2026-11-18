import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/engine_contract.dart';
import 'package:zero_beat_gui/engine/engine_player.dart';
import 'package:zero_beat_gui/engine/playback_host.dart';
import 'package:zero_beat_rpc/engine_host.dart';

void main() {
  test(
    'a stale player callback does not emit ended for the replacement',
    () async {
      final players = <_FakePlayer>[];
      final host = PlaybackHost(
        createPlayer: () {
          final player = _FakePlayer();
          players.add(player);
          return player;
        },
        enablePositionClock: false,
      );
      addTearDown(host.close);

      await host.load(_load('old'));
      await flush();
      await host.load(_load('new'));
      await flush();

      expect(players, hasLength(2));
      expect(players.first.disposed, isTrue);
      expect(players.last.disposed, isFalse);

      players.first.fireCompleted();

      expect(host.terminalEvents, isEmpty);
      expect(
        host.events.where((event) => event.kind == HostEventKind.ended),
        isEmpty,
      );
      expect(host.reportState().playbackId, isNot('old'));
    },
  );

  test('clip end emits ended once and an intentional stop does not', () async {
    final players = <_FakePlayer>[];
    final host = PlaybackHost(
      createPlayer: () {
        final player = _FakePlayer();
        players.add(player);
        return player;
      },
      enablePositionClock: false,
    );
    addTearDown(host.close);

    await host.load(_load('clip', clipEndMs: 1000));
    await flush();
    final player = players.single;
    player.listener!.onPosition(
      const Duration(milliseconds: 1000),
      const Duration(milliseconds: 4000),
    );
    player.listener!.onPosition(
      const Duration(milliseconds: 1200),
      const Duration(milliseconds: 4000),
    );
    player.fireCompleted();
    expect(
      host.terminalEvents.where((report) => report.state == 'ended'),
      hasLength(1),
    );
    expect(host.terminalEvents.single.playbackId, 'clip');

    await host.load(_load('stop'));
    await flush();
    await host.stop('stop');
    players.last.fireCompleted();
    expect(
      host.terminalEvents.where((report) => report.playbackId == 'stop'),
      isEmpty,
    );
  });

  test('playWhenReady false opens paused and stays paused', () async {
    final players = <_FakePlayer>[];
    final host = PlaybackHost(
      createPlayer: () {
        final player = _FakePlayer();
        players.add(player);
        return player;
      },
      enablePositionClock: false,
    );
    addTearDown(host.close);

    await host.load(_load('paused', playWhenReady: false, startAtMs: 1500));
    await flush();
    final player = players.single;
    expect(player.openedPlay, isFalse);
    expect(player.start, const Duration(milliseconds: 1500));
    expect(player.headers['Referer'], 'https://example.test');
    expect(host.reportState().state, 'paused');

    player.listener!.onPlaying(true);
    expect(player.pauseCalls, greaterThan(0));
    expect(host.reportState().state, 'paused');
  });

  test('loudnorm is omitted when the player cannot enable it', () async {
    final host = PlaybackHost(
      createPlayer: () => _FakePlayer(filterOk: false),
      enablePositionClock: false,
    );
    addTearDown(host.close);

    await host.prepare();
    expect(host.capabilities, ['clip']);
    expect(host.loudnormNotice, '当前播放器无法启用响度均衡');
  });
  test(
    'resuming a paused load updates intention, including buffering callbacks',
    () async {
      final player = _FakePlayer();
      final host = PlaybackHost(
        createPlayer: () => player,
        enablePositionClock: false,
      );
      addTearDown(host.close);
      await host.load(_load('paused', playWhenReady: false));
      await flush();
      final pauses = player.pauseCalls;
      await host.resume('paused');
      player.listener!.onPlaying(true);
      player.listener!.onBuffering(false);
      expect(player.pauseCalls, pauses);
      expect(host.reportState().state, 'playing');
      await host.pause('paused');
      player.listener!.onBuffering(true);
      player.listener!.onBuffering(false);
      expect(host.reportState().state, 'paused');
      await host.seek('paused', 1500);
      expect(host.reportState().state, 'paused');
    },
  );

  test(
    'slow open acknowledges promptly and pause is applied before any sound',
    () async {
      final gate = Completer<void>();
      final player = _FakePlayer(openGate: gate);
      final host = PlaybackHost(
        createPlayer: () => player,
        enablePositionClock: false,
      );
      addTearDown(host.close);
      await host.load(_load('slow')).timeout(const Duration(milliseconds: 100));
      await flush();
      expect(player.openedPlay, isFalse);
      await host.pause('slow').timeout(const Duration(milliseconds: 100));
      gate.complete();
      await flush();
      expect(player.playCalls, 0);
      expect(host.reportState().state, 'paused');
    },
  );

  test(
    'stop and replacement bypass slow open and stale callbacks stay isolated',
    () async {
      final gate = Completer<void>();
      final players = <_FakePlayer>[];
      final host = PlaybackHost(
        createPlayer: () {
          expect(players.where((p) => !p.disposed), isEmpty);
          final p = _FakePlayer(openGate: players.isEmpty ? gate : null);
          players.add(p);
          return p;
        },
        enablePositionClock: false,
      );
      addTearDown(host.close);
      await host.load(_load('old'));
      await flush();
      final oldListener = players.first.listener!;
      await host.stop('old').timeout(const Duration(milliseconds: 100));
      await host.load(_load('new'));
      await flush();
      expect(players, hasLength(2));
      gate.complete();
      await flush();
      oldListener.onPlaying(true);
      oldListener.onCompleted();
      oldListener.onError('late failure');
      expect(players.first.playCalls, 0);
      expect(host.reportState().playbackId, 'new');
      expect(host.terminalEvents, isEmpty);
    },
  );

  test('focus denial pauses without reporting a source failure', () async {
    final player = _FakePlayer();
    var denied = 0;
    final host = PlaybackHost(
      createPlayer: () => player,
      enablePositionClock: false,
    );
    host.acquireFocus = () async => false;
    host.onFocusDenied = () => denied++;
    addTearDown(host.close);
    await host.load(_load('focus'));
    await flush();
    expect(player.playCalls, 0);
    expect(denied, 1);
    expect(host.reportState().state, 'paused');
    expect(host.terminalEvents, isEmpty);
    expect(host.focusNotice, isNotEmpty);
  });

  test('pause while focus is pending prevents a late play', () async {
    final focus = Completer<bool>();
    final player = _FakePlayer();
    final host = PlaybackHost(
      createPlayer: () => player,
      enablePositionClock: false,
    )..acquireFocus = () => focus.future;
    addTearDown(host.close);
    await host.load(_load('focus'));
    await flush();
    await host.pause('focus');
    focus.complete(true);
    await flush();
    expect(player.playCalls, 0);
    expect(host.reportState().state, 'paused');
  });
}

EngineLoad _load(
  String id, {
  bool playWhenReady = true,
  int startAtMs = 0,
  int clipEndMs = 0,
}) {
  return EngineLoad(
    playbackId: id,
    stream: EngineStream(
      url: 'https://example.test/$id',
      headers: const {'Referer': 'https://example.test'},
      codec: 'mp3',
      durationMs: 4000,
      quality: 'auto',
      clipStartMs: 0,
      clipEndMs: clipEndMs,
    ),
    startAtMs: startAtMs,
    playWhenReady: playWhenReady,
    volume: 0.8,
    compDb: 0,
    autoGain: false,
  );
}

class _FakePlayer implements EnginePlayer {
  _FakePlayer({this.filterOk = true, this.openGate});
  final Completer<void>? openGate;
  int playCalls = 0;

  final bool filterOk;
  EnginePlayerListener? listener;
  bool disposed = false;
  bool openedPlay = false;
  Duration? start;
  Duration? end;
  Map<String, String> headers = const {};
  int pauseCalls = 0;

  void fireCompleted() => listener?.onCompleted();

  @override
  Future<void> open({
    required String url,
    required Map<String, String> headers,
    Duration? start,
    Duration? end,
    required bool play,
  }) async {
    this.headers = headers;
    this.start = start;
    this.end = end;
    openedPlay = play;
    await openGate?.future;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double percent) async {}

  @override
  Future<bool> trySetFilter(String filter) async => filterOk;

  @override
  void listen(EnginePlayerListener listener) {
    this.listener = listener;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
