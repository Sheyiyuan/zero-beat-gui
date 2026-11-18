import 'package:zero_beat_core/zero_beat_core.dart';
import 'api.dart';

/// Typed feature facade. Raw transport is confined to this package.
abstract interface class CoreFeatureTransport {
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  );
  Stream<String> get changes;
}

extension CoreFeatures on CoreApi {
  CoreFeatureTransport get _features {
    if (this case final CoreFeatureTransport transport) return transport;
    throw UnsupportedError('当前核心未提供此功能');
  }

  Stream<String> get changes =>
      this is CoreFeatureTransport ? _features.changes : const Stream.empty();
  Future<Map<String, Object?>> _request(
    String method, [
    Map<String, Object?> params = const {},
  ]) => _features.featureCall(method, params);
  Future<List<SourceInfo>> accounts({bool refresh = false}) async => _list(
    await _request('auth.accounts', {'refresh': refresh}),
    'sources',
    SourceInfo.fromJson,
  );
  Future<LoginQR> loginQR(String source) async =>
      LoginQR.fromJson(await _request('auth.qr.start', {'source': source}));
  Future<LoginPoll> pollLogin(String source, String key) async =>
      LoginPoll.fromJson(
        await _request('auth.qr.poll', {'source': source, 'key': key}),
      );
  Future<void> cancelLogin(String source, String key) async {
    await _request('auth.qr.cancel', {'source': source, 'key': key});
  }

  Future<void> logout(String source) async {
    await _request('auth.logout', {'source': source});
  }

  /// Hands the official page's session cookies to the core. The result is only
  /// the public account name; callers must drop the cookie map after the call.
  Future<({bool loggedIn, String name})> commitWebLogin(
    String source,
    Map<String, String> cookies,
  ) async {
    final raw = await _request('auth.web.commit', {
      'source': source,
      'cookies': Map<String, String>.from(cookies),
    });
    return (
      loggedIn: raw['logged_in'] == true,
      name: raw['name']?.toString() ?? '',
    );
  }

  Future<CommentPage> comments(TrackRef ref, int page) async =>
      CommentPage.fromJson(
        await _request('content.comments', {'ref': ref.toJson(), 'page': page}),
      );
  Future<RelatedPage> related(TrackRef ref) async => RelatedPage.fromJson(
    await _request('content.related', {'ref': ref.toJson()}),
  );
  Future<ProfileList> profiles(
    TrackRef ref, {
    bool authorsOnly = false,
  }) async => ProfileList.fromJson(
    await _request('browse.profiles', {
      'ref': ref.toJson(),
      'authors_only': authorsOnly,
    }),
  );
  Future<ProfileList> browseRoots() async =>
      ProfileList.fromJson(await _request('browse.roots'));
  Future<BrowsePage> browse(BrowseRef ref, int page) async =>
      BrowsePage.fromJson(
        await _request('browse.page', {
          'browse_ref': ref.toJson(),
          'page': page,
        }),
      );
  Future<BrowseRef> parseBrowse(String text) async => BrowseRef.fromJson(
    Map<String, Object?>.from(
      (await _request('browse.parse', {'text': text}))['ref'] as Map,
    ),
  );
  Future<Playlist> createPlaylist(
    String title, {
    String kind = 'local',
    bool localOnly = false,
    List<String> refs = const [],
  }) async => Playlist.fromJson(
    await _request('library.create', {
      'title': title,
      'kind': kind,
      'local_only': localOnly,
      'refs': refs,
    }),
  );
  Future<void> editPlaylist(
    String action,
    String id, {
    String title = '',
    List<String> refs = const [],
  }) async {
    await _request('library.$action', {'id': id, 'title': title, 'refs': refs});
  }

  Future<List<Playlist>> mixinRefs(String id) async => _list(
    await _request('library.refs', {'id': id}),
    'playlists',
    Playlist.fromJson,
  );
  Future<List<RemotePlaylist>> remotePlaylists(
    String source, {
    bool write = false,
  }) async => _list(
    await _request('library.remote', {'source': source, 'write': write}),
    'playlists',
    RemotePlaylist.fromJson,
  );
  Future<Playlist> importPlaylist(RemotePlaylist playlist) async =>
      Playlist.fromJson(
        await _request('library.import_remote', {'remote': playlist.toJson()}),
      );
  Future<LibraryScan> folder(
    String action, {
    String id = '',
    String path = '',
  }) async {
    final task = Work.fromJson(
      await _request('library.folder.start', {
        'action': action,
        'id': id,
        'path': path,
      }),
    );
    await waitTask(task.id);
    return LibraryScan.fromJson(
      await _request('tasks.folder_result', {'id': task.id}),
    );
  }

  Future<List<Song>> localSearch(
    String query, {
    String playlistId = '',
  }) async => _list(
    await _request('search.local', {'query': query, 'playlist_id': playlistId}),
    'songs',
    Song.fromJson,
  );
  Future<BatchResult> batch(
    String action, {
    String target = '',
    String playlistId = '',
    List<Song> songs = const [],
  }) async {
    final params = <String, Object?>{
      'action': action,
      'target': target,
      'playlist_id': playlistId,
      'songs': [for (final s in songs) s.toJson()],
    };
    if (action == 'add' || action == 'remove') {
      final work = Work.fromJson(await _request('library.batch.start', params));
      return waitBatch(work.id);
    }
    return BatchResult.fromJson(await _request('library.batch', params));
  }

  Future<(Work, BatchResult)> batchTask(String id) async {
    final data = await _request('tasks.batch_result', {'id': id});
    return (
      Work.fromJson(Map<String, Object?>.from(data['task'] as Map)),
      BatchResult.fromJson(Map<String, Object?>.from(data['result'] as Map)),
    );
  }

  Future<BatchResult> waitBatch(String id) async {
    while (true) {
      final (work, result) = await batchTask(id);
      if (work.state != 'running') {
        if (work.state == 'failed' &&
            result.succeeded.isEmpty &&
            result.failed.isEmpty) {
          throw StateError(work.message);
        }
        return result;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<Work> retryBatch(String id) async =>
      Work.fromJson(await _request('tasks.retry_batch', {'id': id}));
  Future<Map<String, String>> conflictChoices(String txId) async =>
      Map<String, String>.from(
        (await _request('sync.choices', {'tx_id': txId}))['choices'] as Map,
      );
  Future<void> waitTask(String id) async {
    while (true) {
      final list = await tasks();
      final work = list.where((w) => w.id == id).firstOrNull;
      if (work == null) throw StateError('任务不存在，请刷新任务列表');
      if (work.state != 'running') {
        if (work.state != 'completed')
          throw StateError(work.message.isEmpty ? '操作已取消' : work.message);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<LyricsResult> lyrics(Song song) async => LyricsResult.fromJson(
    await _request('lyrics.get', {'song': song.toJson()}),
  );
  Future<List<LyricCandidate>> lyricCandidates(
    Song song,
    String query, {
    String filter = '',
  }) async => _list(
    await _request('lyrics.candidates', {
      'song': song.toJson(),
      'query': query,
      'filter': filter,
    }),
    'candidates',
    LyricCandidate.fromJson,
  );
  Future<LyricPreview> previewLyrics(
    Song song,
    LyricCandidate candidate,
  ) async => LyricPreview.fromJson(
    await _request('lyrics.preview', {
      'song': song.toJson(),
      'candidate': candidate.toJson(),
    }),
  );
  Future<void> bindLyrics(Song song, LyricCandidate candidate) async {
    await _request('lyrics.bind', {
      'song': song.toJson(),
      'candidate': candidate.toJson(),
    });
  }

  Future<void> unbindLyrics(String id) async {
    await _request('lyrics.unbind', {'id': id});
  }

  Future<void> lyricOffset(String id, BindingScope scope, int ms) async {
    await _request('lyrics.offset', {
      'id': id,
      'scope': scope.value,
      'offset_ms': ms,
    });
  }

  Future<String> resourceBegin(
    String uri,
    String title, {
    String id = '',
    int subdirs = 0,
  }) async =>
      (await _request('library.resource.begin', {
            'uri': uri,
            'title': title,
            'id': id,
            'subdirs': subdirs,
          }))['token']
          as String;
  Future<void> resourceInspect(
    String token, {
    required int fd,
    required String uri,
    required String name,
    String lrc = '',
    int duration = 0,
  }) async {
    await _request('library.resource.inspect', {
      'key': token,
      'fd': fd,
      'uri': uri,
      'name': name,
      'lrc': lrc,
      'duration': duration,
    });
  }

  Future<void> resourceLyrics(String token, String name, int fd) async {
    await _request('library.resource.lyrics', {
      'key': token,
      'name': name,
      'fd': fd,
    });
  }

  Future<void> resourceCancel(String token) async {
    await _request('library.resource.cancel', {'key': token});
  }

  Future<void> resourceSkip(String token, String name) async {
    await _request('library.resource.skip', {'key': token, 'name': name});
  }

  Future<LibraryScan> resourceCommit(String token) async =>
      LibraryScan.fromJson(
        await _request('library.resource.commit', {'key': token}),
      );
  Future<void> resourceUnavailable(String id) async {
    await _request('library.resource.unavailable', {'id': id});
  }

  Future<List<DownloadEntry>> downloads() async =>
      _list(await _request('download.list'), 'entries', DownloadEntry.fromJson);
  Future<List<DownloadTask>> downloadTasks() async =>
      _list(await _request('download.tasks'), 'tasks', DownloadTask.fromJson);
  Future<BatchResult> downloadSelection({
    List<Song> songs = const [],
    String playlistId = '',
    bool force = false,
  }) async {
    final work = Work.fromJson(
      await _request('download.batch.start', {
        'songs': songs.map((s) => s.toJson()).toList(),
        'playlist_id': playlistId,
        'force': force,
      }),
    );
    return waitBatch(work.id);
  }

  Future<void> downloadAction(
    String action, {
    int taskId = 0,
    String songId = '',
  }) async {
    await _request('download.action', {
      'action': action,
      'task_id': taskId,
      'id': songId,
    });
  }

  Future<List<Work>> tasks() async =>
      _list(await _request('tasks.list'), 'tasks', Work.fromJson);
  Future<void> cancelTask(String id) async {
    await _request('tasks.cancel', {'id': id});
  }

  Future<List<Archive>> syncArchives() async =>
      _list(await _request('sync.archives'), 'archives', Archive.fromJson);
  Future<String> syncArchive(String name) async =>
      (await _request('sync.archive', {'name': name}))['text'] as String;
  Future<SyncStatus> syncStatus() async =>
      SyncStatus.fromJson(await _request('sync.status'));
  Future<Work> syncAction(
    String action, {
    String remote = '',
    String branch = 'main',
    String passphrase = '',
    String token = '',
    String txId = '',
    String entity = '',
    String choice = '',
    bool auto = false,
    bool accounts = false,
  }) async => Work.fromJson(
    await _request('sync.action', {
      'action': action,
      'sync': {
        'Remote': remote,
        'Branch': branch,
        'Passphrase': passphrase,
        'Token': token,
        'TxID': txId,
        'Entity': entity,
        'Choice': choice,
        'Auto': auto,
        'Accounts': accounts,
      },
    }),
  );
  Future<SyncConflictList> syncConflicts() async =>
      SyncConflictList.fromJson(await _request('sync.conflicts'));
  Future<String> conflictVersion(String txId, int index, String side) async =>
      (await _request('sync.version', {
            'tx_id': txId,
            'index': index,
            'side': side,
          }))['text']
          as String;

  Future<Preferences> preferences() async =>
      Preferences.fromJson(await _request('settings.get'));
  Future<void> playbackSetting(String key, num value) async {
    await _request('settings.set', {'key': key, 'value': value});
  }

  Future<GUISettings> guiSettings() async =>
      GUISettings.fromJson(await _request('settings.gui.get'));
  Future<void> saveGUISettings(GUISettings settings) async {
    await _request('settings.gui.set', {'settings': settings.toJson()});
  }

  Future<Clip> clip(String id) async =>
      Clip.fromJson(await _request('player.clip.get', {'id': id}));
  Future<(String, Clip)> beginClip(String id) async {
    final data = await _request('player.clip.begin', {'id': id});
    return (
      data['token'] as String,
      Clip.fromJson(Map<String, Object?>.from(data['clip'] as Map)),
    );
  }

  Future<void> editClip(
    String id,
    String action, {
    Clip? clip,
    int positionMs = 0,
    String token = '',
  }) async {
    await _request('player.clip.edit', {
      'id': id,
      'key': token,
      'action': action,
      'clip': (clip ?? Clip(startMs: 0, endMs: 0)).toJson(),
      'position_ms': positionMs,
    });
  }
}

List<T> _list<T>(
  Map<String, Object?> json,
  String field,
  T Function(Map<String, Object?>) decode,
) => [
  for (final v in json[field] as List? ?? const [])
    decode(Map<String, Object?>.from(v as Map)),
];
