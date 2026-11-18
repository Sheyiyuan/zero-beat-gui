/// Stable method names and error codes. Keep aligned with rpc/codes.go.
abstract final class RpcMethod {
  static const hello = 'core.hello';
  static const cancel = 'core.cancel';
  static const playlists = 'library.playlists';
  static const songs = 'library.songs';
  static const search = 'search.query';
  static const openLink = 'source.open_link';
  static const play = 'player.play';
  static const toggle = 'player.toggle';
  static const pause = 'player.pause';
  static const stop = 'player.stop';
  static const resume = 'player.resume';
  static const next = 'player.next';
  static const previous = 'player.prev';
  static const seek = 'player.seek';
  static const volume = 'player.volume';
  static const mode = 'player.mode';
  static const enqueue = 'player.enqueue';
  static const insertNext = 'player.insert_next';
  static const queueRemove = 'player.queue_remove';
  static const queueMove = 'player.queue_move';
  static const queueClear = 'player.queue_clear';
  static const playerState = 'player.state';
  static const quit = 'app.quit';
  static const engineLoad = 'engine.load';
  static const enginePause = 'engine.pause';
  static const engineResume = 'engine.resume';
  static const engineStop = 'engine.stop';
  static const engineSeek = 'engine.seek';
  static const engineVolume = 'engine.volume';
  static const engineComp = 'engine.comp';
  static const engineAutoGain = 'engine.auto_gain';
  static const engineState = 'engine.state';
  static const enginePosition = 'engine.position';
  static const engineEnded = 'engine.ended';
  static const engineFailed = 'engine.failed';
  static const notice = 'notice';
}

abstract final class RpcCode {
  static const parse = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internal = -32603;
  static const unauthorized = -32001;
  static const version = -32002;
  static const cancelled = -32004;
  static const unavailable = -32010;
  static const stalePlayback = -32011;
  static const closed = -32012;
}

const int rpcApiVersion = 1;
const int rpcRepoVersion = 3;
const String rpcClientVersion = '0.1.0-dev';
const int rpcMaxFrameBytes = 8 * 1024 * 1024;
const int rpcHelloFrameBytes = 16 * 1024;

const Set<String> slowMethods = {
  RpcMethod.search,
  RpcMethod.openLink,
  RpcMethod.songs,
  RpcMethod.playlists,
};

Duration timeoutFor(String method) =>
    (slowMethods.contains(method) ||
        const [
          'auth.',
          'content.',
          'browse.',
          'lyrics.',
          'library.',
          'search.',
          'download.',
          'sync.',
          'tasks.',
        ].any(method.startsWith))
    ? const Duration(seconds: 20)
    : const Duration(seconds: 3);
