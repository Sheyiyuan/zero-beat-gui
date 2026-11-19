import 'dart:async';
import 'package:flutter/material.dart';
import '../app/chrome.dart';
import '../app/icons.dart';
import '../app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import '../shared/refreshable.dart';
import 'navigation.dart';
import 'tasks_page.dart';

Future<void> _syncPerform(
  BuildContext context,
  Future<void> Function() operation, {
  String? success,
}) => perform(context, operation, source: '同步', success: success);

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
    await _syncPerform(context, () async {
      await ref
          .read(coreApiProvider)
          .syncAction(
            action,
            auto: auto,
            accounts: accounts,
            passphrase: passphrase,
            token: token,
          );
    }, success: '已开始，请在操作记录中查看结果');
    if (mounted) setState(() => version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(coreApiProvider);
    return RefreshableFeature<(SyncStatus, List<Work>)>(
      target: version,
      retain: true,
      load: () async => (await api.syncStatus(), await api.tasks()),
      builder: (context, data, reload) {
        final status = data.$1;
        final syncTasks = data.$2
            .where((t) => !t.action.contains('.'))
            .toList();
        final busy = syncTasks.any((t) => t.state == 'running');
        return RefreshableListView(
          key: const Key('sync-refresh'),
          onRefresh: reload,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _SyncLocationCard(
              status: status,
              busy: busy,
              onSync: () => _run('now'),
              onProbe: () => _run('probe'),
              onConfigure: () async {
                await openFeature(
                  context,
                  '设置同步位置',
                  SyncConfigure(status: status),
                );
                if (mounted) reload();
              },
            ),
            const SizedBox(height: 24),
            const GroupLabel('同步选项'),
            InsetGroup(
              dividerIndent: 16,
              children: [
                SwitchListTile(
                  title: const Text('自动同步'),
                  subtitle: const Text('修改歌单后自动同步；内容冲突时暂停，等待你选择保留的版本。'),
                  value: status.auto,
                  onChanged: busy ? null : (v) => _run('auto', auto: v),
                ),
                SwitchListTile(
                  title: const Text('同步登录信息'),
                  subtitle: const Text(
                    '使用同步口令加密平台登录信息，供其他设备使用。每台设备默认关闭，需单独开启。',
                  ),
                  value: status.syncAccounts,
                  onChanged: busy ? null : (v) => _run('accounts', accounts: v),
                ),
                ListTile(
                  title: const Text('HTTPS 访问令牌'),
                  subtitle: const Text('用于访问 HTTPS 同步地址，仅保存在本机。'),
                  trailing: const Icon(AppIcons.chevronRight, size: 18),
                  onTap: busy
                      ? null
                      : () => _syncPerform(context, () async {
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
                  title: const Text('设置同步加密口令'),
                  trailing: const Icon(AppIcons.chevronRight, size: 18),
                  onTap: busy
                      ? null
                      : () => _syncPerform(context, () async {
                          final value = await askText(
                            context,
                            '同步加密口令',
                            secret: true,
                          );
                          if (value != null && value.isNotEmpty) {
                            await _run('passphrase', passphrase: value);
                          }
                        }),
                ),
                ListTile(
                  title: Text(
                    '清除本机解密密钥',
                    style: TextStyle(color: context.zero.danger),
                  ),
                  onTap: busy
                      ? null
                      : () => _syncPerform(context, () async {
                          if (await confirmAction(
                            context,
                            '清除本机解密密钥',
                            '清除后，需要重新输入同步加密口令才能读取同步的登录信息。歌单和音频文件保留。',
                          )) {
                            await _run('forget');
                          }
                        }),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const GroupLabel('记录'),
            InsetGroup(
              children: [
                if (status.conflictTx.isNotEmpty)
                  ListTile(
                    leading: Icon(
                      AppIcons.compare,
                      color: context.zero.warning,
                    ),
                    title: Text('处理同步冲突（${status.conflicts} 项）'),
                    subtitle: const Text('比较本机与同步端的内容，逐项选择保留哪个。'),
                    trailing: const Icon(AppIcons.chevronRight, size: 18),
                    onTap: () =>
                        openFeature(context, '同步冲突', const ConflictsBody()),
                  ),
                ListTile(
                  leading: const Icon(AppIcons.archive),
                  title: const Text('归档歌单'),
                  subtitle: const Text('查看同步删除前保留的歌单副本'),
                  trailing: const Icon(AppIcons.chevronRight, size: 18),
                  onTap: () =>
                      openFeature(context, '归档歌单', const ArchivesBody()),
                ),
                ListTile(
                  leading: const Icon(AppIcons.select),
                  title: const Text('任务与操作结果'),
                  trailing: const Icon(AppIcons.chevronRight, size: 18),
                  onTap: () =>
                      openFeature(context, '任务与操作结果', const TasksBody()),
                ),
              ],
            ),
            if (syncTasks.isNotEmpty) ...[
              const SizedBox(height: 24),
              const GroupLabel('操作记录'),
              InsetGroup(
                dividerIndent: 16,
                children: [
                  for (final task in syncTasks.reversed)
                    ListTile(
                      title: Text(
                        {
                              'now': '同步',
                              'probe': '连接测试',
                              'init': '启用新同步仓库',
                              'configure': '设置同步位置',
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
                              onPressed: () => _syncPerform(
                                context,
                                () => api.cancelTask(task.id),
                              ),
                              child: const Text('取消'),
                            )
                          : null,
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SyncLocationCard extends StatelessWidget {
  const _SyncLocationCard({
    required this.status,
    required this.busy,
    required this.onSync,
    required this.onProbe,
    required this.onConfigure,
  });

  final SyncStatus status;
  final bool busy;
  final VoidCallback onSync;
  final VoidCallback onProbe;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: context.zero.muted,
      fontSize: 13,
      height: 1.45,
    );
    return Material(
      color: context.zero.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.sync, size: 18, color: context.zero.accent),
                const SizedBox(width: 8),
                Text(
                  status.configured ? '同步位置' : '同步曲库',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (status.remote.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                status.remote,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                status.lastSyncAt == null
                    ? '分支 ${status.branch}'
                    : '分支 ${status.branch} · 上次同步 ${_formatTime(status.lastSyncAt!.toLocal())}',
                style: muted,
              ),
            ],
            const SizedBox(height: 10),
            Text('同步歌单、混合歌单及隐藏歌曲的设置。文件夹、仅本机歌单和本地歌词设置仅保留在本机。', style: muted),
            if (status.hasError) ...[
              const SizedBox(height: 8),
              Text(
                '上次同步失败。请检查同步地址和访问权限，再点「测试连接」。',
                style: TextStyle(color: context.zero.danger, fontSize: 13),
              ),
            ],
            if (status.syncAccounts && status.hasKeyIssue) ...[
              const SizedBox(height: 8),
              Text(
                '无法解密登录信息，请设置同步加密口令，或关闭「同步登录信息」。',
                style: TextStyle(color: context.zero.warning, fontSize: 13),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : onSync,
                  child: const Text('立即同步'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onProbe,
                  child: const Text('测试连接'),
                ),
                TextButton(
                  onPressed: busy ? null : onConfigure,
                  child: Text(status.configured ? '更换同步位置' : '设置同步'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
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
      const Text('使用 Git 仓库存放同步数据。请填写你有读写权限的仓库地址。'),
      const SizedBox(height: 16),
      TextField(
        controller: remote,
        decoration: const InputDecoration(
          labelText: '同步仓库地址',
          hintText: 'SSH 或 HTTPS Git 地址',
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: branch,
        decoration: const InputDecoration(labelText: '分支'),
      ),
      SwitchListTile(
        title: const Text('首次使用空仓库'),
        subtitle: const Text('仅用于尚无零拍数据的仓库。已有数据时请关闭此项，连接后点「立即同步」。'),
        value: initialize,
        onChanged: busy ? null : (v) => setState(() => initialize = v),
      ),
      if (initialize)
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: '登录信息加密口令（可留空）'),
        ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: busy
            ? null
            : () => _syncPerform(context, () async {
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
        child: Text(busy ? '连接中' : '连接'),
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
  ) => RefreshableFeature<(SyncConflictList, Map<String, String>)>(
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
            child: RefreshableListView(
              key: const Key('conflicts-refresh'),
              onRefresh: reload,
              children: [
                for (final e in data.entities)
                  ListTile(
                    title: Text(e.title),
                    subtitle: Text(
                      "${e.summary}\n${{'local': '已选本机版本', 'remote': '已选同步端版本', 'both': '已选保留两个版本'}[value.$2[e.entity]] ?? '尚未选择'}",
                    ),
                    trailing: const Icon(AppIcons.chevronRight, size: 18),
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
                onPressed: () => _syncPerform(context, () async {
                  await ref
                      .read(coreApiProvider)
                      .syncAction('resolve', txId: data.txId);
                  if (context.mounted) Navigator.pop(context);
                }),
                child: const Text('应用全部选择'),
              ),
              TextButton(
                onPressed: () => _syncPerform(context, () async {
                  if (await confirmAction(
                    context,
                    '放弃本次同步',
                    '本机曲库和冲突记录会保留，下次同步时重新比较。',
                  )) {
                    await ref
                        .read(coreApiProvider)
                        .syncAction('discard', txId: data.txId);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
                child: const Text('放弃本次同步'),
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
                    for (final pair in [('本机', data.$1), ('同步端', data.$2)])
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
                                pair.$2.isEmpty ? '此处已删除这项内容' : pair.$2,
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
                  'local': '保留本机版本',
                  'remote': '使用同步端版本',
                  if (entity.both) 'both': '保留两个版本',
                }.entries)
                  TextButton(
                    onPressed: () => _syncPerform(context, () async {
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
    return RefreshableFeature<List<Archive>>(
      load: api.syncArchives,
      builder: (context, data, reload) => RefreshableListView(
        key: const Key('archives-refresh'),
        onRefresh: reload,
        children: [
          if (data.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂无归档歌单')),
            ),
          for (final item in data.reversed)
            ListTile(
              title: Text(item.title),
              subtitle: Text(item.name),
              onTap: () => openFeature(
                context,
                item.title,
                AsyncFeature<String>(
                  load: () => api.syncArchive(item.name),
                  builder: (context, text, reload) => SingleChildScrollView(
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
