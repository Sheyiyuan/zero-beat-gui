import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/layout.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/zero_beat_app.dart';
import '../platform/desktop_window.dart';
import '../platform/window_frame.dart';
import 'bootstrap.dart';

class CoreStartup extends StatefulWidget {
  const CoreStartup({super.key});

  @override
  State<CoreStartup> createState() => _CoreStartupState();
}

class _CoreStartupState extends State<CoreStartup> {
  late Future<StartedCore> _future;

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  Future<StartedCore> _start() async {
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
      await _installWindow();
    }
    return CoreRuntime.instance.ensureStarted();
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
      _future = CoreRuntime.instance.ensureStarted();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StartedCore>(
      future: _future,
      builder: (context, snapshot) {
        final started = snapshot.data;
        if (snapshot.connectionState == ConnectionState.done &&
            started != null) {
          return _scope(started);
        }
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildZeroTheme(),
            builder: (context, child) => DesktopWindow.installed
                ? ZeroWindowFrame(child: child!)
                : child!,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '无法连接核心\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _retry, child: const Text('重试')),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildZeroTheme(),
          builder: (context, child) =>
              DesktopWindow.installed ? ZeroWindowFrame(child: child!) : child!,
          home: const Scaffold(body: Center(child: Text('正在连接核心'))),
        );
      },
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
