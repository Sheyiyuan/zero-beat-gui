import '../features/library_actions.dart';
import '../features/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        Row(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('曲库', style: TextStyle(fontSize: 22)),
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
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey('mobile-playlists'),
            itemCount: library.playlists.length,
            itemBuilder: (context, index) {
              final playlist = library.playlists[index];
              return ListTile(
                title: Text(playlist.title),
                leading: const Icon(Icons.queue_music),
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
              );
            },
          ),
        ),
      ],
    );
  }
}
