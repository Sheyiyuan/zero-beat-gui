import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../platform/storage.dart';
import '../shared/song_tile.dart';
import 'content_pages.dart';
import 'folder_scan.dart';
import 'navigation.dart';
import 'session.dart';
import 'song_selection.dart';

Future<BatchResult?> addSongs(
  BuildContext context,
  CoreApi api,
  List<Song> songs, {
  String playlistId = '',
}) async {
  final list = await api.playlists();
  if (!context.mounted) return null;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('加入歌单')),
          for (final source in ['bilibili', 'netease'])
            ListTile(
              title: Text(source == 'bilibili' ? '哔哩哔哩收藏夹' : '网易云歌单'),
              subtitle: const Text('只能添加同一平台的内容，电台节目不能加入歌曲歌单。'),
              onTap: () => Navigator.pop(context, 'cloud-source:$source'),
            ),
          for (final p in list.playlists.where((p) => p.kind.value != 'folder'))
            ListTile(
              title: Text(p.title),
              subtitle: Text(
                p.syncExcluded
                    ? '仅本机'
                    : p.kind.value == 'remote'
                    ? '保存到平台歌单'
                    : '本地歌单',
              ),
              onTap: () => Navigator.pop(context, p.id),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  String target = choice;
  if (choice.startsWith('cloud-source:')) {
    final source = choice.substring('cloud-source:'.length);
    final remote = await api.remotePlaylists(source, write: true);
    if (!context.mounted) return null;
    final selected = await showModalBottomSheet<RemotePlaylist>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: remote.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无可添加的歌单，请确认已登录该平台并创建歌单。'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final p in remote)
                    ListTile(
                      title: Text(p.title),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
      ),
    );
    if (selected == null) return null;
    target = 'cloud:$source:${selected.remoteId}';
  }
  final result = await api.batch(
    'add',
    target: target,
    songs: songs,
    playlistId: playlistId,
  );
  if (context.mounted) showBatchResult(context, result);
  return result;
}

void showBatchResult(BuildContext context, BatchResult result) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '完成 ${result.succeeded.length} 项，跳过 ${result.skipped.length} 项，失败 ${result.failed.length} 项${result.failed.isEmpty ? '' : '：${result.failed.first.error}'}',
      ),
    ),
  );
}

/// One playlist action shared by the row long-press/right-click menu and the
/// overflow menu, so the two entry points cannot drift apart.
class PlaylistAction {
  const PlaylistAction({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// Platform playlists show their source; every other kind is a local mirror or
/// local playlist, so it uses the local badge instead of a misleading platform.
SourceID playlistSource(Playlist playlist) =>
    playlist.kind.value == 'remote' ? playlist.source : SourceID.valueLocal;

String playlistMeta(Playlist playlist) {
  final kind = switch (playlist.kind.value) {
    'remote' => '平台',
    'mixin' => '混合',
    'folder' => '文件夹',
    _ => '本地',
  };
  final frozen = playlist.frozen ? ' · 已停止同步' : '';
  return '$kind · ${playlist.count} 首$frozen';
}

List<PlaylistAction> playlistActionsFor(Playlist playlist) => [
  const PlaylistAction(id: 'play', label: '播放歌单', icon: AppIcons.play),
  if (playlist.kind.value == 'folder')
    const PlaylistAction(
      id: 'replace',
      label: '更换文件夹或重新授权',
      icon: AppIcons.folderOpen,
    ),
  PlaylistAction(
    id: 'refresh',
    label: playlist.kind.value == 'folder' ? '重新扫描' : '刷新歌单',
    icon: AppIcons.refresh,
  ),
  if (playlist.kind.value != 'remote')
    const PlaylistAction(id: 'rename', label: '重命名', icon: AppIcons.edit),
  if (playlist.kind.value == 'mixin')
    const PlaylistAction(id: 'refs', label: '选择来源歌单', icon: AppIcons.sources),
  if (playlist.kind.value == 'remote')
    const PlaylistAction(id: 'unlock', label: '转为本地歌单', icon: AppIcons.unlock),
  const PlaylistAction(id: 'delete', label: '移除歌单', icon: AppIcons.delete),
];

Future<bool> confirmDeletePlaylist(BuildContext context, Playlist playlist) =>
    confirmAction(
      context,
      '移除「${playlist.title}」',
      playlist.kind.value == 'remote'
          ? '只移除零拍中的歌单，音频文件和平台上的原歌单保留。'
          : '只移除歌单，音频文件保留。',
    );

/// Plays a playlist from the beginning, the same way the TUI does: the whole
/// playlist is queued, and shuffle mode also randomizes which song starts.
Future<void> playPlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist, {
  List<Song>? songs,
}) async {
  final library = ref.read(libraryProvider);
  final viewing = library.selectedPlaylistId == playlist.id;
  if (viewing && library.loaded && library.total == 0) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('歌单里还没有曲目')));
    return;
  }
  final loaded = songs ?? (viewing ? library.songs : const <Song>[]);
  await perform(
    context,
    () =>
        ref.read(transportProvider).playPlaylistFromStart(playlist.id, loaded),
  );
}

/// Reloads the open playlist from its source. A plain library reload only
/// rereads the local mirror, so a song just added to a cloud or folder
/// playlist stays invisible until that mirror is considered stale.
Future<void> refreshPlaylistNow(BuildContext context, WidgetRef ref) {
  return perform(context, () async {
    final library = ref.read(libraryProvider);
    final id = library.selectedPlaylistId;
    final playlist = library.playlists
        .where((item) => item.id == id)
        .firstOrNull;
    final kind = playlist?.kind.value;
    if (id != null &&
        (kind == 'remote' || kind == 'mixin' || kind == 'folder')) {
      await ref.read(coreApiProvider).editPlaylist('refresh', id);
      return;
    }
    await ref.read(libraryProvider.notifier).refresh();
  }, source: '刷新歌单');
}

Future<void> runPlaylistAction(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
  String action,
) async {
  final api = ref.read(coreApiProvider);
  switch (action) {
    case 'play':
      await playPlaylist(context, ref, playlist);
      return;
    case 'replace':
      if (Platform.isAndroid) {
        await scanAndroidFolder(
          context,
          api,
          playlist: playlist,
          replace: true,
        );
      } else {
        final path = await getDirectoryPath(confirmButtonText: '更换目录');
        if (path == null) return;
        await api.folder('replace', id: playlist.id, path: path);
      }
    case 'refresh':
      if (playlist.kind.value == 'folder') {
        if (Platform.isAndroid) {
          await scanAndroidFolder(context, api, playlist: playlist);
        } else {
          await api.folder('rescan', id: playlist.id);
        }
      } else {
        await api.editPlaylist('refresh', playlist.id);
      }
    case 'rename':
      final title = await askText(context, '重命名歌单', initial: playlist.title);
      if (title == null || title.isEmpty) return;
      await api.editPlaylist('rename', playlist.id, title: title);
    case 'unlock':
      if (!await confirmAction(
        context,
        '转为本地歌单',
        '保留现有歌曲，转为本地歌单后不再跟随平台更新。平台上的原歌单不受影响。',
      )) {
        return;
      }
      await api.editPlaylist('unlock', playlist.id);
    case 'refs':
      await openFeature(context, '选择来源歌单', MixinEditor(playlist: playlist));
    case 'delete':
      if (!await confirmDeletePlaylist(context, playlist)) return;
      await api.editPlaylist('delete', playlist.id);
      if (Platform.isAndroid && playlist.rootPath.startsWith('content://')) {
        await AndroidStorage.releaseUnused(api, playlist.rootPath);
      }
  }
  if (context.mounted) ref.read(libraryProvider.notifier).reload();
}

Future<void> showPlaylistMenu(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist, {
  Offset? position,
}) async {
  final actions = playlistActionsFor(playlist);
  final mobile = ref.read(platformLabelProvider) == 'android';
  String? action;
  if (mobile) {
    action = await showModalBottomSheet<String>(
      context: context,
      // Use the page's own navigator so a back gesture pops the menu with the
      // route instead of leaving a root-level sheet on screen.
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
            ListTile(
              leading: PlaylistSourceIcon(playlist: playlist, size: 24),
              title: Text(
                playlist.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.zero.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(playlistMeta(playlist)),
            ),
            const Divider(height: 1),
            for (final item in actions)
              ListTile(
                key: ValueKey('playlist-menu-${item.id}'),
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () => Navigator.pop(sheetContext, item.id),
              ),
          ],
        ),
      ),
    );
  } else {
    final overlayRender = Overlay.of(
      context,
      rootOverlay: false,
    ).context.findRenderObject();
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
            key: ValueKey('playlist-menu-${item.id}'),
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
  if (selected == null || !context.mounted) return;
  await perform(
    context,
    () => runPlaylistAction(context, ref, playlist, selected),
  );
}

/// Header for the selected playlist. It exists on desktop and inside the
/// mobile detail route, and keeps the source icon, play button, and overflow
/// menu together.
class PlaylistDetailHeader extends ConsumerWidget {
  const PlaylistDetailHeader({
    required this.playlist,
    this.showTitle = true,
    super.key,
  });

  final Playlist playlist;
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final canPlay = library.songs.isNotEmpty;
    final compact = MediaQuery.sizeOf(context).width < 560;
    void play() => playPlaylist(context, ref, playlist, songs: library.songs);
    final playButton = compact
        ? FilledButton.tonalIcon(
            key: const Key('play-playlist'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: canPlay ? play : null,
            icon: const Icon(AppIcons.play, size: 16),
            label: const Text('播放全部'),
          )
        : FilledButton.tonalIcon(
            key: const Key('play-playlist'),
            onPressed: canPlay ? play : null,
            icon: const Icon(AppIcons.play),
            label: const Text('播放歌单'),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              key: ValueKey('playlist-header-${playlist.id}'),
              behavior: HitTestBehavior.opaque,
              onLongPress: () => showPlaylistMenu(context, ref, playlist),
              onSecondaryTapDown: (details) => showPlaylistMenu(
                context,
                ref,
                playlist,
                position: details.globalPosition,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showTitle) ...[
                    Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.zero.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          playlistMeta(playlist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.zero.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PlaylistSourceIcon(
                        key: ValueKey('playlist-header-source-${playlist.id}'),
                        playlist: playlist,
                        size: 16,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          playButton,
          LibraryTools(playlist: playlist),
        ],
      ),
    );
  }
}

/// Playlist row shared by the mobile home list and the desktop sidebar. It
/// owns the source badge, long-press/right-click menu, and the swipe-to-delete
/// confirmation, so both layouts behave identically.
class PlaylistRow extends ConsumerStatefulWidget {
  const PlaylistRow({
    required this.playlist,
    required this.onTap,
    this.selected = false,
    this.subtitle,
    this.trailing,
    this.contentPadding,
    this.iconSize = 20,
    super.key,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final bool selected;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;
  final double iconSize;

  @override
  ConsumerState<PlaylistRow> createState() => _PlaylistRowState();
}

class _PlaylistRowState extends ConsumerState<PlaylistRow> {
  bool _dismissed = false;

  Future<void> _delete() async {
    setState(() => _dismissed = true);
    var deleted = false;
    await perform(context, () async {
      final api = ref.read(coreApiProvider);
      await api.editPlaylist('delete', widget.playlist.id);
      if (Platform.isAndroid &&
          widget.playlist.rootPath.startsWith('content://')) {
        await AndroidStorage.releaseUnused(api, widget.playlist.rootPath);
      }
      deleted = true;
    });
    if (!mounted) return;
    if (deleted) {
      ref.read(libraryProvider.notifier).reload();
    } else {
      setState(() => _dismissed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return Dismissible(
      key: ValueKey('playlist-dismiss-${widget.playlist.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDeletePlaylist(context, widget.playlist),
      onDismissed: (_) => _delete(),
      background: Container(
        color: context.zero.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.delete, color: Colors.white),
            SizedBox(width: 8),
            Text('移除', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      child: GestureDetector(
        key: ValueKey('playlist-row-${widget.playlist.id}'),
        behavior: HitTestBehavior.opaque,
        onLongPress: () => showPlaylistMenu(context, ref, widget.playlist),
        onSecondaryTapDown: (details) => showPlaylistMenu(
          context,
          ref,
          widget.playlist,
          position: details.globalPosition,
        ),
        child: ListTile(
          selected: widget.selected,
          selectedTileColor: context.zero.accentSoft,
          contentPadding: widget.contentPadding,
          leading: PlaylistSourceIcon(
            key: ValueKey('playlist-row-source-${widget.playlist.id}'),
            playlist: widget.playlist,
            size: widget.iconSize,
          ),
          title: Text(
            widget.playlist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: widget.subtitle,
          trailing: widget.trailing,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class LibraryTools extends ConsumerWidget {
  const LibraryTools({this.playlist, super.key});
  final Playlist? playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: '管理曲库',
    icon: const Icon(AppIcons.add),
    onSelected: (action) async {
      final p = playlist;
      if (p != null && playlistActionsFor(p).any((item) => item.id == action)) {
        await perform(
          context,
          () => runPlaylistAction(context, ref, p, action),
        );
        return;
      }
      await perform(context, () async {
        final api = ref.read(coreApiProvider);
        switch (action) {
          case 'create':
          case 'local':
            final title = await askText(
              context,
              '新建${action == 'local' ? '仅本机' : ''}歌单',
            );
            if (title == null || title.isEmpty) return;
            await api.createPlaylist(title, localOnly: action == 'local');
          case 'mixin':
            await openFeature(context, '新建混合歌单', MixinEditor());
          case 'folder':
            if (Platform.isAndroid) {
              await scanAndroidFolder(context, api);
              break;
            }
            final path = await getDirectoryPath(confirmButtonText: '添加文件夹歌单');
            if (path != null) await api.folder('add', path: path);
          case 'import':
            await openFeature(context, '导入平台歌单', const ImportBody());
        }
      });
      if (context.mounted) ref.read(libraryProvider.notifier).reload();
    },
    itemBuilder: (context) => [
      const PopupMenuItem(value: 'create', child: Text('新建歌单')),
      const PopupMenuItem(value: 'local', child: Text('新建仅本机歌单')),
      const PopupMenuItem(value: 'mixin', child: Text('新建混合歌单')),
      const PopupMenuItem(value: 'folder', child: Text('添加本地文件夹')),
      const PopupMenuItem(value: 'import', child: Text('导入平台歌单')),
      if (playlist != null) ...[
        const PopupMenuDivider(),
        for (final item in playlistActionsFor(playlist!))
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
    ],
  );
}

class MixinEditor extends ConsumerStatefulWidget {
  const MixinEditor({this.playlist, super.key});
  final Playlist? playlist;
  @override
  ConsumerState<MixinEditor> createState() => _MixinEditorState();
}

class _MixinEditorState extends ConsumerState<MixinEditor> {
  final selected = <String>{};
  bool initialized = false;
  bool busy = false;
  @override
  Widget build(BuildContext context) => AsyncFeature<List<Playlist>>(
    load: () async {
      final api = ref.read(coreApiProvider);
      final all = (await api.playlists()).playlists;
      if (!initialized && widget.playlist != null) {
        selected.addAll(
          (await api.mixinRefs(widget.playlist!.id)).map((p) => p.id),
        );
      }
      initialized = true;
      return all.where((p) => p.kind.value != 'mixin').toList();
    },
    builder: (context, data, reload) => Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('选择要合并的歌单，歌曲会随所选歌单更新。包含文件夹或仅本机歌单时，混合歌单也只保留在本机。'),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final p in data)
                CheckboxListTile(
                  title: Text(p.title),
                  subtitle: p.syncExcluded ? const Text('仅本机') : null,
                  value: selected.contains(p.id),
                  onChanged: busy
                      ? null
                      : (on) => setState(() {
                          if (on == true) {
                            selected.add(p.id);
                          } else {
                            selected.remove(p.id);
                          }
                        }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: busy || selected.isEmpty
                ? null
                : () => perform(context, () async {
                    setState(() => busy = true);
                    try {
                      final api = ref.read(coreApiProvider);
                      if (widget.playlist != null) {
                        await api.editPlaylist(
                          'refs.set',
                          widget.playlist!.id,
                          refs: selected.toList(),
                        );
                      } else {
                        final title = await askText(context, '混合歌单名称');
                        if (title == null || title.isEmpty) return;
                        await api.createPlaylist(
                          title,
                          kind: 'mixin',
                          refs: selected.toList(),
                        );
                      }
                      if (context.mounted) Navigator.pop(context);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  }, success: '已保存'),
            child: const Text('保存'),
          ),
        ),
      ],
    ),
  );
}

class ImportBody extends ConsumerStatefulWidget {
  const ImportBody({super.key});
  @override
  ConsumerState<ImportBody> createState() => _ImportBodyState();
}

class _ImportBodyState extends ConsumerState<ImportBody> {
  String source = 'netease';
  final importing = <String>{};
  @override
  Widget build(BuildContext context) => Column(
    children: [
      DropdownButton<String>(
        value: source,
        items: const [
          DropdownMenuItem(value: 'netease', child: Text('网易云')),
          DropdownMenuItem(value: 'bilibili', child: Text('哔哩哔哩')),
        ],
        onChanged: (v) => setState(() => source = v!),
      ),
      Expanded(
        child: AsyncFeature<List<RemotePlaylist>>(
          target: source,
          load: () => ref.read(coreApiProvider).remotePlaylists(source),
          builder: (context, data, reload) => data.isEmpty
              ? const Center(child: Text('暂无可导入的歌单。请确认已登录该平台，且账号中有歌单或收藏夹。'))
              : ListView(
                  children: [
                    for (final p in data)
                      ListTile(
                        title: Text(p.title),
                        subtitle: Text('${p.count} 首'),
                        trailing: TextButton(
                          onPressed: importing.contains(p.id)
                              ? null
                              : () => perform(context, () async {
                                  setState(() => importing.add(p.id));
                                  try {
                                    await ref
                                        .read(coreApiProvider)
                                        .importPlaylist(p);
                                    ref.read(libraryProvider.notifier).reload();
                                  } finally {
                                    if (mounted) {
                                      setState(() => importing.remove(p.id));
                                    }
                                  }
                                }, success: '已导入'),
                          child: Text(importing.contains(p.id) ? '导入中' : '导入'),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    ],
  );
}

class LocalSearchBody extends ConsumerStatefulWidget {
  const LocalSearchBody({this.playlistId = '', super.key});
  final String playlistId;
  @override
  ConsumerState<LocalSearchBody> createState() => _LocalSearchBodyState();
}

class _LocalSearchBodyState extends ConsumerState<LocalSearchBody> {
  String query = '';
  bool all = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(
            labelText: '搜索本地曲库',
            prefixIcon: Icon(AppIcons.search),
          ),
          onSubmitted: (v) => setState(() => query = v),
        ),
      ),
      if (widget.playlistId.isNotEmpty)
        SwitchListTile(
          title: const Text('搜索整个本地曲库'),
          value: all,
          onChanged: (v) => setState(() => all = v),
        ),
      Expanded(
        child: SongSelectionScope(
          target: (query, all, widget.playlistId),
          child: AsyncFeature<List<Song>>(
            target: '$query:$all',
            load: () => ref
                .read(coreApiProvider)
                .localSearch(query, playlistId: all ? '' : widget.playlistId),
            builder: (context, data, reload) => ListView(
              children: [
                const SongSelectionBar(),
                for (final song in data) FeatureSong(song: song),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
