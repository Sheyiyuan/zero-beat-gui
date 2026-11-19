import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/providers.dart';
import '../shared/playback.dart';

class LibraryState {
  const LibraryState({
    this.playlists = const <Playlist>[],
    this.songs = const <Song>[],
    this.selectedPlaylistId,
    this.selectedSongId,
    this.warning = '',
    this.error = '',
    this.loading = false,
    this.refreshing = false,
    this.loaded = false,
    this.total = 0,
    this.loadingMore = false,
    this.moreError = '',
  });

  final List<Playlist> playlists;
  final List<Song> songs;
  final String? selectedPlaylistId;
  final String? selectedSongId;
  final String warning;
  final String error;
  final bool loading;
  final bool refreshing;
  final bool loaded;
  final int total;
  final bool loadingMore;
  final String moreError;
  bool get hasMore => songs.length < total;

  bool get isEmpty => loaded && error.isEmpty && songs.isEmpty;

  Song? get selectedSong {
    for (final song in songs) {
      if (song.id == selectedSongId) return song;
    }
    return null;
  }

  LibraryState copy({
    List<Playlist>? playlists,
    List<Song>? songs,
    String? selectedPlaylistId,
    bool keepPlaylist = true,
    String? selectedSongId,
    bool keepSong = true,
    String? warning,
    String? error,
    bool? loading,
    bool? refreshing,
    bool? loaded,
    int? total,
    bool? loadingMore,
    String? moreError,
  }) {
    return LibraryState(
      playlists: playlists ?? this.playlists,
      songs: songs ?? this.songs,
      selectedPlaylistId: keepPlaylist
          ? (selectedPlaylistId ?? this.selectedPlaylistId)
          : selectedPlaylistId,
      selectedSongId: keepSong
          ? (selectedSongId ?? this.selectedSongId)
          : selectedSongId,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      loaded: loaded ?? this.loaded,
      total: total ?? this.total,
      loadingMore: loadingMore ?? this.loadingMore,
      moreError: moreError ?? this.moreError,
    );
  }
}

class LibraryController extends Notifier<LibraryState> {
  int _generation = 0;
  bool _alive = true;
  Future<void>? _refreshInFlight;

  @override
  LibraryState build() {
    final api = ref.watch(coreApiProvider);
    _alive = true;
    final generation = ++_generation;
    ref.onDispose(() {
      _alive = false;
      _generation++;
    });
    Future<void>(() {
      if (_valid(generation)) _reload(api);
    });
    final changes = api.changes.listen((event) {
      if (event == "library.changed" || event == "all.changed") refresh();
    });
    ref.onDispose(changes.cancel);
    return const LibraryState(loading: true);
  }

  bool _valid(int generation) => _alive && generation == _generation;

  Future<void> reload() => _reload(ref.read(coreApiProvider));

  /// Refreshes playlists and the selected playlist without dropping the rows
  /// that are already on screen. Concurrent calls share one request so a pull
  /// gesture and a lifecycle resume cannot race each other.
  Future<void> refresh() async {
    final running = _refreshInFlight;
    if (running != null) {
      await running;
      return;
    }
    final future = reload();
    _refreshInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    }
  }

  Future<void> retry() {
    final id = state.selectedPlaylistId;
    return id == null ? _reload(ref.read(coreApiProvider)) : selectPlaylist(id);
  }

  Future<void> selectPlaylist(String id) async {
    final generation = ++_generation;
    state = state.copy(
      selectedPlaylistId: id,
      keepSong: false,
      songs: [],
      total: 0,
      loading: true,
      refreshing: false,
      loaded: false,
      error: '',
      moreError: '',
      loadingMore: false,
    );
    await _loadSongs(ref.read(coreApiProvider), id, generation);
  }

  void selectSong(String id) => state = state.copy(selectedSongId: id);

  Future<void> _reload(CoreApi api) async {
    final generation = ++_generation;
    final keepContent = state.loaded;
    state = state.copy(loading: true, refreshing: keepContent, error: '');
    try {
      final lists = await api.playlists();
      if (!_valid(generation)) return;
      final playlists = lists.playlists;
      if (playlists.isEmpty) {
        state = LibraryState(warning: lists.warning, loaded: true);
        return;
      }
      final selected = playlists.any((p) => p.id == state.selectedPlaylistId)
          ? state.selectedPlaylistId!
          : playlists.first.id;
      final same = selected == state.selectedPlaylistId;
      state = state.copy(
        playlists: playlists,
        selectedPlaylistId: selected,
        keepPlaylist: false,
        keepSong: same,
        selectedSongId: null,
        songs: same ? state.songs : const <Song>[],
        total: same ? state.total : 0,
        warning: lists.warning,
        loading: true,
        refreshing: same && keepContent,
        loaded: same && state.loaded,
        moreError: '',
        loadingMore: false,
      );
      await _loadSongs(api, selected, generation);
    } catch (error) {
      if (_valid(generation)) {
        final message = errorText(error);
        if (state.refreshing && state.songs.isNotEmpty) {
          state = state.copy(
            loading: false,
            refreshing: false,
            loaded: true,
            warning: '刷新失败：$message',
          );
          return;
        }
        state = state.copy(
          loading: false,
          refreshing: false,
          loaded: true,
          error: message,
          songs: [],
        );
      }
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore ||
        !state.hasMore ||
        state.selectedPlaylistId == null) {
      return;
    }
    state = state.copy(loadingMore: true, moreError: '');
    await _loadSongs(
      ref.read(coreApiProvider),
      state.selectedPlaylistId!,
      _generation,
      append: true,
    );
  }

  Future<void> _loadSongs(
    CoreApi api,
    String id,
    int generation, {
    bool append = false,
  }) async {
    final offset = append ? state.songs.length : 0;
    try {
      final page = await api.songs(playlistId: id, offset: offset, limit: 200);
      if (!_valid(generation)) return;
      if (append && page.songs.isEmpty && offset < page.total) {
        throw StateError('曲库内容已变化，请重试');
      }
      state = state.copy(
        songs: [if (append) ...state.songs, ...page.songs],
        total: page.total,
        loading: false,
        refreshing: false,
        loadingMore: false,
        loaded: true,
        error: '',
        moreError: '',
      );
    } catch (error) {
      if (!_valid(generation)) return;
      final message = errorText(error);
      if (append) {
        state = state.copy(loadingMore: false, moreError: message);
        return;
      }
      if (state.refreshing && state.songs.isNotEmpty) {
        state = state.copy(
          loading: false,
          refreshing: false,
          loaded: true,
          warning: '刷新失败：$message',
        );
        return;
      }
      state = state.copy(
        loading: false,
        refreshing: false,
        loaded: true,
        error: message,
        songs: [],
      );
    }
  }
}

class SearchState {
  const SearchState({
    this.keyword = '',
    this.source = '',
    this.results = const <Candidate>[],
    this.warning = '',
    this.error = '',
    this.linkMessage = '',
    this.loading = false,
    this.submitted = false,
    this.selectedIndex = 0,
    this.page = 1,
    this.pages = 0,
  });

  final String keyword;
  final String source;
  final List<Candidate> results;
  final String warning;
  final String error;
  final String linkMessage;
  final bool loading;
  final bool submitted;
  final int selectedIndex;
  final int page;
  final int pages;

  bool get showingResults => submitted && error.isEmpty;

  Song? get selectedSong {
    if (results.isEmpty) return null;
    final index = selectedIndex.clamp(0, results.length - 1);
    return songFromTrack(results[index].track);
  }

  SearchState copy({
    String? keyword,
    String? source,
    List<Candidate>? results,
    String? warning,
    String? error,
    String? linkMessage,
    bool? loading,
    bool? submitted,
    int? selectedIndex,
    int? page,
    int? pages,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      source: source ?? this.source,
      results: results ?? this.results,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      linkMessage: linkMessage ?? this.linkMessage,
      loading: loading ?? this.loading,
      submitted: submitted ?? this.submitted,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      page: page ?? this.page,
      pages: pages ?? this.pages,
    );
  }
}

class SearchController extends Notifier<SearchState> {
  int _generation = 0;

  @override
  SearchState build() {
    ref.watch(coreApiProvider);
    ref.onDispose(() => _generation++);
    return const SearchState();
  }

  void setKeyword(String value) {
    if (value == state.keyword) return;
    _generation++;
    state = state.copy(
      keyword: value,
      page: 1,
      pages: 0,
      results: [],
      submitted: false,
      loading: false,
      error: '',
    );
  }

  void setSource(String value) {
    if (value == state.source) return;
    _generation++;
    state = state.copy(
      source: value,
      page: 1,
      pages: 0,
      results: [],
      loading: false,
      error: '',
    );
    if (state.submitted) _run(state.keyword);
  }

  void select(int index) => state = state.copy(selectedIndex: index);

  void clearResults() {
    _generation++;
    state = state.copy(
      submitted: false,
      loading: false,
      error: '',
      warning: '',
    );
  }

  Future<void> submit() => _run(state.keyword);

  Future<void> retry() => _run(state.keyword, page: state.page);

  Future<void> goToPage(int page) async {
    if (state.loading || page < 1 || page > state.pages) return;
    await _run(state.keyword, page: page);
  }

  Future<void> openLink(String text, {LinkView? resolved}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      state = state.copy(linkMessage: '请先粘贴链接');
      return;
    }
    final api = ref.read(coreApiProvider);
    try {
      final link = resolved ?? await api.openLink(trimmed);
      final song = link.song;
      if (link.matched && link.kind == 'track' && song != null) {
        ref.read(interruptionPolicyProvider).noteUserTransport();
        await api.play(song: song);
        state = state.copy(linkMessage: '');
        return;
      }
      final message = !link.matched
          ? '未找到可播放的歌曲'
          : link.kind == 'browse'
          ? '这是歌单或主页链接，请打开后选择歌曲。'
          : '此链接无法直接播放，请检查链接或搜索歌曲。';
      state = state.copy(linkMessage: message);
    } catch (error) {
      state = state.copy(linkMessage: errorText(error));
    }
  }

  Future<void> _run(String keyword, {int page = 1}) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      state = state.copy(
        error: '请输入歌曲名、歌手或关键词',
        submitted: true,
        loading: false,
      );
      return;
    }
    final generation = ++_generation;
    final source = state.source;
    state = state.copy(
      loading: true,
      submitted: true,
      error: '',
      keyword: trimmed,
      page: page,
    );
    try {
      final view = await ref
          .read(coreApiProvider)
          .search(keyword: trimmed, page: page, source: source);
      if (generation != _generation) return;
      state = state.copy(
        results: view.candidates,
        pages: view.pages,
        warning: view.hasWarning ? view.warning : '',
        error: '',
        loading: false,
        submitted: true,
        selectedIndex: 0,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = state.copy(
        error: errorText(error),
        loading: false,
        submitted: true,
      );
    }
  }
}

class HelloState {
  const HelloState({this.result, this.error = ''});

  final HelloResult? result;
  final String error;
}

class HelloController extends Notifier<HelloState> {
  @override
  HelloState build() {
    return HelloState(result: ref.watch(coreApiProvider).helloResult);
  }
}

class PlayerController extends Notifier<PlayerView> {
  @override
  PlayerView build() {
    final api = ref.watch(coreApiProvider);
    var active = true;
    var fromStream = false;
    ref.onDispose(() => active = false);
    final subscription = api.states.listen((view) {
      fromStream = true;
      state = view;
    });
    ref.onDispose(subscription.cancel);
    Future<void>(() async {
      try {
        final view = await api.playerState();
        if (!active || fromStream) return;
        state = view;
      } catch (_) {}
    });
    // The handshake already carries the persisted player snapshot. Starting
    // from it avoids a visible 80% volume flash on every launch.
    return api.helloResult?.player ?? playerView();
  }

  void show(PlayerView view) => state = view;
}

class NoticeController extends Notifier<String> {
  @override
  String build() {
    final subscription = ref
        .watch(coreApiProvider)
        .notices
        .listen((text) => state = text);
    ref.onDispose(subscription.cancel);
    return '';
  }

  void clear() => state = '';
}

class ConnectionController extends Notifier<bool> {
  @override
  bool build() {
    final api = ref.watch(coreApiProvider);
    final subscription = api.connections.listen(
      (connected) => state = connected,
      onDone: () => state = false,
    );
    ref.onDispose(subscription.cancel);
    return api.connected;
  }
}

class Transport {
  Transport(this.ref);

  final Ref ref;

  CoreApi get _api => ref.read(coreApiProvider);

  void _touch() => ref.read(interruptionPolicyProvider).noteUserTransport();

  Future<void> toggle() {
    _touch();
    return _api.toggle();
  }

  Future<void> pause() {
    _touch();
    return _api.pause();
  }

  Future<void> resume() {
    _touch();
    return _api.resume();
  }

  Future<void> next() {
    _touch();
    return _api.next();
  }

  Future<void> previous() {
    _touch();
    return _api.previous();
  }

  Future<void> seek(int positionMs) {
    _touch();
    return _api.seek(positionMs);
  }

  Future<void> setVolume(double volume) async {
    final next = volume.clamp(0.0, 1.0);
    final current = ref.read(playerProvider);
    ref.read(playerProvider.notifier).show(playerViewWithVolume(current, next));
    await _api.setVolume(next);
  }

  Future<void> bumpVolume(double delta) {
    final current = ref.read(playerProvider).snapshot.volume;
    return setVolume(current + delta);
  }

  Future<void> setPlaybackMode(String mode) {
    _touch();
    return _api.setMode(mode);
  }

  Future<void> playPlaylistSong(
    Song song,
    String playlistId,
    List<Song> loaded,
  ) async {
    _touch();
    if (_api is CoreFeatureTransport) {
      await _api.batch('play', target: song.id, playlistId: playlistId);
    } else {
      await _api.play(song: song, queue: loaded);
    }
  }

  /// Plays the whole playlist from the start. Passing the playlist id as the
  /// batch target asks the core to shuffle the first song too when shuffle
  /// mode is on, matching the TUI's play-playlist action.
  Future<void> playPlaylistFromStart(
    String playlistId,
    List<Song> loaded,
  ) async {
    _touch();
    if (_api is CoreFeatureTransport) {
      await _api.batch('play', target: playlistId, playlistId: playlistId);
      return;
    }
    var queue = loaded;
    if (queue.isEmpty) {
      final page = await _api.songs(
        playlistId: playlistId,
        offset: 0,
        limit: 200,
      );
      queue = page.songs;
    }
    if (queue.isEmpty) {
      throw StateError('歌单里还没有曲目');
    }
    await _api.play(song: queue.first, queue: queue);
  }

  Future<void> playSong(Song song, {List<Song>? context}) {
    _touch();
    return _api.play(song: song, queue: context);
  }

  Future<void> playIndex(int index) {
    _touch();
    return _api.play(queueIndex: index);
  }

  Future<void> enqueue(Song song) => _api.enqueue(song);

  Future<void> insertNext(Song song) => _api.insertNext(song);
}

final libraryProvider = NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);
final searchProvider = NotifierProvider<SearchController, SearchState>(
  SearchController.new,
);
final helloProvider = NotifierProvider<HelloController, HelloState>(
  HelloController.new,
);
final playerProvider = NotifierProvider<PlayerController, PlayerView>(
  PlayerController.new,
);
final noticeProvider = NotifierProvider<NoticeController, String>(
  NoticeController.new,
);
final connectionProvider = NotifierProvider<ConnectionController, bool>(
  ConnectionController.new,
);
final transportProvider = Provider<Transport>((ref) => Transport(ref));
