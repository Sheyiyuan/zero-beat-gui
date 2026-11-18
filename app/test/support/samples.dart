import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'package:zero_beat_gui/shared/playback.dart';

const longTitle = '很长很长的示例标题用来检查单行省略时仍然保留完整语义';

Song sampleSong({
  String id = 'song-1',
  String title = '示例歌曲',
  String artist = '示例歌手',
}) {
  return Song(
    id: id,
    source: SourceID.valueNetease,
    remoteId: id,
    page: 1,
    cid: BigInt.zero,
    title: title,
    artist: artist,
    album: '',
    durationMs: 180000,
    cover: '',
  );
}

Playlist samplePlaylist({
  String id = 'list-1',
  String title = '本地歌曲',
  int count = 0,
}) {
  return Playlist(
    id: id,
    source: SourceID.valueLocal,
    title: title,
    kind: PlaylistKind.valueLocal,
    remoteId: '',
    count: count,
    frozen: false,
    syncExcluded: false,
    rootPath: '',
    scanStatus: '',
    hasScanError: false,
  );
}

HelloResult sampleHello() {
  return HelloResult(
    api: 1,
    repo: 3,
    coreVersion: '0.8.0',
    guiVersion: '0.1.0-dev',
    dataDir: '',
    capabilities: const ['library', 'search', 'link', 'player', 'clip'],
    accounts: {
      'bilibili': AccountBrief(loggedIn: false, name: ''),
      'netease': AccountBrief(loggedIn: false, name: ''),
    },
    player: playerView(),
  );
}
