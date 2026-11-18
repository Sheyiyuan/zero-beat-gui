import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import 'navigation.dart';

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
      children: [
        for (final s in data.where(
          (s) => s.capabilities.names.contains('account'),
        ))
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(s.name),
            subtitle: Text(s.user.loggedIn ? s.user.name : '未登录'),
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
                    QRLoginBody(source: s.id.value),
                  );
                }
                if (context.mounted) reload();
              }),
              child: Text(s.user.loggedIn ? '退出登录' : '扫码登录'),
            ),
          ),
      ],
    ),
  );
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
        message = '请使用对应平台 App 扫码';
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
          Text(message),
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
