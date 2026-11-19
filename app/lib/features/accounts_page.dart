import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/chrome.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../core/developer_log.dart';
import '../shared/account_status.dart';
import '../shared/song_tile.dart';
import '../shared/playback.dart';
import '../shared/refreshable.dart';
import 'navigation.dart';
import 'session.dart';
import 'web_login_page.dart';
import 'web_login_policy.dart';

class AccountsBody extends ConsumerStatefulWidget {
  const AccountsBody({super.key});
  @override
  ConsumerState<AccountsBody> createState() => _AccountsBodyState();
}

class _AccountsBodyState extends ConsumerState<AccountsBody> {
  StreamSubscription<String>? events;
  final Map<String, bool> _seenLoggedIn = {};
  bool _refreshNext = false;
  int version = 0;
  @override
  void initState() {
    super.initState();
    final hello = ref.read(helloProvider).result;
    for (final entry
        in hello?.accounts.entries ??
            const <MapEntry<String, AccountBrief>>[]) {
      _seenLoggedIn[entry.key] = entry.value.loggedIn;
    }
    events = ref.read(coreApiProvider).changes.listen((kind) {
      if (mounted && (kind == 'auth.changed' || kind == 'all.changed')) {
        setState(() => version++);
      }
    });
  }

  @override
  void dispose() {
    events?.cancel();
    super.dispose();
  }

  Future<List<SourceInfo>> _load() async {
    final refresh = _refreshNext;
    _refreshNext = false;
    final sources = await ref.read(coreApiProvider).accounts(refresh: refresh);
    for (final source in sources) {
      if (source.user.loggedIn) _seenLoggedIn[source.id.value] = true;
    }
    return sources
        .where((source) => source.capabilities.names.contains('account'))
        .toList();
  }

  @override
  Widget build(BuildContext context) => RefreshableFeature<List<SourceInfo>>(
    target: version,
    retain: true,
    load: _load,
    builder: (context, data, reload) => RefreshableListView(
      key: const Key('accounts-refresh'),
      onRefresh: () {
        _refreshNext = true;
        return reload();
      },
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text('登录后可导入平台歌单、查看收藏和评论；未登录仍可播放公开内容。'),
        ),
        const SizedBox(height: 8),
        InsetGroup(
          children: [
            for (final s in data)
              ListTile(
                leading: PlatformSourceIcon(source: s.id, size: 36),
                title: Text(accountDisplayName(s.id.value, s.name)),
                subtitle: Text(
                  accountLoginStatus(
                    loggedIn: s.user.loggedIn,
                    name: s.user.name,
                    expired:
                        !s.user.loggedIn && _seenLoggedIn[s.id.value] == true,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => perform(context, () async {
                    final api = ref.read(coreApiProvider);
                    final title = accountDisplayName(s.id.value, s.name);
                    if (s.user.loggedIn) {
                      if (!await confirmAction(
                        context,
                        '退出$title账号',
                        '该平台的导入歌单会停止同步，已缓存内容和混合歌单保留。',
                      )) {
                        return;
                      }
                      await api.logout(s.id.value);
                    } else {
                      await openFeature(
                        context,
                        '登录 $title',
                        LoginOptions(source: s.id.value, title: title),
                      );
                    }
                    if (context.mounted) reload();
                  }),
                  child: Text(s.user.loggedIn ? '退出登录' : '登录'),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class LoginOptions extends StatelessWidget {
  const LoginOptions({
    required this.source,
    required this.title,
    this.sameDeviceFirst,
    this.cookies,
    this.viewport,
    super.key,
  });

  final String source;
  final String title;
  final bool? sameDeviceFirst;
  final WebCookieReader? cookies;
  final Widget? viewport;

  @override
  Widget build(BuildContext context) {
    final onDevice =
        sameDeviceFirst ??
        sameDeviceLoginFirst(
          android: defaultTargetPlatform == TargetPlatform.android,
        );
    final device = _LoginChoice(
      key: const Key('login-on-device'),
      icon: AppIcons.deviceLogin,
      title: '在本机登录',
      detail: '在$title官方页面登录，无需另一台设备。',
      filled: onDevice,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => WebLoginPage(
              source: source,
              title: title,
              cookies: cookies,
              viewport: viewport,
            ),
          ),
        );
      },
    );
    final qr = _LoginChoice(
      key: const Key('login-qr'),
      icon: AppIcons.qr,
      title: '扫码登录',
      detail: '使用另一台设备上的$title App 扫描二维码。',
      filled: !onDevice,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              backgroundColor: context.zero.canvas,
              appBar: AppBar(
                title: Row(
                  children: [
                    PlatformSourceIcon(source: SourceID(source), size: 28),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '扫码登录$title',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              body: QRLoginBody(source: source),
            ),
          ),
        );
      },
    );
    final choices = onDevice ? [device, qr] : [qr, device];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            PlatformSourceIcon(source: SourceID(source), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '密码仅在平台官方页面输入，零拍只保存登录信息。',
          style: TextStyle(color: context.zero.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        for (final choice in choices) ...[choice, const SizedBox(height: 12)],
      ],
    );
  }
}

class _LoginChoice extends StatelessWidget {
  const _LoginChoice({
    required this.icon,
    required this.title,
    required this.detail,
    required this.filled,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? FilledButton(onPressed: onPressed, child: Text(title))
        : OutlinedButton(onPressed: onPressed, child: Text(title));
    return Material(
      color: context.zero.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.zero.accent),
            const SizedBox(height: 12),
            Text(
              detail,
              style: TextStyle(color: context.zero.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: button),
          ],
        ),
      ),
    );
  }
}

class QRLoginBody extends ConsumerStatefulWidget {
  const QRLoginBody({required this.source, super.key});
  final String source;
  @override
  ConsumerState<QRLoginBody> createState() => _QRLoginBodyState();
}

class _QRLoginBodyState extends ConsumerState<QRLoginBody> {
  LoginQR? qr;
  late final CoreApi api;
  String message = '正在获取二维码';
  bool expired = false;
  bool busy = false;
  int generation = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    api = ref.read(coreApiProvider);
    _start();
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    if (qr != null) {
      unawaited(
        api.cancelLogin(widget.source, qr!.key).catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  Future<void> _start() async {
    final g = ++generation;
    timer?.cancel();
    setState(() {
      qr = null;
      expired = false;
      busy = true;
      message = '正在获取二维码';
    });
    try {
      final v = await ref.read(coreApiProvider).loginQR(widget.source);
      if (!mounted || g != generation) {
        await api.cancelLogin(widget.source, v.key);
        return;
      }
      setState(() {
        qr = v;
        busy = false;
        message = '请用另一台设备上的平台 App 扫码';
      });
      _schedule(g);
    } catch (e) {
      DeveloperLog.instance.error('登录', '获取二维码失败：${errorText(e)}');
      if (mounted && g == generation) {
        setState(() {
          busy = false;
          message = '获取二维码失败：${errorText(e)}';
          expired = true;
        });
      }
    }
  }

  void _schedule(int g) {
    timer = Timer(const Duration(seconds: 2), () => _poll(g));
  }

  Future<void> _poll(int g) async {
    try {
      final status = await ref
          .read(coreApiProvider)
          .pollLogin(widget.source, qr!.key);
      if (!mounted || g != generation) return;
      if (status.loggedIn) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        message = status.message.isEmpty ? '等待扫码' : status.message;
        expired = status.expired;
      });
      if (!expired) _schedule(g);
    } catch (e) {
      DeveloperLog.instance.error('登录', '登录失败：${errorText(e)}');
      if (mounted && g == generation) {
        setState(() {
          message = '登录失败：${errorText(e)}';
          expired = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Column(
        children: [
          if (qr != null && !expired)
            ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(data: qr!.url, size: 240),
              ),
            ),
          const SizedBox(height: 24),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            '只有一台设备时，请返回并选择「在本机登录」。',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.zero.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : _start,
            child: const Text('刷新二维码'),
          ),
        ],
      ),
    ),
  );
}
