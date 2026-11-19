import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/chrome.dart';
import '../app/theme.dart';
import '../features/library_actions.dart';
import '../features/navigation.dart';
import '../features/session.dart';
import '../shared/library_pane.dart';
import '../shared/song_tile.dart';

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
      return Column(
        children: [
          const Align(alignment: Alignment.centerRight, child: LibraryTools()),
          Expanded(
            child: RefreshIndicator(
              key: const Key('mobile-library-refresh-empty'),
              onRefresh: () => refreshPlaylistNow(context, ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 360, child: EmptyLibrary())],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: PageHeader(title: '曲库', subtitle: '本地音乐与导入的平台歌单。'),
              ),
              IconButton(
                tooltip: '搜索本地曲库',
                icon: const Icon(AppIcons.localSearch),
                onPressed: () =>
                    openFeature(context, '本地曲库搜索', const LocalSearchBody()),
              ),
              const LibraryTools(),
            ],
          ),
        ),
        if (library.refreshing)
          const LinearProgressIndicator(
            key: Key('mobile-library-refresh-progress'),
            minHeight: 2,
          ),
        if (library.warning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                library.warning,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.zero.warning, fontSize: 12),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            key: const Key('mobile-library-refresh'),
            onRefresh: () => refreshPlaylistNow(context, ref),
            child: ListView.builder(
              key: const PageStorageKey('mobile-playlists'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              itemCount: library.playlists.length,
              itemBuilder: (context, index) {
                final playlist = library.playlists[index];
                final last = index == library.playlists.length - 1;
                return Column(
                  children: [
                    if (index > 0)
                      const Divider(height: 1, indent: 80, endIndent: 20),
                    PlaylistRow(
                      key: ValueKey('playlist-item-${playlist.id}'),
                      playlist: playlist,
                      iconSize: 44,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      subtitle: Text(
                        playlistMeta(playlist),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        AppIcons.chevronRight,
                        size: 18,
                        color: context.zero.muted.withValues(alpha: 0.6),
                      ),
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
                              PlaylistDetailHeader(
                                playlist: playlist,
                                showTitle: false,
                              ),
                              const Expanded(
                                child: LibraryPane(
                                  tapToPlay: true,
                                  showPlaylistHeader: false,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (last) const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
