import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import 'navigation.dart';
import 'tasks_page.dart';

class SyncBody extends ConsumerStatefulWidget {
  const SyncBody({super.key});
  @override
  ConsumerState<SyncBody> createState() => _SyncBodyState();
}

class _SyncBodyState extends ConsumerState<SyncBody> {
  StreamSubscription<String>? events;
  int version = 0;
  @override
  void initState() {
    super.initState();
    events = ref.read(coreApiProvider).changes.listen((kind) {
      if (mounted &&
          (kind == 'sync.changed' ||
              kind == 'tasks.changed' ||
              kind == 'all.changed')) {
        setState(() => version++);
      }
    });
  }

  @override
  void dispose() {
    events?.cancel();
    super.dispose();
  }

  Future<void> _run(
    String action, {
    bool auto = false,
    bool accounts = false,
    String passphrase = '',
    String token = '',
  }) async {
    await perform(context, () async {
      await ref
          .read(coreApiProvider)
          .syncAction(
            action,
            auto: auto,
            accounts: accounts,
            passphrase: passphrase,
            token: token,
          );
    }, success: '已开始，可在此页查看结果');
    if (mounted) setState(() => version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(coreApiProvider);
    return AsyncFeature<(SyncStatus, List<Work>)>(
      target: version,
      retain: true,
      load: () async => (await api.syncStatus(), await api.tasks()),
      builder: (context, data, reload) {
        final status = data.$1;
        final syncTasks = data.$2
            .where((t) => !t.action.contains('.'))
            .toList();
        final busy = syncTasks.any((t) => t.state == 'running');
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ListTile(
              title: const Text('后台操作与批量结果'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openFeature(context, '后台操作', const TasksBody()),
            ),
            Text(
              status.configured ? '已连接的仓库' : '同步你的曲库',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (status.remote.isNotEmpty)
              SelectableText('${status.remote}\n分支 ${status.branch}'),
            const SizedBox(height: 16),
            Text('歌单、混合引用和排除项参与同步。文件夹、仅本机歌单与本地歌词绑定保留在本机。'),
            if (status.hasError)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('最近一次同步失败。请检查仓库地址和凭据后测试连接。'),
              ),
            if (status.syncAccounts && status.hasKeyIssue)
              const Text('登录态密钥不可用，请设置仓库口令或关闭登录态同步。'),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : () => _run('now'),
                  child: const Text('立即同步'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => _run('probe'),
                  child: const Text('测试连接'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await openFeature(
                            context,
                            '连接同步仓库',
                            SyncConfigure(status: status),
                          );
                          if (mounted) reload();
                        },
                  child: Text(status.configured ? '更换仓库' : '初始化／加入仓库'),
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('自动同步'),
              subtitle: const Text('修改后自动推送；同步冲突时暂停自动同步'),
              value: status.auto,
              onChanged: busy ? null : (v) => _run('auto', auto: v),
            ),
            SwitchListTile(
              title: const Text('同步登录态'),
              subtitle: const Text('每台设备默认关闭；开启后使用仓库口令加密'),
              value: status.syncAccounts,
              onChanged: busy ? null : (v) => _run('accounts', accounts: v),
            ),
            ListTile(
              title: const Text('HTTPS 访问令牌'),
              subtitle: const Text('仅保存到本设备'),
              onTap: busy
                  ? null
                  : () => perform(context, () async {
                      final value = await askText(
                        context,
                        '设置访问令牌',
                        secret: true,
                        hint: '留空清除',
                      );
                      if (value != null) await _run('token', token: value);
                    }),
            ),
            ListTile(
              title: const Text('设置／更换仓库口令'),
              onTap: busy
                  ? null
                  : () => perform(context, () async {
                      final value = await askText(
                        context,
                        '仓库口令',
                        secret: true,
                      );
                      if (value != null && value.isNotEmpty) {
                        await _run('passphrase', passphrase: value);
                      }
                    }),
            ),
            ListTile(
              title: const Text('忘记本机密钥'),
              onTap: busy
                  ? null
                  : () => perform(context, () async {
                      if (await confirmAction(
                        context,
                        '忘记本机密钥',
                        '移除本设备缓存的登录态解密密钥；歌单和音频文件保留。',
                      )) {
                        await _run('forget');
                      }
                    }),
            ),
            if (status.conflictTx.isNotEmpty)
              ListTile(
                title: Text('处理同步冲突（${status.conflicts} 项）'),
                subtitle: const Text('比较本地和远端版本，逐项选择'),
                trailing: const Icon(Icons.compare_arrows),
                onTap: () =>
                    openFeature(context, '同步冲突', const ConflictsBody()),
              ),
            ListTile(
              title: const Text('归档歌单'),
              subtitle: const Text('查看同步删除前保留的歌单副本'),
              trailing: const Icon(Icons.archive_outlined),
              onTap: () => openFeature(context, '归档歌单', const ArchivesBody()),
            ),
            if (status.lastSyncAt != null)
              Text('上次同步：${status.lastSyncAt!.toLocal()}'),
            const Divider(),
            Text('操作记录', style: Theme.of(context).textTheme.titleMedium),
            for (final task in syncTasks.reversed)
              ListTile(
                title: Text(
                  {
                        'now': '同步',
                        'probe': '连接测试',
                        'init': '初始化仓库',
                        'configure': '配置仓库',
                        'passphrase': '更新口令',
                        'resolve': '解决冲突',
                      }[task.action] ??
                      '更新同步设置',
                ),
                subtitle: Text(
                  '${{'running': '进行中', 'completed': '已完成', 'failed': '失败', 'cancelled': '已取消'}[task.state]}${task.message.isEmpty ? '' : ' · ${task.message}'}',
                ),
                trailing: task.state == 'running'
                    ? TextButton(
                        onPressed: () =>
                            perform(context, () => api.cancelTask(task.id)),
                        child: const Text('取消'),
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class SyncConfigure extends ConsumerStatefulWidget {
  const SyncConfigure({required this.status, super.key});
  final SyncStatus status;
  @override
  ConsumerState<SyncConfigure> createState() => _SyncConfigureState();
}

class _SyncConfigureState extends ConsumerState<SyncConfigure> {
  late final remote = TextEditingController(text: widget.status.remote);
  late final branch = TextEditingController(
    text: widget.status.branch.isEmpty ? 'main' : widget.status.branch,
  );
  final password = TextEditingController();
  bool initialize = false;
  bool busy = false;
  @override
  void dispose() {
    remote.dispose();
    branch.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      TextField(
        controller: remote,
        decoration: const InputDecoration(
          labelText: '仓库地址',
          hintText: 'SSH 或 HTTPS Git 地址',
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: branch,
        decoration: const InputDecoration(labelText: '分支'),
      ),
      SwitchListTile(
        title: const Text('初始化空仓库'),
        subtitle: const Text('已有零拍仓库请关闭此选项，加入后手动同步'),
        value: initialize,
        onChanged: busy ? null : (v) => setState(() => initialize = v),
      ),
      if (initialize)
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: '登录态加密口令（可留空）'),
        ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: busy
            ? null
            : () => perform(context, () async {
                setState(() => busy = true);
                try {
                  await ref
                      .read(coreApiProvider)
                      .syncAction(
                        initialize ? 'init' : 'configure',
                        remote: remote.text.trim(),
                        branch: branch.text.trim(),
                        passphrase: password.text,
                      );
                  if (context.mounted) Navigator.pop(context);
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              }),
        child: Text(busy ? '提交中' : '连接仓库'),
      ),
    ],
  );
}

class ConflictsBody extends ConsumerWidget {
  const ConflictsBody({super.key});
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => AsyncFeature<(SyncConflictList, Map<String, String>)>(
    load: () async {
      final api = ref.read(coreApiProvider);
      final conflicts = await api.syncConflicts();
      return (conflicts, await api.conflictChoices(conflicts.txId));
    },
    builder: (context, value, reload) {
      final data = value.$1;
      return Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                for (final e in data.entities)
                  ListTile(
                    title: Text(e.title),
                    subtitle: Text(
                      "${e.summary}\n${{'local': '已选本地', 'remote': '已选远端', 'both': '已选保留两者'}[value.$2[e.entity]] ?? '尚未选择'}",
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await openFeature(
                        context,
                        '比较版本',
                        ConflictCompare(txId: data.txId, entity: e),
                      );
                      if (context.mounted) reload();
                    },
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: () => perform(context, () async {
                  await ref
                      .read(coreApiProvider)
                      .syncAction('resolve', txId: data.txId);
                  if (context.mounted) Navigator.pop(context);
                }),
                child: const Text('应用全部选择'),
              ),
              TextButton(
                onPressed: () => perform(context, () async {
                  if (await confirmAction(
                    context,
                    '放弃本次同步事务',
                    '保留本地曲库，归档冲突记录；下次同步会重新比较。',
                  )) {
                    await ref
                        .read(coreApiProvider)
                        .syncAction('discard', txId: data.txId);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
                child: const Text('放弃事务'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class ConflictCompare extends ConsumerWidget {
  const ConflictCompare({required this.txId, required this.entity, super.key});
  final String txId;
  final SyncConflict entity;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncFeature<(String, String)>(
        load: () async {
          final api = ref.read(coreApiProvider);
          return (
            await api.conflictVersion(txId, entity.index, 'local'),
            await api.conflictVersion(txId, entity.index, 'remote'),
          );
        },
        builder: (context, data, reload) => Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, size) {
                  final panels = [
                    for (final pair in [('本地', data.$1), ('远端', data.$2)])
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pair.$1,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              SelectableText(
                                pair.$2.isEmpty ? '此版本已删除' : pair.$2,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ];
                  return size.maxWidth < 650
                      ? Column(children: panels)
                      : Row(children: panels);
                },
              ),
            ),
            Wrap(
              children: [
                for (final choice in {
                  'local': '保留本地',
                  'remote': '使用远端',
                  if (entity.both) 'both': '保留两者',
                }.entries)
                  TextButton(
                    onPressed: () => perform(context, () async {
                      final api = ref.read(coreApiProvider);
                      final task = await api.syncAction(
                        'choice',
                        txId: txId,
                        entity: entity.entity,
                        choice: choice.key,
                      );
                      await api.waitTask(task.id);
                      if (context.mounted) Navigator.pop(context);
                    }),
                    child: Text(choice.value),
                  ),
              ],
            ),
          ],
        ),
      );
}

class ArchivesBody extends ConsumerWidget {
  const ArchivesBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(coreApiProvider);
    return AsyncFeature<List<Archive>>(
      load: api.syncArchives,
      builder: (context, data, reload) => data.isEmpty
          ? const Center(child: Text('暂无归档歌单'))
          : ListView(
              children: [
                for (final item in data.reversed)
                  ListTile(
                    title: Text(item.title),
                    subtitle: Text(item.name),
                    onTap: () => openFeature(
                      context,
                      item.title,
                      AsyncFeature<String>(
                        load: () => api.syncArchive(item.name),
                        builder: (context, text, reload) =>
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: SelectableText(text),
                            ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
