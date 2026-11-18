import '../app/chrome.dart';
import '../app/theme.dart';
import '../features/library_actions.dart';
import '../features/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart' hide Clip;
import '../features/playback_clip.dart';
import '../features/session.dart';
import '../shared/library_pane.dart';
import '../shared/playback.dart';
import '../shared/player_bar.dart';
import '../shared/song_tile.dart';
import 'full_player_page.dart';

/// A real nested route preserves the playlist list and its scroll offset.
class MobileLibraryPage extends ConsumerWidget {
  const MobileLibraryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    if (library.playlists.isEmpty) {
      if (library.loading) return const Center(child: Text('正在读取曲库'));
      if (library.error.isNotEmpty) {
        return Center(
          child: TextButton(
            onPressed: ref.read(libraryProvider.notifier).retry,
            child: Text('${library.error}\n重试'),
          ),
        );
      }
      return const Column(
        children: [
          Align(alignment: Alignment.centerRight, child: LibraryTools()),
          Expanded(child: EmptyLibrary()),
        ],
      );
    }
    final player = ref.watch(playerProvider).snapshot;
    final current = player.current;
    final hasPlayback =
        current != null && player.state != PlaybackStatus.valueIdle;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: PageHeader(title: '曲库', subtitle: '歌单、本机与平台导入内容。'),
              ),
              IconButton(
                tooltip: '搜索本地曲库',
                icon: const Icon(Icons.manage_search),
                onPressed: () =>
                    openFeature(context, '本地曲库搜索', const LocalSearchBody()),
              ),
              const LibraryTools(),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey('mobile-playlists'),
            padding: EdgeInsets.fromLTRB(0, 0, 0, hasPlayback ? 8 : 16),
            itemCount: library.playlists.length + (hasPlayback ? 1 : 0),
            itemBuilder: (context, index) {
              if (hasPlayback && index == 0) {
                return _ContinuePlaybackRow(song: current);
              }
              final playlistIndex = hasPlayback ? index - 1 : index;
              final playlist = library.playlists[playlistIndex];
              final last = playlistIndex == library.playlists.length - 1;
              return Column(
                children: [
                  if (hasPlayback || playlistIndex > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 20,
                      endIndent: 20,
                      color: context.zero.line,
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _playlistMeta(playlist),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (library.selectedPlaylistId != playlist.id ||
                          !library.loaded) {
                        ref
                            .read(libraryProvider.notifier)
                            .selectPlaylist(playlist.id);
                      }
                      openFeature(
                        context,
                        playlist.title,
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _playlistMeta(playlist),
                                      style: TextStyle(
                                        color: context.zero.muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  LibraryTools(playlist: playlist),
                                ],
                              ),
                            ),
                            const Expanded(child: LibraryPane(tapToPlay: true)),
                          ],
                        ),
                      );
                    },
                  ),
                  if (last && !hasPlayback) const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinuePlaybackRow extends ConsumerWidget {
  const _ContinuePlaybackRow({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final clipInfo = ref.watch(displayedClipProvider);
    final clip = clipInfo != null
        ? playbackClipSubtitle(
            clipStartMs: clipInfo.startMs,
            clipEndMs: clipInfo.endMs,
            positionMs: view.snapshot.positionMs,
          )
        : null;
    final subtitle =
        clip ?? '${song.artist} · ${sourceShortLabel(song.source)}';
    final playing = isPlaying(view);
    return Material(
      color: context.zero.accentSoft,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: CoverArt(cover: song.cover, size: 44),
        title: Text(
          '继续播放',
          style: TextStyle(fontSize: 12, color: context.zero.muted),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.zero.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: clip != null ? context.zero.accent : context.zero.muted,
                fontSize: 13,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          tooltip: playing ? '暂停' : '播放',
          onPressed: () => ref.read(transportProvider).toggle(),
          icon: Icon(
            playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
          ),
          color: context.zero.accent,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (context) => const FullPlayerPage()),
        ),
      ),
    );
  }
}

String _playlistMeta(Playlist playlist) {
  final kind = switch (playlist.kind.value) {
    'remote' => '平台',
    'mixin' => '混合',
    'folder' => '文件夹',
    _ => '本地',
  };
  final frozen = playlist.frozen ? ' · 已冻结' : '';
  return '$kind · ${playlist.count} 首$frozen';
}
