import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../features/session.dart';
import '../features/song_actions.dart';
import '../features/library_actions.dart';
import '../features/navigation.dart';
import 'song_tile.dart';

class LibraryPane extends ConsumerStatefulWidget {
  const LibraryPane({super.key, this.tapToPlay = false});
  final bool tapToPlay;
  @override
  ConsumerState<LibraryPane> createState() => _LibraryPaneState();
}

class _LibraryPaneState extends ConsumerState<LibraryPane> {
  final selected = <String>{};
  String? target;
  bool all = false;
  bool selecting = false;
  bool busy = false;
  void _toggle(Song song) => setState(() {
    selecting = true;
    all = false;
    if (!selected.add(song.id)) selected.remove(song.id);
  });
  Future<void> _batch(String action) async {
    final library = ref.read(libraryProvider);
    final batchTarget = library.selectedPlaylistId;
    final songs = library.songs.where((s) => selected.contains(s.id)).toList();
    final playlist = all ? library.selectedPlaylistId ?? '' : '';
    final api = ref.read(coreApiProvider);
    setState(() => busy = true);
    await perform(context, () async {
      if (action == 'download') {
        final result = await api.downloadSelection(
          songs: songs,
          playlistId: playlist,
        );
        if (mounted) {
          showBatchResult(context, result);
          _keepFailures(result, batchTarget);
        }
        return;
      }
      if (action == 'add') {
        final result = await addSongs(
          context,
          api,
          songs,
          playlistId: playlist,
        );
        if (mounted && result != null) _keepFailures(result, batchTarget);
        return;
      }
      if (action == 'remove' &&
          !await confirmAction(
            context,
            '移除选中曲目',
            '从本地歌单移除，混合歌单会记录排除关系；音频文件会保留。',
          )) {
        return;
      }
      if (action == 'play') {
        ref.read(interruptionPolicyProvider).noteUserTransport();
      }
      final result = await api.batch(
        action,
        playlistId: playlist,
        songs: songs,
        target: action == 'play' ? '' : library.selectedPlaylistId ?? '',
      );
      if (!mounted) return;
      showBatchResult(context, result);
      _keepFailures(result, batchTarget);
    });
    if (mounted) setState(() => busy = false);
  }

  void _keepFailures(BatchResult result, String? batchTarget) {
    if (ref.read(libraryProvider).selectedPlaylistId != batchTarget) return;
    setState(() {
      all = false;
      selected.clear();
      selected.addAll(result.failed.map((f) => f.songId));
      selecting = selected.isNotEmpty;
    });
  }

  Future<void> _play(Song song, LibraryState library) => perform(
    context,
    () => ref
        .read(transportProvider)
        .playPlaylistSong(song, library.selectedPlaylistId!, library.songs),
  );
  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    if (target != library.selectedPlaylistId) {
      target = library.selectedPlaylistId;
      selected.clear();
      all = false;
      selecting = false;
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tapToPlay && library.songs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: busy
                    ? null
                    : () => ref
                          .read(transportProvider)
                          .playPlaylistSong(
                            library.songs.first,
                            library.selectedPlaylistId!,
                            library.songs,
                          ),
                child: const Text('播放全部'),
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${library.songs.length} / ${library.total} 首'),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      selecting = !selecting;
                      selected.clear();
                      all = false;
                    }),
              child: Text(selecting ? '取消多选' : '多选'),
            ),
            if (selecting) ...[
              Text(
                all
                    ? '已选全部 ${library.total} 首'
                    : '已选已加载曲目 ${selected.length} 首',
              ),
              TextButton(
                onPressed: () => setState(() {
                  all = false;
                  selected.addAll(library.songs.map((s) => s.id));
                }),
                child: const Text('选择已加载'),
              ),
              TextButton(
                onPressed: () => setState(() => all = true),
                child: Text('选择全部 ${library.total} 首'),
              ),
              PopupMenuButton<String>(
                tooltip: '批量操作',
                enabled: !busy && (all || selected.isNotEmpty),
                onSelected: _batch,
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
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (library.warning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              library.warning,
              style: TextStyle(color: context.zero.warning),
            ),
          ),
        Expanded(
          child: ListView.builder(
            key: PageStorageKey(library.selectedPlaylistId),
            itemCount: library.songs.length + (library.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == library.songs.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (library.moreError.isNotEmpty) Text(library.moreError),
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
              final song = library.songs[index];
              final last =
                  index == library.songs.length - 1 && !library.hasMore;
              return Column(
                children: [
                  Row(
                    children: [
                      if (selecting)
                        Checkbox(
                          value: all || selected.contains(song.id),
                          onChanged: busy ? null : (_) => _toggle(song),
                        ),
                      Expanded(
                        child: SongTile(
                          song: song,
                          doubleTapToPlay: !widget.tapToPlay,
                          current: current == song.id,
                          selected: selecting
                              ? all || selected.contains(song.id)
                              : song.id == library.selectedSongId,
                          onLongPress: () => _toggle(song),
                          onTap: () {
                            if (selecting) {
                              _toggle(song);
                            } else if (widget.tapToPlay) {
                              _play(song, library);
                            } else {
                              ref
                                  .read(libraryProvider.notifier)
                                  .selectSong(song.id);
                            }
                          },
                          onPlay: () => _play(song, library),
                          trailing: SongActions(song: song),
                        ),
                      ),
                    ],
                  ),
                  if (!last)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: context.zero.line,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
