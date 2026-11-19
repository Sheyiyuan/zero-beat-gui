import 'dart:async';

import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import 'content_pages.dart';
import 'library_actions.dart';
import 'lyrics_page.dart';
import 'navigation.dart';
import 'session.dart';

/// One entry shared by the trailing overflow button, right-click menu, and
/// mobile long-press sheet. Keeping the action table in one place prevents
/// the three entry points from drifting apart.
class SongAction {
  const SongAction({required this.id, required this.label, required this.icon});

  final String id;
  final String label;
  final IconData icon;
}

List<SongAction> songActionsFor(Song song) => [
  const SongAction(id: 'play', label: '播放', icon: AppIcons.play),
  if (song.source.value != 'local')
    const SongAction(id: 'download', label: '下载', icon: AppIcons.download),
  const SongAction(id: 'next', label: '下一首播放', icon: AppIcons.playNext),
  const SongAction(id: 'enqueue', label: '加入队列', icon: AppIcons.queue),
  const SongAction(id: 'save', label: '加入歌单', icon: AppIcons.addToPlaylist),
  const SongAction(id: 'lyrics', label: '歌词与来源', icon: AppIcons.lyrics),
  if (song.source.value != 'local') ...[
    const SongAction(id: 'comments', label: '查看评论', icon: AppIcons.comments),
    const SongAction(id: 'related', label: '相关推荐', icon: AppIcons.related),
    const SongAction(id: 'authors', label: '作者／所属电台', icon: AppIcons.person),
  ],
];

Future<void> runSongAction(
  BuildContext context,
  WidgetRef ref,
  Song song,
  String action,
) async {
  final api = ref.read(coreApiProvider);
  switch (action) {
    case 'play':
      ref.read(interruptionPolicyProvider).noteUserTransport();
      await ref.read(transportProvider).playSong(song);
    case 'download':
      final result = await api.downloadSelection(songs: [song]);
      if (context.mounted) showBatchResult(context, result);
    case 'next':
      await api.insertNext(song);
    case 'enqueue':
      await api.enqueue(song);
    case 'save':
      await addSongs(context, api, [song]);
    case 'lyrics':
      if (context.mounted) {
        await openFeature(
          context,
          '${song.title} · 歌词',
          LyricsBody(song: song),
        );
      }
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
  }
}

String? _extraId(Iterable<SongAction> extra, String id) {
  for (final item in extra) {
    if (item.id == id) return id;
  }
  return null;
}

Future<void> showSongMenu(
  BuildContext context,
  WidgetRef ref,
  Song song, {
  Offset? position,
  List<SongAction> extra = const <SongAction>[],
  FutureOr<void> Function(String action)? onExtra,
}) async {
  final actions = <SongAction>[...songActionsFor(song), ...extra];
  final mobile = ref.read(platformLabelProvider) == 'android';
  String? action;
  if (mobile) {
    action = await showModalBottomSheet<String>(
      context: context,
      // Stay on the route's own navigator. Attaching the sheet to the root
      // navigator leaves it floating above the page after a back gesture pops
      // the nested library route.
      useRootNavigator: false,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      backgroundColor: context.zero.surface,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.zero.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final item in actions)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () => Navigator.pop(sheetContext, item.id),
              ),
          ],
        ),
      ),
    );
  } else {
    final overlayRender = Overlay.of(context).context.findRenderObject();
    final overlay = overlayRender is RenderBox ? overlayRender : null;
    final anchor =
        position ??
        Offset(
          (overlay?.size.width ?? MediaQuery.sizeOf(context).width) / 2,
          (overlay?.size.height ?? MediaQuery.sizeOf(context).height) / 2,
        );
    final rect = RelativeRect.fromLTRB(
      anchor.dx,
      anchor.dy,
      (overlay?.size.width ?? 0) - anchor.dx,
      (overlay?.size.height ?? 0) - anchor.dy,
    );
    action = await showMenu<String>(
      context: context,
      useRootNavigator: false,
      position: rect,
      items: [
        for (final item in actions)
          PopupMenuItem(
            value: item.id,
            child: Row(
              children: [
                Icon(item.icon, size: 18),
                const SizedBox(width: 12),
                Text(item.label),
              ],
            ),
          ),
      ],
    );
  }
  final selected = action;
  final handler = onExtra;
  if (selected == null || !context.mounted) return;
  if (_extraId(extra, selected) != null && handler != null) {
    await handler(selected);
    return;
  }
  await perform(context, () => runSongAction(context, ref, song, selected));
}

class SongActions extends ConsumerWidget {
  const SongActions({
    required this.song,
    this.extra = const <SongAction>[],
    this.onExtra,
    super.key,
  });

  final Song song;
  final List<SongAction> extra;
  final FutureOr<void> Function(String action)? onExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: '歌曲操作',
    icon: const Icon(AppIcons.more),
    onSelected: (action) async {
      final handler = onExtra;
      if (_extraId(extra, action) != null && handler != null) {
        await handler(action);
        return;
      }
      await perform(context, () => runSongAction(context, ref, song, action));
    },
    itemBuilder: (context) => [
      for (final item in [...songActionsFor(song), ...extra])
        PopupMenuItem(
          value: item.id,
          child: Row(
            children: [
              Icon(item.icon, size: 18),
              const SizedBox(width: 12),
              Text(item.label),
            ],
          ),
        ),
    ],
  );
}
