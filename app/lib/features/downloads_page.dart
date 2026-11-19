import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import '../shared/refreshable.dart';
import 'navigation.dart';
import 'tasks_page.dart';
import 'session.dart';
import '../platform/storage.dart';

class DownloadsBody extends ConsumerStatefulWidget {
  const DownloadsBody({super.key});
  @override
  ConsumerState<DownloadsBody> createState() => _DownloadsBodyState();
}

class _DownloadsBodyState extends ConsumerState<DownloadsBody> {
  StreamSubscription<String>? events;
  int version = 0;
  @override
  void initState() {
    super.initState();
    events = ref.read(coreApiProvider).changes.listen((kind) {
      if (mounted && (kind == 'download.changed' || kind == 'all.changed')) {
        setState(() => version++);
      }
    });
  }

  @override
  void dispose() {
    events?.cancel();
    super.dispose();
  }

  Future<void> _fileAction(String action, DownloadEntry entry) async {
    final api = ref.read(coreApiProvider);
    await perform(context, () async {
      final d = entry.download;
      switch (action) {
        case 'play':
          if (entry.song != null) {
            await ref.read(transportProvider).playSong(entry.song!);
          }
        case 'retry':
          if (entry.song != null) {
            await api.downloadSelection(songs: [entry.song!], force: true);
          }
        case 'remove_record':
        case 'delete_file':
          if (await confirmAction(
            context,
            action == 'delete_file' ? '删除音频文件' : '移除下载记录',
            action == 'delete_file'
                ? '将删除「${entry.song?.title ?? d.songId}」的文件和下载记录。'
                : '文件会保留，播放时将不再优先使用这个下载文件。',
          )) {
            await api.downloadAction(action, songId: d.songId);
          }
        case 'share':
          await SharePlus.instance.share(
            ShareParams(files: [XFile(d.path)], title: entry.song?.title),
          );
        case 'export':
        case 'save_as':
          bool exported = false;
          if (Platform.isAndroid) {
            exported = await AndroidStorage.exportDownload(
              d.path,
              saveAs: action == 'save_as',
            );
          } else {
            final output = await getSaveLocation(
              suggestedName: d.path.split('/').last,
            );
            if (output != null) {
              await XFile(d.path).saveTo(output.path);
              exported = true;
            }
          }
          if (exported && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('音频文件已导出')));
          }
        case 'locate':
          await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [
            File(d.path).parent.path,
          ]);
      }
    });
    if (mounted) setState(() => version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(coreApiProvider);
    return RefreshableFeature<(List<DownloadTask>, List<DownloadEntry>)>(
      target: version,
      retain: true,
      load: () async => (await api.downloadTasks(), await api.downloads()),
      builder: (context, data, reload) => RefreshableListView(
        key: const Key('downloads-refresh'),
        onRefresh: reload,
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('任务与操作结果'),
            trailing: const Icon(AppIcons.chevronRight, size: 18),
            onTap: () => openFeature(context, '任务与操作结果', const TasksBody()),
          ),
          Row(
            children: [
              const Expanded(child: Text('下载任务 · 最多同时下载 2 首')),
              TextButton(
                onPressed: () =>
                    perform(context, () => api.downloadAction('cancel_all')),
                child: const Text('全部取消'),
              ),
            ],
          ),
          for (final task in data.$1)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.song.title),
                    Text(
                      '${{'queued': '等待下载', 'running': '下载中', 'failed': '下载失败', 'completed': '已完成'}[task.state]} · ${task.done} / ${task.total} 字节',
                    ),
                    if (task.state == 'running')
                      LinearProgressIndicator(
                        value: task.total > BigInt.zero
                            ? (task.done.toDouble() / task.total.toDouble())
                                  .clamp(0, 1)
                            : null,
                      ),
                    Wrap(
                      children: [
                        if (task.state == 'failed')
                          TextButton(
                            onPressed: () => perform(
                              context,
                              () =>
                                  api.downloadAction('retry', taskId: task.id),
                            ),
                            child: const Text('继续下载'),
                          ),
                        if (task.state == 'running' || task.state == 'queued')
                          TextButton(
                            onPressed: () => perform(
                              context,
                              () =>
                                  api.downloadAction('cancel', taskId: task.id),
                            ),
                            child: const Text('取消'),
                          ),
                        if (task.state == 'completed' || task.state == 'failed')
                          TextButton(
                            onPressed: () => perform(
                              context,
                              () => api.downloadAction(
                                'remove_task',
                                taskId: task.id,
                              ),
                            ),
                            child: const Text('移除任务'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('已下载')),
              TextButton(
                onPressed: () => perform(context, () async {
                  final songs = data.$2
                      .where(
                        (d) =>
                            d.song != null &&
                            !File(d.download.path).existsSync(),
                      )
                      .map((d) => d.song!)
                      .toList();
                  await api.downloadSelection(songs: songs);
                }),
                child: const Text('重新下载缺失文件'),
              ),
            ],
          ),
          if (data.$2.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有下载歌曲。打开歌曲菜单或在歌单中多选后，选择「下载」。'),
            ),
          for (final entry in data.$2)
            ListTile(
              title: Text(entry.song?.title ?? entry.download.songId),
              subtitle: Text(
                File(entry.download.path).existsSync()
                    ? entry.download.path
                    : '文件缺失 · 可重新下载',
              ),
              trailing: PopupMenuButton<String>(
                tooltip: '下载文件操作',
                onSelected: (action) => _fileAction(action, entry),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'play', child: Text('播放')),
                  const PopupMenuItem(value: 'retry', child: Text('重新下载')),
                  PopupMenuItem(
                    value: 'export',
                    child: Text(Platform.isAndroid ? '导出到系统音乐' : '另存为'),
                  ),
                  if (Platform.isAndroid)
                    const PopupMenuItem(value: 'save_as', child: Text('另存为')),
                  const PopupMenuItem(value: 'share', child: Text('分享')),
                  if (!Platform.isAndroid)
                    const PopupMenuItem(
                      value: 'locate',
                      child: Text('打开所在文件夹'),
                    ),
                  const PopupMenuItem(
                    value: 'remove_record',
                    child: Text('移除记录'),
                  ),
                  const PopupMenuItem(
                    value: 'delete_file',
                    child: Text('删除文件'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
