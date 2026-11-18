import '../app/chrome.dart';
import '../app/theme.dart';
import '../features/library_actions.dart';
import '../features/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart' hide Clip;
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
      return const Column(
        children: [
          Align(alignment: Alignment.centerRight, child: LibraryTools()),
          Expanded(child: EmptyLibrary()),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: PageHeader(
                  title: '曲库',
                  subtitle: '最近使用的歌单、本机内容和已导入的平台歌单。',
                ),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: library.playlists.length,
            itemBuilder: (context, index) {
              final playlist = library.playlists[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: context.zero.surface,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    title: Text(playlist.title),
                    subtitle: Text(_playlistMeta(playlist)),
                    leading: CircleAvatar(
                      backgroundColor: context.zero.accentSoft,
                      foregroundColor: context.zero.accent,
                      child: const Icon(Icons.queue_music),
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
                            Align(
                              alignment: Alignment.centerRight,
                              child: LibraryTools(playlist: playlist),
                            ),
                            const Expanded(child: LibraryPane(tapToPlay: true)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
