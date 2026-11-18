import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import 'navigation.dart';

class TasksBody extends ConsumerStatefulWidget {
  const TasksBody({super.key});
  @override
  ConsumerState<TasksBody> createState() => _TasksBodyState();
}

class _TasksBodyState extends ConsumerState<TasksBody> {
  StreamSubscription<String>? events;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    events = ref.read(coreApiProvider).changes.listen((kind) {
      if (mounted && (kind == 'tasks.changed' || kind == 'all.changed')) {
        setState(() => revision++);
      }
    });
  }

  @override
  void dispose() {
    events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(coreApiProvider);
    return AsyncFeature<List<Work>>(
      target: revision,
      retain: true,
      load: api.tasks,
      builder: (context, data, reload) => data.isEmpty
          ? const Center(child: Text('暂无后台操作'))
          : ListView(
              children: [
                for (final task in data.reversed)
                  ListTile(
                    title: Text(
                      {
                            'batch.add': '批量加入歌单',
                            'batch.remove': '批量移除',
                            'batch.download': '准备下载',
                            'now': '同步曲库',
                            'init': '初始化仓库',
                            'probe': '测试连接',
                            'resolve': '应用冲突选择',
                          }[task.action] ??
                          '更新同步设置',
                    ),
                    subtitle: Text(
                      '${{'running': '进行中', 'completed': '已完成', 'cancelled': '已取消', 'failed': '失败'}[task.state]} ${task.message}',
                    ),
                    trailing: task.state == 'running'
                        ? TextButton(
                            child: const Text('取消'),
                            onPressed: () =>
                                perform(context, () => api.cancelTask(task.id)),
                          )
                        : null,
                    onTap:
                        task.action.startsWith('batch.') &&
                            task.state != 'running'
                        ? () => openFeature(
                            context,
                            '批量操作结果',
                            BatchResultBody(id: task.id),
                          )
                        : null,
                  ),
              ],
            ),
    );
  }
}

class BatchResultBody extends ConsumerWidget {
  const BatchResultBody({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(coreApiProvider);
    return AsyncFeature<(Work, BatchResult)>(
      load: () => api.batchTask(id),
      builder: (context, data, reload) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '完成 ${data.$2.succeeded.length} · 跳过 ${data.$2.skipped.length} · 失败 ${data.$2.failed.length}',
          ),
          if (data.$2.failed.isNotEmpty)
            FilledButton(
              onPressed: () => perform(context, () async {
                final task = await api.retryBatch(id);
                if (context.mounted) {
                  await openFeature(context, '后台操作', const TasksBody());
                }
                await api.waitBatch(task.id);
              }),
              child: const Text('仅重试失败项'),
            ),
          for (final item in data.$2.failed)
            ListTile(title: Text(item.songId), subtitle: Text(item.error)),
        ],
      ),
    );
  }
}
