import 'song_selection.dart';
import 'folder_scan.dart';
import '../platform/storage.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import 'session.dart';
import 'navigation.dart';
import 'content_pages.dart';

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
              title: Text(source == 'bilibili' ? 'B 站云端收藏夹' : '网易云云端歌单'),
              subtitle: const Text('仅添加同来源内容；节目不写入歌曲歌单'),
              onTap: () => Navigator.pop(context, 'cloud-source:$source'),
            ),
          for (final p in list.playlists.where((p) => p.kind.value != 'folder'))
            ListTile(
              title: Text(p.title),
              subtitle: Text(
                p.syncExcluded
                    ? '仅本机'
                    : p.kind.value == 'remote'
                    ? '写入平台歌单'
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
                child: Text('没有可用的云端歌单，请先登录对应平台'),
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

class LibraryTools extends ConsumerWidget {
  const LibraryTools({this.playlist, super.key});
  final Playlist? playlist;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: '管理曲库',
    icon: const Icon(Icons.add_circle_outline),
    onSelected: (action) => perform(context, () async {
      final api = ref.read(coreApiProvider);
      final p = playlist;
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
        case 'replace':
          if (p == null) return;
          if (Platform.isAndroid) {
            await scanAndroidFolder(context, api, playlist: p, replace: true);
          } else {
            final path = await getDirectoryPath(confirmButtonText: '更换目录');
            if (path != null) await api.folder('replace', id: p.id, path: path);
          }
        case 'import':
          await openFeature(context, '导入平台歌单', const ImportBody());
        case 'rename':
          if (p == null) return;
          final title = await askText(context, '重命名歌单', initial: p.title);
          if (title != null && title.isNotEmpty) {
            await api.editPlaylist('rename', p.id, title: title);
          }
        case 'delete':
          if (p == null) return;
          if (await confirmAction(
            context,
            '移除「${p.title}」',
            '仅移除本地歌单或镜像，不删除原音频文件，也不修改平台歌单。',
          )) {
            await api.editPlaylist('delete', p.id);
            if (Platform.isAndroid && p.rootPath.startsWith('content://')) {
              await AndroidStorage.releaseUnused(api, p.rootPath);
            }
          }
        case 'refresh':
          if (p != null) {
            if (p.kind.value == 'folder') {
              if (Platform.isAndroid) {
                await scanAndroidFolder(context, api, playlist: p);
              } else {
                await api.folder('rescan', id: p.id);
              }
            } else {
              await api.editPlaylist('refresh', p.id);
            }
          }
        case 'unlock':
          if (p != null &&
              await confirmAction(
                context,
                '解锁歌单',
                '保留曲目并转为本地歌单，此副本不再跟随平台刷新。',
              )) {
            await api.editPlaylist('unlock', p.id);
          }
        case 'refs':
          if (p != null) {
            await openFeature(context, '编辑引用', MixinEditor(playlist: p));
          }
      }
      ref.read(libraryProvider.notifier).reload();
    }),
    itemBuilder: (context) => [
      const PopupMenuItem(value: 'create', child: Text('新建歌单')),
      const PopupMenuItem(value: 'local', child: Text('新建仅本机歌单')),
      const PopupMenuItem(value: 'mixin', child: Text('新建混合歌单')),
      const PopupMenuItem(value: 'folder', child: Text('添加本地文件夹')),
      const PopupMenuItem(value: 'import', child: Text('导入平台歌单')),
      if (playlist != null) ...[
        if (playlist!.kind.value == 'folder')
          const PopupMenuItem(value: 'replace', child: Text('更换目录／重新授权')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'refresh', child: Text('刷新／重新扫描')),
        if (playlist!.kind.value != 'remote')
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
        if (playlist!.kind.value == 'mixin')
          const PopupMenuItem(value: 'refs', child: Text('编辑混合引用')),
        if (playlist!.kind.value == 'remote')
          const PopupMenuItem(value: 'unlock', child: Text('解锁为本地歌单')),
        const PopupMenuItem(value: 'delete', child: Text('移除歌单')),
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
          child: Text('引用歌单会随来源更新。包含文件夹或仅本机歌单时，新混合歌单仅保留在本机。'),
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
            child: const Text('保存引用'),
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
          DropdownMenuItem(value: 'bilibili', child: Text('B 站')),
        ],
        onChanged: (v) => setState(() => source = v!),
      ),
      Expanded(
        child: AsyncFeature<List<RemotePlaylist>>(
          target: source,
          load: () => ref.read(coreApiProvider).remotePlaylists(source),
          builder: (context, data, reload) => data.isEmpty
              ? const Center(child: Text('暂无可导入歌单，请先登录对应账号'))
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
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (v) => setState(() => query = v),
        ),
      ),
      if (widget.playlistId.isNotEmpty)
        SwitchListTile(
          title: const Text('搜索本地全部'),
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
