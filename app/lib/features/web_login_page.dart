import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter/services.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../app/providers.dart';
import '../shared/brand_mark.dart';
import '../app/theme.dart';
import '../core/developer_log.dart';
import '../shared/playback.dart';
import 'web_login_policy.dart';

typedef WebCookieReader =
    Future<Map<String, String>> Function(List<String> urls);
typedef WebCookieClear = Future<void> Function();

final _channel = MethodChannel('zero_beat/web_login');

Future<Map<String, String>> readSystemWebCookies(List<String> urls) async {
  final raw = await _channel.invokeMapMethod<Object?, Object?>('read', {
    'urls': urls,
  });
  final out = <String, String>{};
  raw?.forEach((key, value) {
    if (key != null && value != null) out[key.toString()] = value.toString();
  });
  return out;
}

Future<void> clearSystemWebCookies() async {
  try {
    await _channel.invokeMethod<void>('clear');
  } catch (_) {}
}

class WebLoginPage extends ConsumerStatefulWidget {
  const WebLoginPage({
    required this.source,
    required this.title,
    this.cookies,
    this.clearCookies,
    this.viewport,
    super.key,
  });

  final String source;
  final String title;
  final WebCookieReader? cookies;
  final WebCookieClear? clearCookies;
  final Widget? viewport;

  @override
  ConsumerState<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends ConsumerState<WebLoginPage> {
  WebViewController? _controller;
  Timer? _timer;
  String _hint = '请在官方页面登录。零拍不读取密码，仅保存登录信息。';
  bool _busy = false;
  bool _done = false;
  bool _browserReady = false;

  @override
  void initState() {
    super.initState();
    _browserReady = widget.viewport != null || WebViewPlatform.instance != null;
    if (widget.viewport == null && WebViewPlatform.instance != null) {
      _controller = WebViewController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openOfficialPage());
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_tryComplete());
    });
  }

  Future<void> _openOfficialPage() async {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final phone =
        defaultTargetPlatform == TargetPlatform.android ||
        MediaQuery.sizeOf(context).shortestSide < 600;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setUserAgent(loginUserAgent(widget.source, phone: phone));
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          if (allowedLoginNavigation(widget.source, request.url)) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          unawaited(_tryComplete());
        },
      ),
    );
    await _tighten(controller);
    if (!mounted) return;
    await controller.loadRequest(
      Uri.parse(loginPageUrl(widget.source, phone: phone)),
    );
  }

  Future<void> _tighten(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setAllowFileAccess(false);
      await platform.setMixedContentMode(MixedContentMode.compatibilityMode);
      await platform.setUseWideViewPort(widget.source != 'netease');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_done) unawaited(_clear());
    super.dispose();
  }

  Future<void> _clear() async {
    final clear = widget.clearCookies ?? clearSystemWebCookies;
    await clear();
  }

  Future<void> _tryComplete() async {
    if (!mounted || _done || _busy) return;
    final reader = widget.cookies ?? readSystemWebCookies;
    Map<String, String> found;
    try {
      found = await reader(loginCookieUrls(widget.source));
    } catch (_) {
      DeveloperLog.instance.warning('登录', '无法读取系统 Cookie');
      if (mounted && !_done) {
        setState(() => _hint = '暂时无法确认登录状态，请稍后点「我已完成登录」。');
      }
      return;
    }
    final cookies = sessionCookies(widget.source, found);
    found.clear();
    if (cookies.isEmpty) {
      if (mounted && !_done) setState(() => _hint = '请在官方页面完成登录，成功后会自动返回。');
      return;
    }
    setState(() {
      _busy = true;
      _hint = '正在确认登录状态';
    });
    try {
      final result = await ref
          .read(coreApiProvider)
          .commitWebLogin(widget.source, cookies);
      cookies.clear();
      await _clear();
      if (!mounted) return;
      _done = true;
      _timer?.cancel();
      Navigator.pop(context, result.loggedIn);
    } catch (error) {
      cookies.clear();
      DeveloperLog.instance.error('登录', '网页登录失败：${errorText(error)}');
      if (!mounted || _done) return;
      setState(() {
        _busy = false;
        _hint = '登录失败：${errorText(error)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = loginPageUrl(widget.source, phone: true);
    return Scaffold(
      backgroundColor: context.zero.canvas,
      appBar: AppBar(
        title: Row(
          children: [
            BrandMark(source: widget.source, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text('登录${widget.title}', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : () => _controller?.reload(),
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              _hint,
              key: const Key('web-login-status'),
              style: TextStyle(color: context.zero.muted, height: 1.4),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: context.zero.surface,
                  child: _browserReady
                      ? (widget.viewport ??
                            (_controller == null
                                ? const SizedBox.shrink()
                                : WebViewWidget(controller: _controller!)))
                      : _missingBrowser(phone),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: FilledButton(
              key: const Key('web-login-check'),
              onPressed: _busy ? null : _tryComplete,
              child: Text(_busy ? '正在确认' : '我已完成登录'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _missingBrowser(String url) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.browserOff, color: context.zero.muted, size: 36),
          const SizedBox(height: 12),
          Text(
            '此设备暂不支持页面登录。请返回选择「扫码登录」，用另一台设备扫描。',
            key: const Key('web-login-unavailable'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.zero.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
