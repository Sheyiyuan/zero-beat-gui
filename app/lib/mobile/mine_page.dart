import 'dart:async';

import '../app/chrome.dart';
import '../app/providers.dart';
import '../features/downloads_page.dart';
import '../features/sync_page.dart';
import '../features/navigation.dart';
import '../features/accounts_page.dart';
import '../features/settings_page.dart';
import '../features/version_page.dart';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/theme.dart';
import '../features/session.dart';
import '../shared/account_status.dart';
import '../shared/playback.dart';
import '../shared/player_bar.dart';

class MinePage extends ConsumerStatefulWidget {
  const MinePage({super.key});

  @override
  ConsumerState<MinePage> createState() => _MinePageState();
}

class _MinePageState extends ConsumerState<MinePage> {
  StreamSubscription<String>? _events;
  List<SourceInfo>? _sources;
  final Map<String, bool> _seenLoggedIn = {};
  SyncStatus? _syncStatus;
  Object? _syncError;
  List<DownloadEntry>? _downloads;
  List<DownloadTask>? _downloadTasks;
  Object? _downloadError;
  bool _featuresSupported = true;
  String _dismissedPlayerNotice = '';

  @override
  void initState() {
    super.initState();
    final api = ref.read(coreApiProvider);
    _featuresSupported = api is CoreFeatureTransport;
    final hello = ref.read(helloProvider).result;
    for (final entry
        in hello?.accounts.entries ??
            const <MapEntry<String, AccountBrief>>[]) {
      _seenLoggedIn[entry.key] = entry.value.loggedIn;
    }
    _events = api.changes.listen((kind) {
      switch (kind) {
        case 'auth.changed':
          unawaited(_loadAccounts(refresh: false));
        case 'sync.changed':
          unawaited(_loadSync());
        case 'download.changed':
          unawaited(_loadDownloads());
        case 'all.changed':
          unawaited(_loadAccounts(refresh: false));
          unawaited(_loadSync());
          unawaited(_loadDownloads());
      }
    });
    unawaited(_loadAccounts(refresh: true));
    unawaited(_loadSync());
    unawaited(_loadDownloads());
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<Object?> _loadAccounts({required bool refresh}) async {
    final api = ref.read(coreApiProvider);
    // Fake/older cores may not expose the feature transport; keep using the
    // hello snapshot in that case.
    if (api is! CoreFeatureTransport) return null;
    try {
      final sources = await api.accounts(refresh: refresh);
      if (!mounted) return null;
      final accounts = sources
          .where((source) => source.capabilities.names.contains('account'))
          .toList();
      for (final source in accounts) {
        if (source.user.loggedIn) _seenLoggedIn[source.id.value] = true;
      }
      setState(() => _sources = accounts);
      return null;
    } catch (error) {
      // A stale hello snapshot is still better than hiding the whole page.
      return error;
    }
  }

  Future<Object?> _loadSync() async {
    final api = ref.read(coreApiProvider);
    if (api is! CoreFeatureTransport) return null;
    try {
      final status = await api.syncStatus();
      if (!mounted) return null;
      setState(() {
        _syncStatus = status;
        _syncError = null;
      });
      return null;
    } catch (error) {
      if (!mounted) return null;
      setState(() => _syncError = error);
      return error;
    }
  }

  Future<Object?> _loadDownloads() async {
    final api = ref.read(coreApiProvider);
    if (api is! CoreFeatureTransport) return null;
    try {
      final tasks = await api.downloadTasks();
      final downloads = await api.downloads();
      if (!mounted) return null;
      setState(() {
        _downloadTasks = tasks;
        _downloads = downloads;
        _downloadError = null;
      });
      return null;
    } catch (error) {
      if (!mounted) return null;
      setState(() => _downloadError = error);
      return error;
    }
  }

  Future<void> _refresh() async {
    // The banners are events that already happened. Refresh asks for the
    // current account, sync and download status, so the old text goes away.
    // The player bar keeps the live playback notice.
    ref.read(noticeProvider.notifier).clear();
    final playerNotice = ref.read(playerProvider).notice;
    if (mounted) setState(() => _dismissedPlayerNotice = playerNotice);
    final results = await Future.wait<Object?>([
      _loadAccounts(refresh: true),
      _loadSync(),
      _loadDownloads(),
    ]);
    final errors = results.whereType<Object>().toList();
    if (errors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失败：${errorText(errors.first)}')),
      );
    }
  }

  String _accountSummary(List<MapEntry<String, AccountBrief>> fallback) {
    final live = _sources;
    if (live != null) {
      if (live.isEmpty) return '未登录，仍可播放公开内容';
      return live
          .map((source) {
            final label = accountDisplayName(source.id.value, source.name);
            final status = accountCompactStatus(
              loggedIn: source.user.loggedIn,
              expired: _seenLoggedIn[source.id.value] == true,
            );
            return '$label $status';
          })
          .join(' · ');
    }
    if (fallback.isEmpty) return '未登录，仍可播放公开内容';
    return fallback
        .map((entry) {
          final label = accountDisplayName(entry.key, entry.value.name);
          final status = entry.value.loggedIn ? '已登录' : '未登录';
          return '$label $status';
        })
        .join(' · ');
  }

  String get _syncSummary {
    if (!_featuresSupported) return '当前版本暂不支持查看同步状态';
    final status = _syncStatus;
    if (status == null) {
      return _syncError == null ? '正在读取同步状态' : '无法读取同步状态，请下拉重试';
    }
    final parts = <String>[status.auto ? '自动同步已开启' : '自动同步已关闭'];
    if (!status.configured) {
      parts.add('尚未设置同步');
    } else if (status.hasError) {
      parts.add('最近同步失败');
    } else if (status.hasKeyIssue) {
      parts.add('无法解密登录信息');
    } else if (status.conflicts > 0) {
      parts.add('${status.conflicts} 项冲突');
    } else {
      parts.add('状态正常');
    }
    return parts.join(' · ');
  }

  String get _downloadSummary {
    if (!_featuresSupported) return '当前版本暂不支持查看下载状态';
    final downloads = _downloads;
    final tasks = _downloadTasks;
    if (downloads == null || tasks == null) {
      return _downloadError == null ? '正在读取下载状态' : '无法读取下载状态，请下拉重试';
    }
    final failed = tasks
        .where((task) => task.state == 'failed' || task.failed)
        .length;
    final count = '已下载 ${downloads.length} 首';
    return failed == 0 ? count : '$count · $failed 首下载失败';
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectionProvider);
    final hello = ref.watch(helloProvider);
    final notice = ref.watch(noticeProvider);
    final result = hello.result;
    final fallback = result?.accounts.entries.toList() ?? const [];
    final accountSummary = _accountSummary(fallback);
    final syncSummary = _syncSummary;
    final downloadSummary = _downloadSummary;
    return RefreshIndicator(
      key: const Key('mine-refresh'),
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const PageHeader(title: '我的', subtitle: '账号、下载、同步与本机偏好。'),
          InsetGroup(
            children: [
              ListTile(
                key: const Key('mine-download-entry'),
                title: const Text('下载管理'),
                subtitle: Text(
                  downloadSummary,
                  key: const Key('mine-download-status'),
                ),
                leading: const Icon(AppIcons.download),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: () =>
                    openFeature(context, '下载管理', const DownloadsBody()),
              ),
              ListTile(
                key: const Key('mine-sync-entry'),
                title: const Text('曲库同步'),
                subtitle: Text(syncSummary, key: const Key('mine-sync-status')),
                leading: const Icon(AppIcons.sync),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: () => openFeature(context, '曲库同步', const SyncBody()),
              ),
              ListTile(
                key: const Key('mine-account-entry'),
                title: const Text('账号与登录'),
                subtitle: Text(
                  accountSummary,
                  key: const Key('mine-account-status'),
                ),
                leading: const Icon(AppIcons.account),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: () => openFeature(context, '账号', const AccountsBody()),
              ),
              ListTile(
                title: const Text('设置'),
                leading: const Icon(AppIcons.settings),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: () => openFeature(context, '设置', const SettingsBody()),
              ),
              ListTile(
                key: const Key('mine-version-entry'),
                title: const Text('版本信息'),
                subtitle: const Text('应用版本与诊断信息'),
                leading: const Icon(AppIcons.info),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: () => openFeature(context, '版本信息', const VersionBody()),
              ),
            ],
          ),
          if (!connected) ...[
            const SizedBox(height: 20),
            Text(
              '与核心的连接已断开，正在自动重连',
              key: const Key('connection-status'),
              style: TextStyle(color: context.zero.warning),
            ),
            const SizedBox(height: 12),
          ],
          if (hello.error.isNotEmpty)
            Text(hello.error, style: TextStyle(color: context.zero.danger)),
          if (notice.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              notice,
              key: const Key('core-notice'),
              style: TextStyle(color: context.zero.warning),
            ),
          ],
          const SizedBox(height: 8),
          PlayerNotices(suppressNotice: _dismissedPlayerNotice),
        ],
      ),
    );
  }
}
