import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/chrome.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import 'navigation.dart';
import 'web_login_page.dart';
import 'web_login_policy.dart';

class AccountsBody extends ConsumerStatefulWidget {
  const AccountsBody({super.key});
  @override
  ConsumerState<AccountsBody> createState() => _AccountsBodyState();
}

class _AccountsBodyState extends ConsumerState<AccountsBody> {
  StreamSubscription<String>? events;
  int version = 0;
  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) => AsyncFeature<List<SourceInfo>>(
    target: version,
    retain: true,
    load: () => ref.read(coreApiProvider).accounts(),
    builder: (context, data, reload) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text('登录后可以导入歌单和查看需要登录的内容。未登录时仍可匿名播放公开内容。'),
        ),
        const SizedBox(height: 8),
        InsetGroup(
          children: [
            for (final s in data.where(
              (s) => s.capabilities.names.contains('account'),
            ))
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: context.zero.accentSoft,
                  foregroundColor: context.zero.accent,
                  child: Text(_accountMark(s.mark, s.name)),
                ),
                title: Text(s.name),
                subtitle: Text(
                  s.user.loggedIn
                      ? (s.user.name.isEmpty ? '已登录' : s.user.name)
                      : '未登录，可以匿名使用',
                ),
                trailing: TextButton(
                  onPressed: () => perform(context, () async {
                    final api = ref.read(coreApiProvider);
                    if (s.user.loggedIn) {
                      if (!await confirmAction(
                        context,
                        '退出 ${s.name}',
                        '此来源的导入歌单将冻结，缓存曲目和混合引用保留。',
                      )) {
                        return;
                      }
                      await api.logout(s.id.value);
                    } else {
                      await openFeature(
                        context,
                        '登录 ${s.name}',
                        LoginOptions(source: s.id.value, title: s.name),
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

String _accountMark(String mark, String name) {
  if (mark.isNotEmpty) return mark;
  if (name.isEmpty) return '音';
  return String.fromCharCode(name.runes.first);
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
      icon: Icons.phonelink_lock_outlined,
      title: '在本机登录',
      detail: '打开$title的官方页面，在这台设备上完成登录。不需要另一台设备来扫码。',
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
      icon: Icons.qr_code_2,
      title: '二维码',
      detail: '适合桌面：用手机上的$title App 扫描。手机上看不到自己屏幕上的码。',
      filled: !onDevice,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              backgroundColor: context.zero.canvas,
              appBar: AppBar(title: Text('扫码登录$title')),
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
        Text(
          '密码只留在官方页面里。零拍只在登录成功后接收会话，不会出现在界面或日志中。',
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
        message = '请用另一台设备上的 App 扫描';
      });
      _schedule(g);
    } catch (e) {
      if (mounted && g == generation) {
        setState(() {
          busy = false;
          message = '$e';
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
      if (mounted && g == generation) {
        setState(() {
          message = '$e';
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
            '手机上请返回，改用「在本机登录」。二维码需要另一台设备才能看到并扫描。',
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
