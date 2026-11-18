import 'package:zero_beat_core/zero_beat_core.dart';

import 'envelope.dart';

class AccountBrief {
  AccountBrief({required this.loggedIn, required this.name, this.notice = ''});

  final bool loggedIn;
  final String name;
  final String notice;

  static AccountBrief fromJson(Map<String, Object?> json) => AccountBrief(
    loggedIn: json['logged_in'] == true,
    name: json['name']?.toString() ?? '',
    notice: json['notice']?.toString() ?? '',
  );
}

class PlayerView {
  PlayerView({
    required this.playbackId,
    required this.playWhenReady,
    required this.notice,
    required this.noticeLevel,
    required this.snapshot,
  });

  final String? playbackId;
  final bool playWhenReady;
  final String notice;
  final String noticeLevel;
  final PlaybackSnapshot snapshot;

  bool get hasTrack => snapshot.current != null || snapshot.queue.isNotEmpty;

  static PlayerView fromJson(Map<String, Object?> json) {
    final id = json['playback_id'];
    return PlayerView(
      playbackId: id == null ? null : id.toString(),
      playWhenReady: json['play_when_ready'] == true,
      notice: json['notice']?.toString() ?? '',
      noticeLevel: json['notice_level']?.toString() ?? '',
      snapshot: PlaybackSnapshot.fromJson(
        objectOf(json['snapshot'], 'player.snapshot'),
      ),
    );
  }
}

class HelloResult {
  HelloResult({
    required this.api,
    required this.repo,
    required this.coreVersion,
    required this.guiVersion,
    required this.dataDir,
    required this.capabilities,
    required this.accounts,
    required this.player,
  });

  final int api;
  final int repo;
  final String coreVersion;
  final String guiVersion;
  final String dataDir;
  final List<String> capabilities;
  final Map<String, AccountBrief> accounts;
  final PlayerView player;

  bool get loudnorm => capabilities.contains('loudnorm');

  static HelloResult fromJson(Map<String, Object?> json) {
    final rawAccounts = objectOf(json['account'], 'hello.account');
    return HelloResult(
      api: (json['api'] as num).toInt(),
      repo: (json['repo'] as num).toInt(),
      coreVersion: json['core_version']?.toString() ?? '',
      guiVersion: json['gui_version']?.toString() ?? '',
      dataDir: json['data_dir']?.toString() ?? '',
      capabilities:
          (json['capabilities'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      accounts: rawAccounts.map(
        (key, value) =>
            MapEntry(key, AccountBrief.fromJson(objectOf(value, key))),
      ),
      player: PlayerView.fromJson(objectOf(json['player'], 'hello.player')),
    );
  }
}

class SongPage {
  SongPage({
    required this.songs,
    required this.total,
    required this.offset,
    required this.limit,
  });

  final List<Song> songs;
  final int total;
  final int offset;
  final int limit;

  static SongPage fromJson(Map<String, Object?> json) => SongPage(
    songs: (json['songs'] as List? ?? const [])
        .map((item) => Song.fromJson(objectOf(item, 'song')))
        .toList(),
    total: (json['total'] as num?)?.toInt() ?? 0,
    offset: (json['offset'] as num?)?.toInt() ?? 0,
    limit: (json['limit'] as num?)?.toInt() ?? 0,
  );
}

class SearchView {
  SearchView({
    required this.candidates,
    required this.pages,
    required this.hasWarning,
    required this.warning,
  });

  final List<Candidate> candidates;
  final int pages;
  final bool hasWarning;
  final String warning;

  static SearchView fromJson(Map<String, Object?> json) => SearchView(
    candidates: (json['candidates'] as List? ?? const [])
        .map((item) => Candidate.fromJson(objectOf(item, 'candidate')))
        .toList(),
    pages: (json['pages'] as num?)?.toInt() ?? 0,
    hasWarning: json['has_warning'] == true,
    warning: json['warning']?.toString() ?? '',
  );
}

class LinkView {
  LinkView({
    required this.matched,
    required this.kind,
    required this.ref,
    required this.song,
  });

  final bool matched;
  final String kind;
  final TrackRef? ref;
  final Song? song;

  static LinkView fromJson(Map<String, Object?> json) => LinkView(
    matched: json['matched'] == true,
    kind: json['kind']?.toString() ?? 'unknown',
    ref: json['ref'] == null
        ? null
        : TrackRef.fromJson(objectOf(json['ref'], 'link.ref')),
    song: json['song'] == null
        ? null
        : Song.fromJson(objectOf(json['song'], 'link.song')),
  );
}

class Accepted {
  Accepted({required this.requestId, required this.started});

  final int requestId;
  final bool started;

  static Accepted fromJson(Map<String, Object?> json) => Accepted(
    requestId: (json['request_id'] as num?)?.toInt() ?? 0,
    started: json['started'] == true,
  );
}

class PlaylistList {
  PlaylistList({required this.playlists, required this.warning});

  final List<Playlist> playlists;
  final String warning;

  static PlaylistList fromJson(Map<String, Object?> json) => PlaylistList(
    playlists: (json['playlists'] as List? ?? const [])
        .map((item) => Playlist.fromJson(objectOf(item, 'playlist')))
        .toList(),
    warning: json['warning']?.toString() ?? '',
  );
}

class SourceList {
  SourceList({required this.sources});

  final List<Map<String, Object?>> sources;
}
