import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zero_beat_rpc/client.dart';
import 'package:zero_beat_rpc/engine_host.dart';
import 'package:zero_beat_rpc/src/outbox.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

void main() {
  final root = Directory.current.path.endsWith('zero_beat_rpc')
      ? Directory.current.parent.parent
      : Directory.current;

  Map<String, Object?> load(String name) {
    final file = File('${root.path}/testdata/rpc/$name');
    final decoded = jsonDecode(file.readAsStringSync());
    return (decoded as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  test('bad token and version errors decode', () {
    final errors = load('errors.json');
    final unauthorized = RpcMessage.parseLine(
      jsonEncode(errors['unauthorized']),
    );
    expect(unauthorized.error?.code, RpcCode.unauthorized);
    expect(unauthorized.error?.message, '鉴权失败');
    expect(unauthorized.error?.data, isEmpty);

    final version = RpcMessage.parseLine(jsonEncode(errors['version']));
    expect(version.error?.code, RpcCode.version);
    expect(version.error?.message, '需要升级客户端');
    expect(version.error?.data['api'], 1);
  });

  test('frame limits match the RPC contract', () {
    expect(rpcHelloFrameBytes, 16 * 1024);
    expect(rpcMaxFrameBytes, 8 * 1024 * 1024);
    expect(timeoutFor(RpcMethod.pause), const Duration(seconds: 3));
    expect(timeoutFor(RpcMethod.search), const Duration(seconds: 20));
    expect(timeoutFor(RpcMethod.openLink), const Duration(seconds: 20));
  });

  test('position frames coalesce and reliable overflow is visible', () {
    final box = FrameOutbox(limit: 2);
    expect(
      box.add(OutboundFrame('p1\n', position: true, playbackId: 'pb', seq: 1)),
      isTrue,
    );
    expect(
      box.add(OutboundFrame('p2\n', position: true, playbackId: 'pb', seq: 2)),
      isTrue,
    );
    expect(box.items.single.payload, 'p2\n');
    expect(
      box.add(OutboundFrame('end\n', terminal: true, playbackId: 'pb')),
      isTrue,
    );
    expect(
      box.add(OutboundFrame('p3\n', position: true, playbackId: 'pb', seq: 3)),
      isTrue,
    );
    expect(box.items.map((item) => item.payload), ['p2\n', 'end\n']);
    expect(box.add(OutboundFrame('state\n', playbackId: 'pb')), isFalse);
    expect(box.overflowed, isTrue);
  });

  test(
    'version mismatch is fatal and a bad token does not stay connected',
    () async {
      final harness = await PeerHarness.start();
      addTearDown(harness.close);
      final errors = load('errors.json');

      await harness.expectHelloError(errors['version'], RpcCode.version);
      await harness.expectHelloError(
        errors['unauthorized'],
        RpcCode.unauthorized,
      );
    },
  );

  test(
    'pause timeout cancels the odd request',
    () async {
      final harness = await PeerHarness.start();
      addTearDown(harness.close);
      final opened = await harness.handshake();
      final pending = opened.client.pause();
      final pause = jsonDecode(await opened.reader.next()) as Map;
      expect(pause['id'], 3);
      expect(pause['method'], RpcMethod.pause);
      await expectLater(
        pending,
        throwsA(
          isA<RpcException>().having(
            (error) => error.code,
            'code',
            RpcCode.cancelled,
          ),
        ),
      );
      final cancel = jsonDecode(await opened.reader.next()) as Map;
      expect(cancel['id'], 5);
      expect(cancel['method'], RpcMethod.cancel);
      expect((cancel['params'] as Map)['rpc_id'], 3);
    },
    timeout: const Timeout(Duration(seconds: 8)),
  );

  test('stop sends an acknowledged transport command', () async {
    final harness = await PeerHarness.start();
    addTearDown(harness.close);
    final opened = await harness.handshake();
    final stopped = opened.client.stop();
    final request = jsonDecode(await opened.reader.next()) as Map;
    expect(request['method'], RpcMethod.stop);
    opened.socket.write(
      '${jsonEncode({'jsonrpc': '2.0', 'id': request['id'], 'result': <String, Object?>{}})}\n',
    );
    await stopped;
    expect(opened.client.connected, isTrue);
  });

  test(
    'outbound overflow closes the socket instead of dropping a reliable frame',
    () async {
      final harness = await PeerHarness.start();
      addTearDown(harness.close);
      final opened = await harness.handshake(queueLimit: 2);
      opened.client.holdWrites = Completer<void>();
      opened.client.sendEngineState(
        playbackId: 'pb',
        seq: 1,
        state: 'playing',
        positionMs: 0,
        durationMs: 1,
      );
      opened.client.sendEngineState(
        playbackId: 'pb',
        seq: 2,
        state: 'playing',
        positionMs: 10,
        durationMs: 1,
      );
      opened.client.sendEngineState(
        playbackId: 'pb',
        seq: 3,
        state: 'paused',
        positionMs: 20,
        durationMs: 1,
      );
      expect(opened.client.connected, isFalse);
      await expectLater(opened.client.play(), throwsA(isA<RpcException>()));
    },
  );

  test(
    'socket drop stops playback and the next hello does not replay commands',
    () async {
      final harness = await PeerHarness.start();
      addTearDown(harness.close);
      final first = await harness.handshake();
      final seen = first.client.states.firstWhere(
        (view) => view.playbackId == 'pb_01',
      );
      first.sendPlayerState('pb_01');
      await seen;
      await first.socket.close();
      for (var i = 0; i < 50 && first.client.connected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(first.client.connected, isFalse);
      expect(harness.host.stops, ['pb_01']);
      await expectLater(
        first.client.play(songId: 'bilibili:BV1demo:1'),
        throwsA(
          isA<RpcException>().having(
            (error) => error.code,
            'code',
            RpcCode.closed,
          ),
        ),
      );

      final second = await harness.handshake();
      expect(second.hello['method'], RpcMethod.hello);
      expect(second.hello['id'], 1);
      expect(second.client.connected, isTrue);
    },
  );
  test(
    'native ownership rolls back invalid start output, but never stops another core',
    () async {
      var stops = 0;
      Future<void> stop() async {
        stops++;
      }

      await expectLater(
        NativeCore.start(
          platform: 'linux',
          startNative: (_) async => jsonEncode({'ok': true, 'api': 999}),
          stopNative: stop,
        ),
        throwsA(isA<RpcException>()),
      );
      expect(stops, 1);
      await expectLater(
        NativeCore.start(
          platform: 'linux',
          startNative: (_) async =>
              jsonEncode({'ok': false, 'code': 'already_running'}),
          stopNative: stop,
        ),
        throwsA(isA<RpcException>()),
      );
      expect(stops, 1);
    },
  );

  test(
    'connection drop emits false and retains the authenticated hello result',
    () async {
      final harness = await PeerHarness.start();
      addTearDown(harness.close);
      final peer = await harness.handshake();
      expect(peer.client.helloResult!.coreVersion, '0.8.0');
      final dropped = peer.client.connections.firstWhere(
        (connected) => !connected,
      );
      peer.socket.destroy();
      expect(await dropped, isFalse);
      await peer.client.close();
      expect(peer.client.helloResult, isNotNull);
    },
  );
}

class FakeHost implements EngineHost {
  final stops = <String>[];

  @override
  List<String> get capabilities => const ['clip'];

  @override
  Future<void> load(EngineLoad request) async {}

  @override
  Future<void> pause(String playbackId) async {}

  @override
  Future<void> resume(String playbackId) async {}

  @override
  Future<void> stop(String playbackId) async {
    stops.add(playbackId);
  }

  @override
  Future<void> seek(String playbackId, int positionMs) async {}

  @override
  Future<void> volume(String playbackId, double volume) async {}

  @override
  Future<void> compensation(String playbackId, double compDb) async {}

  @override
  Future<void> autoGain(String playbackId, bool enabled) async {}

  @override
  EngineReport reportState() => EngineReport(
    playbackId: null,
    seq: 0,
    state: 'idle',
    positionMs: 0,
    durationMs: 0,
  );
}

class OpenedPeer {
  OpenedPeer(this.client, this.socket, this.reader, this.hello);

  final RpcClient client;
  final Socket socket;
  final LineReader reader;
  final Map<String, Object?> hello;

  void sendPlayerState(String playbackId) {
    socket.write(
      '${jsonEncode({
        'jsonrpc': '2.0',
        'method': 'player.state',
        'params': {'playback_id': playbackId, 'play_when_ready': true, 'notice': '', 'notice_level': '', 'snapshot': _snapshot()},
      })}\n',
    );
  }
}

class PeerHarness {
  PeerHarness._(this.server) {
    server.listen((socket) {
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(socket);
      } else {
        _pending.add(socket);
      }
    });
  }

  final ServerSocket server;
  final FakeHost host = FakeHost();
  final List<Socket> _pending = [];
  final List<Completer<Socket>> _waiters = [];

  static Future<PeerHarness> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return PeerHarness._(server);
  }

  Future<String> Function(String configJson) get _start =>
      (config) async => jsonEncode({
        'ok': true,
        'port': server.port,
        'token': '00112233445566778899aabbccddeeff',
        'api': 1,
        'repo': 3,
        'version': rpcClientVersion,
      });

  Future<Socket> _accept() {
    if (_pending.isNotEmpty) return Future<Socket>.value(_pending.removeAt(0));
    final waiter = Completer<Socket>();
    _waiters.add(waiter);
    return waiter.future;
  }

  Future<OpenedPeer> handshake({int queueLimit = 64}) async {
    final opening = openCore(
      host: host,
      platform: 'linux',
      dataDir: '/tmp/zero-beat',
      lock: false,
      startNative: _start,
      stopNative: () async {},
      queueLimit: queueLimit,
    );
    final socket = await _accept();
    final reader = LineReader(socket);
    final hello = (jsonDecode(await reader.next()) as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    expect(hello['method'], RpcMethod.hello);
    final helloId = hello['id'];
    if (helloId is! int || !helloId.isOdd) {
      fail('hello id must be an odd integer, got $helloId');
    }
    socket.write('${jsonEncode(_helloResult())}\n');
    final client = await opening as RpcClient;
    return OpenedPeer(client, socket, reader, hello);
  }

  Future<void> expectHelloError(Object? errorFrame, int code) async {
    final opening = openCore(
      host: host,
      platform: 'linux',
      lock: false,
      startNative: _start,
      stopNative: () async {},
    );
    final socket = await _accept();
    final reader = LineReader(socket);
    final hello = jsonDecode(await reader.next()) as Map;
    expect(hello['method'], RpcMethod.hello);
    socket.write('${jsonEncode(errorFrame)}\n');
    await expectLater(
      opening,
      throwsA(isA<RpcException>().having((error) => error.code, 'code', code)),
    );
    try {
      await socket.close();
    } catch (_) {}
  }

  Future<void> close() => server.close();
}

Map<String, Object?> _helloResult() => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': {
    'api': 1,
    'repo': 3,
    'core_version': '0.8.0',
    'gui_version': '0.1.0-dev',
    'data_dir': '/tmp/zero-beat',
    'capabilities': ['library', 'search', 'link', 'player', 'clip'],
    'account': {
      'bilibili': {'logged_in': false, 'name': ''},
      'netease': {'logged_in': false, 'name': ''},
    },
    'player': {
      'playback_id': null,
      'play_when_ready': false,
      'notice': '',
      'notice_level': '',
      'snapshot': _snapshot(),
    },
  },
};

Map<String, Object?> _snapshot() => {
  'queue': <Object?>[],
  'index': 0,
  'current': null,
  'state': 'idle',
  'position_ms': 0,
  'duration_ms': 0,
  'mode': 'list_loop',
  'volume': 0.8,
  'comp_db': 0,
  'song_comp_db': 0,
  'auto_gain': false,
  'muted': false,
  'awaiting': false,
  'request_id': 0,
  'sleep_until': null,
  'quality': 'auto',
};

class LineReader {
  LineReader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.addAll(data);
        _drain();
      },
      onDone: () {
        if (_waiters.isNotEmpty && _buffer.isEmpty) {
          _waiters.removeAt(0).completeError(StateError('socket closed'));
        }
      },
    );
  }

  final List<int> _buffer = [];
  final List<Completer<String>> _waiters = [];
  late final StreamSubscription<List<int>> _subscription;

  Future<String> next() {
    final waiter = Completer<String>();
    _waiters.add(waiter);
    _drain();
    return waiter.future;
  }

  void _drain() {
    while (_waiters.isNotEmpty) {
      final newline = _buffer.indexOf(10);
      if (newline < 0) return;
      final line = utf8.decode(_buffer.sublist(0, newline));
      _buffer.removeRange(0, newline + 1);
      _waiters.removeAt(0).complete(line);
    }
  }

  Future<void> cancel() => _subscription.cancel();
}
