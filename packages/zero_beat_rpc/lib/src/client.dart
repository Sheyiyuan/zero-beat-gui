import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zero_beat_core/zero_beat_core.dart';

import 'api.dart';
import 'features.dart';
import 'engine_host.dart';
import 'envelope.dart';
import 'ffi_loader.dart';
import 'methods.dart';
import 'models.dart';
import 'outbox.dart';

const int _maxSafeInteger = 9007199254740991;

/// Owns a successful native start and its in-memory connection credentials.
/// Socket reconnection never starts a second native core.
class NativeCore {
  NativeCore._(
    this.port,
    this.socketPath,
    this._token,
    this.platform,
    this._stop,
  );
  final int port;
  final String socketPath;
  final String _token;
  final String platform;
  final Future<void> Function() _stop;
  bool _closed = false;

  static Future<NativeCore> start({
    required String platform,
    String dataDir = '',
    bool lock = true,
    Future<String> Function(String)? startNative,
    Future<void> Function()? stopNative,
  }) async {
    final raw = await (startNative ?? startZeroNative)(
      jsonEncode({'data_dir': dataDir, 'platform': platform, 'lock': lock}),
    );
    final body = jsonDecode(raw);
    if (body is! Map || body['ok'] != true) {
      throw RpcException(
        RpcCode.unavailable,
        body is Map ? body['message']?.toString() ?? '核心启动失败' : '核心启动失败',
        data: body is Map
            ? {
                'code': body['code'],
                if (body['pid'] != null) 'pid': body['pid'],
              }
            : {},
      );
    }
    final stop = stopNative ?? stopZeroNative;
    try {
      if (body['api'] != rpcApiVersion)
        throw RpcException(RpcCode.version, '需要升级客户端');
      final port = (body['port'] as num?)?.toInt() ?? 0;
      final socketPath = body['socket_path'] as String? ?? '';
      final token = body['token'] as String;
      final validAddress = socketPath.isEmpty
          ? port >= 1 && port <= 65535
          : platform == 'android' && socketPath.startsWith('/') && port == 0;
      if (!validAddress || token.isEmpty) throw FormatException('核心连接参数无效');
      return NativeCore._(port, socketPath, token, platform, stop);
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<RpcClient> connect({
    required EngineHost host,
    int queueLimit = 64,
  }) async {
    if (_closed) throw StateError('核心已关闭');
    // The owner must stop the old engine before handing it to a new connection.
    final state = host.reportState();
    if (state.state != 'idle' || state.playbackId != null)
      throw StateError('旧播放尚未停止');
    for (var attempt = 0; ; attempt++) {
      final socket = await Socket.connect(
        socketPath.isEmpty
            ? InternetAddress.loopbackIPv4
            : InternetAddress(socketPath, type: InternetAddressType.unix),
        port,
        timeout: const Duration(seconds: 3),
      );
      final client = RpcClient(
        socket: socket,
        host: host,
        queueLimit: queueLimit,
      );
      try {
        await client.hello(
          token: _token,
          platform: platform,
          engineCapabilities: host.capabilities,
        );
        return client;
      } catch (error) {
        await client.close();
        // A just-closed peer may still be persisting its final snapshot.
        if (error is! RpcException ||
            error.code != RpcCode.unavailable ||
            attempt >= 9)
          rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stop();
  }
}

/// Convenience for a single connection. Use NativeCore for runtime ownership
/// and reconnecting to the same native session.
Future<CoreApi> openCore({
  required EngineHost host,
  required String platform,
  String dataDir = '',
  bool lock = true,
  Future<String> Function(String configJson)? startNative,
  Future<void> Function()? stopNative,
  int queueLimit = 64,
}) async {
  final native = await NativeCore.start(
    platform: platform,
    dataDir: dataDir,
    lock: lock,
    startNative: startNative,
    stopNative: stopNative,
  );
  try {
    return await native.connect(host: host, queueLimit: queueLimit);
  } catch (_) {
    await native.close();
    rethrow;
  }
}

/// NDJSON JSON-RPC client. Odd request ids. Engine events are sent by the host
/// through [sendEnginePosition], [sendEngineState], [sendEngineEnded], and
/// [sendEngineFailed]. UI playback state comes only from [states] and [playerState].
class RpcClient implements CoreApi, CoreFeatureTransport {
  final _changes = StreamController<String>.broadcast();
  @override
  Stream<String> get changes => _changes.stream;
  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) => _call(method, params, (v) => v);
  RpcClient({
    required Socket socket,
    required this.host,
    int queueLimit = 64,
    this.holdWrites,
  }) : _socket = socket,
       _outbox = FrameOutbox(limit: queueLimit) {
    _subscription = _socket.listen(
      _onData,
      onError: (_) {
        unawaited(_drop());
      },
      onDone: () {
        unawaited(_drop());
      },
    );
    unawaited(_pump());
  }

  final EngineHost host;
  final Socket _socket;
  final FrameOutbox _outbox;
  final Map<int, Completer<RpcMessage>> _pending = {};
  final StreamController<PlayerView> _states =
      StreamController<PlayerView>.broadcast();
  final StreamController<String> _notices =
      StreamController<String>.broadcast();
  final List<int> _buffer = [];
  final _connections = StreamController<bool>.broadcast();
  HelloResult? _helloResult;
  Future<void>? _closing;

  @override
  HelloResult? get helloResult => _helloResult;

  @override
  Stream<bool> get connections => _connections.stream;

  late final StreamSubscription<List<int>> _subscription;

  /// Test hook. While this is incomplete the write pump does not drain.
  Completer<void>? holdWrites;

  bool _alive = true;
  bool _connected = false;
  bool _helloDone = false;
  bool _dropping = false;
  int _next = 1;
  String? _playbackId;
  Completer<void>? _wake;

  @override
  bool get connected => _connected;

  @override
  Stream<PlayerView> get states => _states.stream;

  @override
  Stream<String> get notices => _notices.stream;

  @override
  Future<HelloResult> hello({
    required String token,
    required String platform,
    required List<String> engineCapabilities,
  }) async {
    final result = await _call(RpcMethod.hello, {
      'token': token,
      'api': rpcApiVersion,
      'repo': rpcRepoVersion,
      'client_version': rpcClientVersion,
      'platform': platform,
      'engine_capabilities': engineCapabilities,
    }, HelloResult.fromJson);
    if (result.api != rpcApiVersion) {
      await _drop();
      throw RpcException(RpcCode.version, '需要升级客户端', data: {'api': result.api});
    }
    _helloResult = result;
    _helloDone = true;
    _connected = true;
    _connections.add(true);
    _playbackId = result.player.playbackId;
    if (!_states.isClosed) _states.add(result.player);
    return result;
  }

  @override
  Future<void> cancel(int rpcId) => _void(RpcMethod.cancel, {'rpc_id': rpcId});

  @override
  Future<PlaylistList> playlists() =>
      _call(RpcMethod.playlists, const {}, PlaylistList.fromJson);

  @override
  Future<SongPage> songs({
    required String playlistId,
    required int offset,
    required int limit,
  }) => _call(RpcMethod.songs, {
    'playlist_id': playlistId,
    'offset': offset,
    'limit': limit,
  }, SongPage.fromJson);

  @override
  Future<SearchView> search({
    required String keyword,
    required int page,
    String source = '',
  }) => _call(RpcMethod.search, {
    'keyword': keyword,
    'page': page,
    'source': source,
  }, SearchView.fromJson);

  @override
  Future<LinkView> openLink(String text) =>
      _call(RpcMethod.openLink, {'text': text}, LinkView.fromJson);

  @override
  Future<Accepted> play({
    String songId = '',
    Song? song,
    List<Song>? queue,
    int queueIndex = -1,
    int startAtMs = 0,
  }) {
    final params = <String, Object?>{
      'song_id': songId,
      'queue_index': queueIndex,
      'start_at_ms': startAtMs,
    };
    if (song != null) params['song'] = song.toJson();
    if (queue != null && queue.isNotEmpty) {
      params['queue'] = [for (final item in queue) item.toJson()];
    }
    return _call(RpcMethod.play, params, Accepted.fromJson);
  }

  @override
  Future<Accepted> toggle() =>
      _call(RpcMethod.toggle, const {}, Accepted.fromJson);

  @override
  Future<void> pause() => _void(RpcMethod.pause);

  @override
  Future<void> stop() => _void(RpcMethod.stop);

  @override
  Future<void> resume() => _void(RpcMethod.resume);

  @override
  Future<Accepted> next() => _call(RpcMethod.next, const {}, Accepted.fromJson);

  @override
  Future<Accepted> previous() =>
      _call(RpcMethod.previous, const {}, Accepted.fromJson);

  @override
  Future<void> seek(int positionMs) =>
      _void(RpcMethod.seek, {'position_ms': positionMs});

  @override
  Future<void> setVolume(double volume) =>
      _void(RpcMethod.volume, {'volume': volume});

  @override
  Future<void> setMode(String mode) => _void(RpcMethod.mode, {'mode': mode});

  @override
  Future<int> enqueue(Song song) => _call(RpcMethod.enqueue, {
    'song': song.toJson(),
  }, (json) => (json['index'] as num?)?.toInt() ?? 0);

  @override
  Future<int> insertNext(Song song) => _call(RpcMethod.insertNext, {
    'song': song.toJson(),
  }, (json) => (json['index'] as num?)?.toInt() ?? 0);

  @override
  Future<void> removeQueueAt(int index) =>
      _void(RpcMethod.queueRemove, {'index': index});

  @override
  Future<void> moveQueue(int index, int delta) =>
      _void(RpcMethod.queueMove, {'index': index, 'delta': delta});

  @override
  Future<void> clearQueue() => _void(RpcMethod.queueClear);

  @override
  Future<PlayerView> playerState() =>
      _call(RpcMethod.playerState, const {}, PlayerView.fromJson);

  @override
  Future<void> quit() => _void(RpcMethod.quit);

  @override
  Future<void> close() => _drop();

  void sendEnginePosition({
    required String playbackId,
    required int seq,
    required int positionMs,
    required int durationMs,
  }) {
    _emit(
      RpcMethod.enginePosition,
      {
        'playback_id': playbackId,
        'seq': seq,
        'position_ms': positionMs,
        'duration_ms': durationMs,
      },
      position: true,
      playbackId: playbackId,
      seq: seq,
    );
  }

  void sendEngineState({
    required String playbackId,
    required int seq,
    required String state,
    required int positionMs,
    required int durationMs,
  }) {
    _emit(RpcMethod.engineState, {
      'playback_id': playbackId,
      'seq': seq,
      'state': state,
      'position_ms': positionMs,
      'duration_ms': durationMs,
    }, playbackId: playbackId);
  }

  void sendEngineEnded({
    required String playbackId,
    required int seq,
    required int positionMs,
    required int durationMs,
  }) {
    _emit(
      RpcMethod.engineEnded,
      {
        'playback_id': playbackId,
        'seq': seq,
        'position_ms': positionMs,
        'duration_ms': durationMs,
      },
      terminal: true,
      playbackId: playbackId,
    );
  }

  void sendEngineFailed({
    required String playbackId,
    required int seq,
    required String error,
    int positionMs = 0,
    int durationMs = 0,
  }) {
    _emit(
      RpcMethod.engineFailed,
      {
        'playback_id': playbackId,
        'seq': seq,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'error': error,
      },
      terminal: true,
      playbackId: playbackId,
    );
  }

  Future<T> _call<T>(
    String method,
    Map<String, Object?> params,
    T Function(Map<String, Object?> json) decode,
  ) async {
    if (!_alive) throw RpcException(RpcCode.closed, '连接已断开');
    final id = _allocateId();
    final completer = Completer<RpcMessage>();
    _pending[id] = completer;
    final timer = Timer(timeoutFor(method), () {
      final pending = _pending.remove(id);
      if (pending == null || pending.isCompleted) return;
      pending.completeError(RpcException(RpcCode.cancelled, '已取消'));
      if (_alive) {
        _emit(RpcMethod.cancel, {'rpc_id': id}, id: _allocateId());
      }
    });
    if (!_emit(method, params, id: id)) {
      timer.cancel();
      _pending.remove(id);
      throw RpcException(RpcCode.closed, '连接已断开');
    }
    try {
      final message = await completer.future;
      final error = message.error;
      if (error != null) {
        if (error.code == RpcCode.version) await _drop();
        throw error;
      }
      return decode(objectOf(message.result, method));
    } finally {
      timer.cancel();
    }
  }

  Future<void> _void(String method, [Map<String, Object?> params = const {}]) {
    return _call<bool>(method, params, (_) => true);
  }

  int _allocateId() {
    final id = _next;
    _next += 2;
    if (_next <= 0 || _next > _maxSafeInteger) _next = 1;
    return id;
  }

  bool _emit(
    String method,
    Map<String, Object?> params, {
    int? id,
    bool position = false,
    bool terminal = false,
    String playbackId = '',
    int seq = 0,
  }) {
    if (!_alive) return false;
    final body = <String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    };
    if (id != null) body['id'] = id;
    return _enqueue(
      '${jsonEncode(body)}\n',
      position: position,
      terminal: terminal,
      playbackId: playbackId,
      seq: seq,
    );
  }

  void _reply(int id, Object? result, RpcException? error) {
    if (!_alive) return;
    final body = <String, Object?>{'jsonrpc': '2.0', 'id': id};
    if (error != null) {
      body['error'] = {
        'code': error.code,
        'message': error.message,
        'data': error.data,
      };
    } else {
      body['result'] = result ?? <String, Object?>{};
    }
    _enqueue('${jsonEncode(body)}\n');
  }

  bool _enqueue(
    String payload, {
    bool position = false,
    bool terminal = false,
    String playbackId = '',
    int seq = 0,
  }) {
    final ok = _outbox.add(
      OutboundFrame(
        payload,
        position: position,
        terminal: terminal,
        playbackId: playbackId,
        seq: seq,
      ),
    );
    if (!ok) {
      unawaited(_drop());
      return false;
    }
    _wakePump();
    return true;
  }

  Future<void> _pump() async {
    while (_alive) {
      final hold = holdWrites;
      if (hold != null && !hold.isCompleted) {
        await hold.future;
        continue;
      }
      final frame = _outbox.pop();
      if (frame == null) {
        final wake = Completer<void>();
        _wake = wake;
        if (_outbox.items.isNotEmpty) continue;
        await wake.future;
        continue;
      }
      try {
        _socket.add(utf8.encode(frame.payload));
        await _socket.flush();
      } catch (_) {
        await _drop();
        return;
      }
    }
  }

  void _wakePump() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void _onData(List<int> data) {
    if (!_alive) return;
    final limit = _helloDone ? rpcMaxFrameBytes : rpcHelloFrameBytes;
    for (final byte in data) {
      if (byte == 10) {
        var text = utf8.decode(_buffer);
        _buffer.clear();
        if (text.endsWith('\r')) text = text.substring(0, text.length - 1);
        if (text.isNotEmpty) _onLine(text);
        if (!_alive) return;
        continue;
      }
      _buffer.add(byte);
      if (_buffer.length > limit) {
        unawaited(_drop());
        return;
      }
    }
  }

  void _onLine(String line) {
    final RpcMessage message;
    try {
      message = RpcMessage.parseLine(line);
    } catch (_) {
      unawaited(_drop());
      return;
    }
    final method = message.method;
    if (method != null && method.startsWith('engine.') && message.id != null) {
      unawaited(_answer(message));
      return;
    }
    if (message.isResponse) {
      final pending = _pending.remove(message.id);
      if (pending != null && !pending.isCompleted) pending.complete(message);
      return;
    }
    if (method == RpcMethod.playerState) {
      try {
        final view = PlayerView.fromJson(objectOf(message.params, method!));
        _playbackId = view.playbackId;
        if (!_states.isClosed) _states.add(view);
      } catch (_) {}
      return;
    }
    if (method != null && method.endsWith('.changed')) {
      if (!_changes.isClosed) _changes.add(method);
      return;
    }
    if (method == RpcMethod.notice) {
      try {
        final text =
            objectOf(message.params, method!)['text']?.toString() ?? '';
        if (text.isNotEmpty && !_notices.isClosed) _notices.add(text);
      } catch (_) {}
    }
  }

  Future<void> _answer(RpcMessage message) async {
    try {
      final result = await _dispatchEngine(
        message.method!,
        objectOf(message.params, message.method!),
      );
      _reply(message.id!, result, null);
    } on RpcException catch (error) {
      _reply(message.id!, null, error);
    } catch (_) {
      _reply(message.id!, null, RpcException(RpcCode.internal, '内部错误'));
    }
  }

  Future<Object?> _dispatchEngine(
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case RpcMethod.engineLoad:
        final request = EngineLoad.fromJson(params);
        _playbackId = request.playbackId;
        await host.load(request);
        return {'accepted': true, 'playback_id': request.playbackId};
      case RpcMethod.enginePause:
        final id = params['playback_id']?.toString() ?? '';
        await host.pause(id);
        return <String, Object?>{};
      case RpcMethod.engineResume:
        final id = params['playback_id']?.toString() ?? '';
        await host.resume(id);
        return <String, Object?>{};
      case RpcMethod.engineStop:
        final id = params['playback_id']?.toString() ?? '';
        await host.stop(id);
        if (_playbackId == id) _playbackId = null;
        return <String, Object?>{};
      case RpcMethod.engineSeek:
        await host.seek(
          params['playback_id']?.toString() ?? '',
          (params['position_ms'] as num?)?.toInt() ?? 0,
        );
        return <String, Object?>{};
      case RpcMethod.engineVolume:
        await host.volume(
          params['playback_id']?.toString() ?? '',
          (params['volume'] as num?)?.toDouble() ?? 0,
        );
        return <String, Object?>{};
      case RpcMethod.engineComp:
        await host.compensation(
          params['playback_id']?.toString() ?? '',
          (params['comp_db'] as num?)?.toDouble() ?? 0,
        );
        return <String, Object?>{};
      case RpcMethod.engineAutoGain:
        await host.autoGain(
          params['playback_id']?.toString() ?? '',
          params['enabled'] == true,
        );
        return <String, Object?>{};
      case RpcMethod.engineState:
        return host.reportState().toJson();
      default:
        throw RpcException(RpcCode.methodNotFound, '未知方法');
    }
  }

  Future<void> _drop() => _closing ??= _dropOnce();

  Future<void> _dropOnce() async {
    if (_dropping) return;
    _dropping = true;
    _alive = false;
    _connected = false;
    _connections.add(false);
    _outbox.items.clear();
    final pending = Map<int, Completer<RpcMessage>>.of(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(RpcException(RpcCode.closed, '连接已断开'));
      }
    }
    final hold = holdWrites;
    if (hold != null && !hold.isCompleted) hold.complete();
    _wakePump();
    final playbackId = _playbackId;
    _playbackId = null;
    try {
      await _subscription.cancel();
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {}
    if (playbackId != null && playbackId.isNotEmpty) {
      try {
        await host.stop(playbackId);
      } catch (_) {}
    }
    if (!_changes.isClosed) await _changes.close();
    if (!_connections.isClosed) await _connections.close();
    if (!_states.isClosed) await _states.close();
    if (!_notices.isClosed) await _notices.close();
  }
}
