import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'package:zero_beat_gui/shared/playback.dart';

const longTitle = '很长很长的示例标题用来检查单行省略时仍然保留完整语义';

const longBilibiliTitle =
    '【B站】这是一个非常长的视频标题，用来检查正在播放页面的折叠与展开，'
    '标题里包含平台前缀、节目名称、嘉宾姓名和更多说明文字，'
    '默认最多显示两行，展开后仍然不能把播放控件挤出屏幕，'
    '收起之后又要回到紧凑的高度。';

Song sampleSong({
  String id = 'song-1',
  String title = '示例歌曲',
  String artist = '示例歌手',
  SourceID source = SourceID.valueNetease,
  int durationMs = 180000,
}) {
  return Song(
    id: id,
    source: source,
    remoteId: id,
    page: 1,
    cid: BigInt.zero,
    title: title,
    artist: artist,
    album: '',
    durationMs: durationMs,
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
