import 'dart:async';

import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'package:zero_beat_gui/shared/playback.dart';

import 'samples.dart';

class FakeCoreApi implements CoreApi {
  FakeCoreApi({PlayerView? view}) : view = view ?? playerView();

  PlayerView view;
  List<Playlist> libraryPlaylists = const [];
  List<Song> librarySongs = const [];
  String? searchError;
  HelloResult? _helloResult;
  @override
  HelloResult get helloResult => _helloResult ?? sampleHello();
  set helloResult(HelloResult? value) => _helloResult = value;
  final _connections = StreamController<bool>.broadcast();
  @override
  Stream<bool> get connections => _connections.stream;
  void disconnect() {
    connected = false;
    _connections.add(false);
  }

  int helloCalls = 0;
  @override
  bool connected = true;

  int searchCalls = 0;
  int toggles = 0;
  int pauses = 0;
  int stops = 0;
  int resumes = 0;
  int nexts = 0;
  int previouses = 0;
  int seeks = 0;
  final seekPositions = <int>[];
  final modes = <String>[];
  int quits = 0;
  final played = <String>[];

  final _states = StreamController<PlayerView>.broadcast();
  final _notices = StreamController<String>.broadcast();

  void emit(PlayerView next) {
    view = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> closeControllers() async {
    await _connections.close();
    await _states.close();
    await _notices.close();
  }

  @override
  Stream<PlayerView> get states => _states.stream;

  @override
  Stream<String> get notices => _notices.stream;

  void notify(String text) {
    if (!_notices.isClosed) _notices.add(text);
  }

  @override
  Future<HelloResult> hello({
    required String token,
    required String platform,
    required List<String> engineCapabilities,
  }) async {
    helloCalls++;
    return helloResult;
  }

  @override
  Future<void> cancel(int rpcId) async {}

  @override
  Future<PlaylistList> playlists() async {
    return PlaylistList(playlists: libraryPlaylists, warning: '');
  }

  @override
  Future<SongPage> songs({
    required String playlistId,
    required int offset,
    required int limit,
  }) async {
    return SongPage(
      songs: librarySongs,
      total: librarySongs.length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<SearchView> search({
    required String keyword,
    required int page,
    String source = '',
  }) async {
    searchCalls += 1;
    final error = searchError;
    if (error != null) {
      throw RpcException(RpcCode.unavailable, error);
    }
    return SearchView(
      candidates: const [],
      pages: 0,
      hasWarning: false,
      warning: '',
    );
  }

  @override
  Future<LinkView> openLink(String text) async {
    return LinkView(matched: false, kind: 'unknown', ref: null, song: null);
  }

  @override
  Future<Accepted> play({
    String songId = '',
    Song? song,
    List<Song>? queue,
    int queueIndex = -1,
    int startAtMs = 0,
  }) async {
    played.add(song?.id ?? songId);
    return Accepted(requestId: 1, started: true);
  }

  @override
  Future<Accepted> toggle() async {
    toggles += 1;
    return Accepted(requestId: 1, started: true);
  }

  @override
  Future<void> pause() async {
    pauses += 1;
  }

  @override
  Future<void> stop() async {
    stops += 1;
  }

  @override
  Future<void> resume() async {
    resumes += 1;
  }

  @override
  Future<Accepted> next() async {
    nexts += 1;
    return Accepted(requestId: 1, started: true);
  }

  @override
  Future<Accepted> previous() async {
    previouses += 1;
    return Accepted(requestId: 1, started: true);
  }

  @override
  Future<void> seek(int positionMs) async {
    seeks += 1;
    seekPositions.add(positionMs);
  }

  final volumes = <double>[];

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> setMode(String mode) async {
    modes.add(mode);
    final snapshot = view.snapshot;
    view = PlayerView(
      playbackId: view.playbackId,
      playWhenReady: view.playWhenReady,
      notice: view.notice,
      noticeLevel: view.noticeLevel,
      snapshot: PlaybackSnapshot(
        queue: snapshot.queue,
        index: snapshot.index,
        current: snapshot.current,
        state: snapshot.state,
        positionMs: snapshot.positionMs,
        durationMs: snapshot.durationMs,
        mode: PlaybackMode(mode),
        volume: snapshot.volume,
        compDb: snapshot.compDb,
        songCompDb: snapshot.songCompDb,
        autoGain: snapshot.autoGain,
        muted: snapshot.muted,
        awaiting: snapshot.awaiting,
        requestId: snapshot.requestId,
        sleepUntil: snapshot.sleepUntil,
        quality: snapshot.quality,
      ),
    );
  }

  @override
  Future<int> enqueue(Song song) async => 1;

  @override
  Future<int> insertNext(Song song) async => 1;

  @override
  Future<void> removeQueueAt(int index) async {}

  @override
  Future<void> moveQueue(int index, int delta) async {
    moves.add((index, delta));
  }

  final moves = <(int, int)>[];

  @override
  Future<void> clearQueue() async {}

  @override
  Future<PlayerView> playerState() async => view;

  @override
  Future<void> quit() async {
    quits += 1;
  }

  @override
  Future<void> close() async {}
}
