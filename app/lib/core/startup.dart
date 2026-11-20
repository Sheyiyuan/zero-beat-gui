import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/layout.dart';
import '../app/providers.dart';
import '../app/zero_beat_app.dart';
import '../platform/desktop_window.dart';
import 'bootstrap.dart';
import 'developer_log.dart';
import 'startup_appearance.dart';
import 'startup_splash.dart';

class CoreStartup extends StatefulWidget {
  const CoreStartup({this.appearance = const StartupAppearance(), super.key});

  final StartupAppearance appearance;

  @override
  State<CoreStartup> createState() => _CoreStartupState();
}

class _CoreStartupState extends State<CoreStartup> {
  StartedCore? _started;
  Object? _error;
  bool _splash = true;
  bool _intro = true;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _track(_start());
  }

  void _track(Future<StartedCore> future) {
    final attempt = ++_attempt;
    future.then(
      (started) {
        if (mounted && attempt == _attempt) {
          setState(() => _started = started);
        }
      },
      onError: (Object error) {
        if (mounted && attempt == _attempt) setState(() => _error = error);
      },
    );
  }

  Future<StartedCore> _start() async {
    final log = DeveloperLog.instance;
    try {
      if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
        await _installWindow();
      }
      log.info('启动', '正在连接播放服务');
      final started = await CoreRuntime.instance.ensureStarted();
      log.info('启动', '播放服务已就绪（${started.platform}）');
      return started;
    } catch (error) {
      log.error('启动', '无法连接播放服务：$error');
      rethrow;
    }
  }

  Future<void> _installWindow() async {
    try {
      await DesktopWindow.install();
      DesktopWindow.instance.quit = () async {
        await CoreRuntime.instance.close();
        exit(0);
      };
    } catch (_) {}
  }

  void _retry() {
    setState(() {
      _started = null;
      _error = null;
      _splash = true;
      _intro = false;
    });
    _track(CoreRuntime.instance.ensureStarted());
  }

  @override
  Widget build(BuildContext context) {
    final started = _started;
    // The app mounts under the splash as soon as the core is ready, so the
    // fade-out reveals a page that is already laid out.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (started != null) _scope(started),
          if (_splash)
            ExcludeFocus(
              key: const ValueKey('startup-splash'),
              excluding: started != null,
              child: IgnorePointer(
                ignoring: started != null,
                child: StartupSplash(
                  appearance: widget.appearance,
                  ready: started != null,
                  intro: _intro,
                  error: _error?.toString(),
                  onRetry: _retry,
                  onExited: () => setState(() => _splash = false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _scope(StartedCore started) {
    return ProviderScope(
      key: ObjectKey(started.api),
      overrides: [
        coreApiProvider.overrideWithValue(started.api),
        reconnectActionProvider.overrideWithValue(_retry),
        quitActionProvider.overrideWithValue(() async {
          if (DesktopWindow.installed) await DesktopWindow.instance.dispose();
          await CoreRuntime.instance.close();
          exit(0);
        }),
        playbackHostProvider.overrideWithValue(started.host),
        interruptionPolicyProvider.overrideWithValue(started.policy),
        platformLabelProvider.overrideWithValue(started.platform),
        engineCapabilitiesProvider.overrideWithValue(
          List<String>.unmodifiable(started.host.capabilities),
        ),
      ],
      child: ZeroBeatApp(
        layout: started.platform == 'android'
            ? AppLayout.mobile
            : AppLayout.desktop,
      ),
    );
  }
}
