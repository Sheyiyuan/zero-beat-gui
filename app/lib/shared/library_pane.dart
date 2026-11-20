import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import '../features/session.dart';
import '../features/song_actions.dart';
import '../features/library_actions.dart';
import '../features/navigation.dart';
import '../features/playlist_selection.dart';
import 'song_tile.dart';

class LibraryPane extends ConsumerStatefulWidget {
  const LibraryPane({
    super.key,
    this.tapToPlay = false,
    this.showPlaylistHeader = true,
  });
  final bool tapToPlay;
  final bool showPlaylistHeader;
  @override
  ConsumerState<LibraryPane> createState() => _LibraryPaneState();
}

class _LibraryPaneState extends ConsumerState<LibraryPane>
    with PlaylistSelection {
  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    syncSelectionTarget(library);
    if (library.loading && !library.loaded) {
      return const Center(child: Text('正在读取曲库'));
    }
    if (library.error.isNotEmpty && library.songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              library.error,
              key: const Key('library-error'),
              style: TextStyle(color: context.zero.danger),
            ),
            TextButton(
              onPressed: () => ref.read(libraryProvider.notifier).retry(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (library.isEmpty) return const EmptyLibrary();
    final current = ref.watch(playerProvider).snapshot.current?.id;
    final playlist = library.playlists
        .where((item) => item.id == library.selectedPlaylistId)
        .firstOrNull;
    final songs = visibleSongs(library);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Very short desktops (or large text scales) cannot fit a two-line
        // header plus the selection toolbar; keep the rows usable instead of
        // overflowing the pane.
        final showHeader =
            widget.showPlaylistHeader &&
            playlist != null &&
            constraints.maxHeight >= 180;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) PlaylistDetailHeader(playlist: playlist),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${songs.length} / ${library.total} 首',
                    style: TextStyle(color: context.zero.muted, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: busy ? null : toggleSelecting,
                    child: Text(selecting ? '取消多选' : '多选'),
                  ),
                  if (selecting) ...[
                    Text(
                      all
                          ? '已选全部 ${library.total} 首'
                          : '已选 ${selected.length} 首',
                    ),
                    TextButton(
                      onPressed: () => selectLoaded(library),
                      child: const Text('全选已加载歌曲'),
                    ),
                    TextButton(
                      onPressed: selectAll,
                      child: Text('选择全部 ${library.total} 首'),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '批量操作',
                      enabled: !busy && hasSelection,
                      onSelected: runBatch,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'play', child: Text('播放')),
                        PopupMenuItem(value: 'download', child: Text('下载')),
                        PopupMenuItem(value: 'next', child: Text('下一首播放')),
                        PopupMenuItem(value: 'enqueue', child: Text('加入队列')),
                        PopupMenuItem(value: 'add', child: Text('加入歌单')),
                        PopupMenuItem(value: 'remove', child: Text('移除')),
                      ],
                    ),
                  ],
                  IconButton(
                    key: const Key('library-refresh-pane'),
                    tooltip: '刷新歌单',
                    visualDensity: VisualDensity.compact,
                    onPressed: library.refreshing
                        ? null
                        : () => refreshPlaylistNow(context, ref),
                    icon: library.refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AppIcons.refresh),
                  ),
                ],
              ),
            ),
            if (busy || library.refreshing)
              LinearProgressIndicator(
                key: library.refreshing
                    ? const Key('library-refresh-progress')
                    : null,
                minHeight: 2,
              ),
            if (library.warning.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  library.warning,
                  style: TextStyle(color: context.zero.warning),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                key: const Key('library-pane-refresh'),
                onRefresh: () => refreshPlaylistNow(context, ref),
                child: ListView.builder(
                  key: PageStorageKey(library.selectedPlaylistId),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: songs.length + (library.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == songs.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            if (library.moreError.isNotEmpty)
                              Text(library.moreError),
                            TextButton(
                              key: const Key('library-load-more'),
                              onPressed: library.loadingMore
                                  ? null
                                  : ref.read(libraryProvider.notifier).loadMore,
                              child: Text(
                                library.loadingMore
                                    ? '正在加载'
                                    : library.moreError.isEmpty
                                    ? '加载更多'
                                    : '重试加载',
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final song = songs[index];
                    final last = index == songs.length - 1 && !library.hasMore;
                    return Column(
                      children: [
                        Dismissible(
                          key: ValueKey('song-dismiss-${song.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => confirmAction(
                            context,
                            '从歌单移除「${song.title}」',
                            '只从当前歌单移除，不会删除音频文件。',
                          ),
                          onDismissed: (_) => removeSong(song),
                          background: Container(
                            color: context.zero.danger,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  AppIcons.removeFromList,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '移除',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              if (selecting)
                                Checkbox(
                                  value: all || selected.contains(song.id),
                                  onChanged: busy
                                      ? null
                                      : (_) => toggleSong(song),
                                ),
                              Expanded(
                                child: SongTile(
                                  song: song,
                                  doubleTapToPlay: !widget.tapToPlay,
                                  current: current == song.id,
                                  selected: selecting
                                      ? all || selected.contains(song.id)
                                      : song.id == library.selectedSongId,
                                  onLongPress: () => showSongMenu(
                                    context,
                                    ref,
                                    song,
                                    extra: const [
                                      SongAction(
                                        id: 'select',
                                        label: '多选此曲',
                                        icon: AppIcons.select,
                                      ),
                                    ],
                                    onExtra: (_) => toggleSong(song),
                                  ),
                                  onSecondaryTap: (position) => showSongMenu(
                                    context,
                                    ref,
                                    song,
                                    position: position,
                                    extra: const [
                                      SongAction(
                                        id: 'select',
                                        label: '多选此曲',
                                        icon: AppIcons.select,
                                      ),
                                    ],
                                    onExtra: (_) => toggleSong(song),
                                  ),
                                  onTap: () {
                                    if (selecting) {
                                      toggleSong(song);
                                    } else if (widget.tapToPlay) {
                                      playFromPlaylist(song);
                                    } else {
                                      ref
                                          .read(libraryProvider.notifier)
                                          .selectSong(song.id);
                                    }
                                  },
                                  onPlay: widget.tapToPlay
                                      ? null
                                      : () => playFromPlaylist(song),
                                  trailing: SongActions(song: song),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!last)
                          const Divider(height: 1, indent: 76, endIndent: 20),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
