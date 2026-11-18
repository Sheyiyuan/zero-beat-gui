import 'package:zero_beat_core/zero_beat_core.dart';

import 'models.dart';

/// UI 使用的核心门面。播放状态只来自 [states] 与 [playerState]。
abstract interface class CoreApi {
  Future<HelloResult> hello({
    required String token,
    required String platform,
    required List<String> engineCapabilities,
  });

  Future<void> cancel(int rpcId);

  Future<PlaylistList> playlists();

  Future<SongPage> songs({
    required String playlistId,
    required int offset,
    required int limit,
  });

  Future<SearchView> search({
    required String keyword,
    required int page,
    String source = '',
  });

  Future<LinkView> openLink(String text);

  Future<Accepted> play({
    String songId = '',
    Song? song,
    List<Song>? queue,
    int queueIndex = -1,
    int startAtMs = 0,
  });

  Future<Accepted> toggle();
  Future<void> pause();
  Future<void> stop();
  Future<void> resume();
  Future<Accepted> next();
  Future<Accepted> previous();
  Future<void> seek(int positionMs);
  Future<void> setVolume(double volume);
  Future<void> setMode(String mode);
  Future<int> enqueue(Song song);
  Future<int> insertNext(Song song);
  Future<void> removeQueueAt(int index);
  Future<void> moveQueue(int index, int delta);
  Future<void> clearQueue();
  Future<PlayerView> playerState();
  Future<void> quit();

  HelloResult? get helloResult;
  Stream<bool> get connections;

  Stream<PlayerView> get states;
  Stream<String> get notices;

  /// 连接已断开。重连后必须重新 hello 并拉取快照，不能重放队列里的命令。
  bool get connected;

  Future<void> close();
}
