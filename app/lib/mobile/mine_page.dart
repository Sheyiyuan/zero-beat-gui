import '../app/chrome.dart';
import '../features/downloads_page.dart';
import '../features/sync_page.dart';
import '../features/navigation.dart';
import '../features/accounts_page.dart';
import '../features/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/theme.dart';
import '../features/session.dart';
import '../shared/playback.dart';
import '../shared/player_bar.dart';

class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(connectionProvider);
    final hello = ref.watch(helloProvider);
    final notice = ref.watch(noticeProvider);
    final playerNotice = ref.watch(playerProvider).notice;
    final result = hello.result;
    final accounts = result?.accounts.entries.toList() ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const PageHeader(title: '我的', subtitle: '账号、下载、同步和这台设备上的偏好。'),
        InsetGroup(
          children: [
            ListTile(
              title: const Text('下载管理'),
              leading: const Icon(Icons.download_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openFeature(context, '下载管理', const DownloadsBody()),
            ),
            ListTile(
              title: const Text('仓库同步'),
              leading: const Icon(Icons.sync),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openFeature(context, '仓库同步', const SyncBody()),
            ),
            ListTile(
              title: const Text('账号与登录'),
              subtitle: const Text('手机可在官方页面直接登录'),
              leading: const Icon(Icons.account_circle_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openFeature(context, '账号', const AccountsBody()),
            ),
            ListTile(
              title: const Text('设置'),
              leading: const Icon(Icons.settings_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openFeature(context, '设置', const SettingsBody()),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(connected ? '已连接' : '未连接', key: Key('connection-status')),
        SizedBox(height: 12),
        if (hello.error.isNotEmpty)
          Text(hello.error, style: TextStyle(color: context.zero.danger)),
        for (final entry in accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_accountLine(entry.key, entry.value)),
          ),
        if (accounts.isEmpty && result != null) Text('未登录，可以匿名使用'),
        if (result != null) ...[
          SizedBox(height: 8),
          Text('核心 ${result.coreVersion}'),
          SizedBox(height: 4),
          Text('界面 ${result.guiVersion}'),
          SizedBox(height: 4),
          Text('能力 ${result.capabilities.join('、')}'),
        ],
        if (notice.isNotEmpty) ...[
          SizedBox(height: 12),
          Text(
            notice,
            key: Key('core-notice'),
            style: TextStyle(color: context.zero.warning),
          ),
        ],
        if (playerNotice.isNotEmpty) ...[
          SizedBox(height: 8),
          Text(playerNotice, style: TextStyle(color: context.zero.warning)),
        ],
        SizedBox(height: 8),
        PlayerNotices(),
      ],
    );
  }

  String _accountLine(String id, AccountBrief account) {
    final source = accountLabel(id);
    if (account.notice.isNotEmpty) return '$source：${account.notice}';
    if (!account.loggedIn) return '$source：未登录，可以匿名使用';
    if (account.name.isEmpty) return '$source：已登录';
    return '$source：已登录，${account.name}';
  }
}
