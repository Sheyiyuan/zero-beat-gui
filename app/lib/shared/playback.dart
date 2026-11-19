import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

String sourceLabel(SourceID source) => _sourceName(source.value);

String sourceShortLabel(SourceID source) => _sourceShort(source.value);

String accountLabel(String id) => _sourceName(id);

String _sourceName(String id) {
  return switch (id) {
    'bilibili' => '哔哩哔哩',
    'netease' => '网易云',
    'local' => '本机',
    _ => id,
  };
}

String _sourceShort(String id) {
  return switch (id) {
    'bilibili' => '哔站',
    'netease' => '网易',
    'local' => '本机',
    _ => id,
  };
}

String formatClipRangeLabel(int startMs, int endMs) {
  final start = formatClock(startMs);
  if (endMs <= 0) return '片段 $start–结尾';
  return '片段 $start–${formatClock(endMs)}';
}

String? playbackClipSubtitle({
  required int clipStartMs,
  required int clipEndMs,
  required int positionMs,
}) {
  if (clipStartMs <= 0 && clipEndMs <= 0) return null;
  return '${formatClipRangeLabel(clipStartMs, clipEndMs)} · 原曲 ${formatClock(positionMs)}';
}

String formatClock(int ms) {
  final safe = ms < 0 ? 0 : ms;
  final total = safe ~/ 1000;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String errorText(Object error) {
  if (error is RpcException) {
    return error.message.isEmpty ? '请求失败' : error.message;
  }
  final text = error.toString();
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) return text.substring(prefix.length);
  return text;
}

Song songFromTrack(Track track) {
  return Song(
    id: track.id,
    source: track.source,
    remoteId: track.externalId,
    page: track.page,
    cid: track.cid,
    title: track.title,
    artist: track.artist,
    album: track.album,
    durationMs: track.durationMs,
    cover: track.cover,
  );
}

PlayerView playerView({
  PlaybackStatus state = PlaybackStatus.valueIdle,
  int positionMs = 0,
  int durationMs = 0,
  double volume = 0.8,
  List<Song> queue = const <Song>[],
  int index = 0,
  Song? current,
  String notice = '',
  String? noticeLevel,
  bool playWhenReady = false,
  String? playbackId,
  PlaybackMode mode = PlaybackMode.valueListLoop,
}) {
  return PlayerView(
    playbackId: playbackId,
    playWhenReady: playWhenReady,
    notice: notice,
    noticeLevel: noticeLevel ?? (notice.isEmpty ? '' : 'info'),
    snapshot: PlaybackSnapshot(
      queue: queue,
      index: index,
      current: current,
      state: state,
      positionMs: positionMs,
      durationMs: durationMs,
      mode: mode,
      volume: volume,
      compDb: 0,
      songCompDb: 0,
      autoGain: false,
      muted: false,
      awaiting: false,
      requestId: 0,
      quality: Quality.valueAuto,
    ),
  );
}

PlayerView playerViewWithVolume(PlayerView view, double volume) {
  final snapshot = view.snapshot;
  return PlayerView(
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
      mode: snapshot.mode,
      volume: volume,
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

bool isPlaying(PlayerView view) =>
    view.snapshot.state == PlaybackStatus.valuePlaying;
