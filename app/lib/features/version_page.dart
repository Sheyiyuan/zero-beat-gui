import 'dart:async';

import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/chrome.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import 'developer_log_window.dart';
import 'developer_mode.dart';
import 'session.dart';

/// Version and local diagnostics only; never displays session credentials.
class VersionBody extends ConsumerStatefulWidget {
  const VersionBody({super.key});

  @override
  ConsumerState<VersionBody> createState() => _VersionBodyState();
}

class _VersionBodyState extends ConsumerState<VersionBody> {
  static const _tapWindow = Duration(seconds: 2);
  static const _requiredTaps = 5;

  Timer? _tapReset;
  int _taps = 0;

  @override
  void dispose() {
    _tapReset?.cancel();
    super.dispose();
  }

  void _handleCoreTap() {
    if (ref.read(developerModeProvider)) return;
    _tapReset?.cancel();
    _taps++;
    if (_taps >= _requiredTaps) {
      _taps = 0;
      _tapReset = null;
      unawaited(_enterDeveloperMode());
      return;
    }
    _tapReset = Timer(_tapWindow, () => _taps = 0);
  }

  Future<void> _enterDeveloperMode() async {
    final log = ref.read(developerLogProvider);
    await ref.read(developerModeProvider.notifier).setEnabled(true);
    if (!mounted) return;
    log.info('版本', '已进入开发者模式');
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('已进入开发者模式')));
  }

  Future<void> _exitDeveloperMode() async {
    final log = ref.read(developerLogProvider);
    closeDeveloperLogWindow();
    await ref.read(developerModeProvider.notifier).setEnabled(false);
    if (!mounted) return;
    log.info('版本', '已退出开发者模式');
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('已退出开发者模式')));
  }

  @override
  Widget build(BuildContext context) {
    final hello = ref.watch(helloProvider);
    final result = hello.result;
    final developer = ref.watch(developerModeProvider);
    final platform = ref.watch(platformLabelProvider);
    final connected = developer ? ref.watch(connectionProvider) : false;
    final appVersion = result?.guiVersion ?? '';
    final dataDir = result?.dataDir ?? '';
    final capabilities = result == null
        ? '暂不可用'
        : result.capabilities.isEmpty
        ? '核心未报告能力'
        : result.capabilities.join('、');
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/appicon.png',
                        width: 64,
                        height: 64,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '零拍',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              appVersion.isEmpty ? '暂未获取版本号' : '版本 $appVersion',
                              key: const Key('version-gui'),
                              style: TextStyle(color: context.zero.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                if (result == null) ...[
                  Text(
                    hello.error.isEmpty ? '版本信息暂不可用' : '读取版本信息失败',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hello.error.isEmpty ? '连接恢复后，请重新打开此页。' : hello.error,
                    style: TextStyle(color: context.zero.muted, height: 1.4),
                  ),
                ] else ...[
                  Text('诊断信息', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '反馈问题时，可提供以下信息。',
                    style: TextStyle(color: context.zero.muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  InsetGroup(
                    children: [
                      _InfoTile(
                        key: const Key('version-core'),
                        icon: AppIcons.memory,
                        label: '核心版本',
                        value: result.coreVersion,
                        onTap: _handleCoreTap,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Text('数据目录')),
                                if (dataDir.isNotEmpty)
                                  IconButton(
                                    tooltip: '复制数据目录',
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: dataDir),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('数据目录已复制'),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(AppIcons.copy),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              dataDir.isEmpty ? '暂未获取数据目录' : dataDir,
                              key: const Key('version-data-dir'),
                              style: TextStyle(
                                color: context.zero.muted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (developer) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(
                        AppIcons.developer,
                        size: 18,
                        color: context.zero.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '开发者模式',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '以下信息仅保存在本机，不会上传。',
                    style: TextStyle(color: context.zero.muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  InsetGroup(
                    children: [
                      _InfoTile(
                        key: const Key('version-dev-api'),
                        icon: AppIcons.api,
                        label: 'API 版本',
                        value: result == null ? '暂不可用' : '${result.api}',
                        emptyText: '暂不可用',
                      ),
                      _InfoTile(
                        key: const Key('version-dev-repo'),
                        icon: AppIcons.sources,
                        label: '仓库版本',
                        value: result == null ? '暂不可用' : '${result.repo}',
                        emptyText: '暂不可用',
                      ),
                      _InfoTile(
                        key: const Key('version-dev-capabilities'),
                        icon: AppIcons.plugin,
                        label: '能力列表',
                        value: capabilities,
                        emptyText: '暂不可用',
                      ),
                      _InfoTile(
                        key: const Key('version-dev-platform'),
                        icon: AppIcons.devices,
                        label: '平台 / 目标',
                        value: platform,
                        emptyText: '暂不可用',
                      ),
                      _InfoTile(
                        key: const Key('version-dev-connection'),
                        icon: AppIcons.cast,
                        label: '连接状态',
                        value: connected ? '已连接' : '已断开',
                        emptyText: '暂不可用',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InsetGroup(
                    children: [
                      ListTile(
                        key: const Key('version-runtime-log'),
                        leading: Icon(
                          AppIcons.terminal,
                          color: context.zero.muted,
                        ),
                        title: const Text('运行日志'),
                        subtitle: const Text('查看、复制或导出应用运行日志'),
                        trailing: const Icon(AppIcons.chevronRight, size: 18),
                        onTap: () {
                          if (!showDeveloperLogWindow(context)) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(content: Text('无法打开悬浮日志窗')),
                            );
                          }
                        },
                      ),
                      ListTile(
                        key: const Key('version-exit-developer'),
                        leading: Icon(
                          AppIcons.logout,
                          color: context.zero.muted,
                        ),
                        title: const Text('退出开发者模式'),
                        subtitle: const Text('隐藏诊断信息并关闭运行日志'),
                        trailing: const Icon(AppIcons.chevronRight, size: 18),
                        onTap: () => unawaited(_exitDeveloperMode()),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.emptyText = '暂未获取版本号',
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String emptyText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: context.zero.muted),
      title: Text(label),
      subtitle: Text(value.isEmpty ? emptyText : value),
      onTap: onTap,
    );
  }
}
