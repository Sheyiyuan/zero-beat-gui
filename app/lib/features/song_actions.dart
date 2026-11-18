import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import '../app/providers.dart';
import 'content_pages.dart';
import 'library_actions.dart';
import 'lyrics_page.dart';
import 'navigation.dart';

class SongActions extends ConsumerWidget {
  const SongActions({required this.song, super.key});
  final Song song;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: '歌曲操作',
    icon: const Icon(Icons.more_horiz),
    onSelected: (action) => perform(context, () async {
      final api = ref.read(coreApiProvider);
      switch (action) {
        case 'download':
          final result = await api.downloadSelection(songs: [song]);
          if (context.mounted) showBatchResult(context, result);
        case 'next':
          await api.insertNext(song);
        case 'enqueue':
          await api.enqueue(song);
        case 'save':
          await addSongs(context, api, [song]);
        case 'comments':
          if (context.mounted) {
            await openFeature(
              context,
              '${song.title} · 评论',
              ContentBody(song: song),
            );
          }
        case 'related':
          if (context.mounted) {
            await openFeature(
              context,
              '${song.title} · 推荐',
              ContentBody(song: song, related: true),
            );
          }
        case 'authors':
          if (context.mounted) {
            await openAuthors(context, api, song, authorsOnly: false);
          }
        case 'lyrics':
          if (context.mounted) {
            await openFeature(
              context,
              '${song.title} · 歌词',
              LyricsBody(song: song),
            );
          }
      }
    }),
    itemBuilder: (context) => [
      if (song.source.value != 'local')
        const PopupMenuItem(value: 'download', child: Text('下载')),
      const PopupMenuItem(value: 'next', child: Text('下一首播放')),
      const PopupMenuItem(value: 'enqueue', child: Text('加入队列')),
      const PopupMenuItem(value: 'save', child: Text('加入歌单')),
      const PopupMenuItem(value: 'lyrics', child: Text('歌词与来源')),
      if (song.source.value != 'local') ...[
        const PopupMenuItem(value: 'comments', child: Text('查看评论')),
        const PopupMenuItem(value: 'related', child: Text('相关推荐')),
        const PopupMenuItem(value: 'authors', child: Text('此曲作者／所属电台')),
      ],
    ],
  );
}
