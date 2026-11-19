import 'dart:async';

import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'fake_core.dart';
import 'samples.dart';

/// A fake core that also exposes the feature transport used by the mine,
/// account, download, and sync screens.
class FeatureApi extends FakeCoreApi implements CoreFeatureTransport {
  FeatureApi({
    List<SourceInfo>? sources,
    SyncStatus? sync,
    List<DownloadTask>? downloadTaskList,
    List<DownloadEntry>? downloadEntryList,
    List<Work>? workList,
    List<Archive>? archiveList,
  }) : sources = sources ?? [],
       sync = sync ?? sampleSyncStatus(),
       downloadTaskList = downloadTaskList ?? [],
       downloadEntryList = downloadEntryList ?? [],
       workList = workList ?? [],
       archiveList = archiveList ?? [];

  final _changes = StreamController<String>.broadcast();
  List<SourceInfo> sources;
  SyncStatus sync;
  List<DownloadTask> downloadTaskList;
  List<DownloadEntry> downloadEntryList;
  List<Work> workList;
  List<Archive> archiveList;

  final Set<String> failures = {};
  final Set<String> failNext = {};

  int accountsCalls = 0;
  int accountsRefreshCalls = 0;
  int syncStatusCalls = 0;
  int downloadTasksCalls = 0;
  int downloadsCalls = 0;
  int tasksCalls = 0;
  int archivesCalls = 0;
  final List<String> featureMethods = [];

  void emitChange(String kind) {
    if (!_changes.isClosed) _changes.add(kind);
  }

  bool _maybeFail(String method) {
    if (failNext.remove(method) || failures.contains(method)) {
      throw Exception('测试失败');
    }
    return false;
  }

  @override
  Stream<String> get changes => _changes.stream;

  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) async {
    featureMethods.add(method);
    switch (method) {
      case 'auth.accounts':
        accountsCalls++;
        if (params['refresh'] == true) accountsRefreshCalls++;
        _maybeFail(method);
        return {'sources': sources.map((source) => source.toJson()).toList()};
      case 'sync.status':
        syncStatusCalls++;
        _maybeFail(method);
        return sync.toJson();
      case 'download.tasks':
        downloadTasksCalls++;
        _maybeFail(method);
        return {
          'tasks': downloadTaskList.map((task) => task.toJson()).toList(),
        };
      case 'download.list':
        downloadsCalls++;
        _maybeFail(method);
        return {
          'entries': downloadEntryList.map((entry) => entry.toJson()).toList(),
        };
      case 'tasks.list':
        tasksCalls++;
        _maybeFail(method);
        return {'tasks': workList.map((work) => work.toJson()).toList()};
      case 'sync.archives':
        archivesCalls++;
        _maybeFail(method);
        return {
          'archives': archiveList.map((archive) => archive.toJson()).toList(),
        };
    }
    throw UnsupportedError(method);
  }

  @override
  Future<void> closeControllers() async {
    await _changes.close();
    await super.closeControllers();
  }
}

SyncStatus sampleSyncStatus({
  bool configured = true,
  bool auto = false,
  bool hasError = false,
  bool hasKeyIssue = false,
  int conflicts = 0,
  DateTime? lastSyncAt,
}) {
  return SyncStatus(
    requestedBackend: SyncBackend.valueAuto,
    actualBackend: SyncBackend.valueGogit,
    configured: configured,
    remote: configured ? 'https://example.com/library.git' : '',
    branch: 'main',
    auto: auto,
    syncAccounts: false,
    keyCached: true,
    keyMatchesRepo: true,
    keyVersion: 1,
    lastSyncAt: lastSyncAt,
    hasError: hasError,
    hasKeyIssue: hasKeyIssue,
    conflictTx: '',
    conflicts: conflicts,
    warningCount: 0,
  );
}

SourceInfo sampleSource({
  required String id,
  String name = '',
  String mark = '',
  bool loggedIn = false,
  String userName = '',
  List<String> capabilities = const ['account'],
}) {
  return SourceInfo(
    id: SourceID(id),
    name: name,
    mark: mark,
    capabilities: SourceCapabilities(
      names: capabilities,
      unknownBits: BigInt.zero,
    ),
    user: User(
      id: loggedIn ? 'user-$id' : '',
      name: userName,
      avatar: '',
      loggedIn: loggedIn,
    ),
  );
}

DownloadTask sampleDownloadTask({
  int id = 1,
  String state = 'failed',
  Song? song,
}) {
  return DownloadTask(
    id: id,
    song: song ?? sampleSong(id: 'song-$id'),
    state: state,
    done: BigInt.from(10),
    total: BigInt.from(100),
    path: '/tmp/song-$id.flac',
    failed: state == 'failed',
  );
}

DownloadEntry sampleDownloadEntry({String songId = 'song-1', Song? song}) {
  final resolved = song ?? sampleSong(id: songId);
  return DownloadEntry(
    download: Download(
      songId: songId,
      path: '/tmp/$songId.flac',
      size: BigInt.from(100),
      codec: 'flac',
      durationMs: 180000,
    ),
    song: resolved,
  );
}
