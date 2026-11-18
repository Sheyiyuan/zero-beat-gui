import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/session.dart';
import 'providers.dart';
import '../features/settings_page.dart';
import '../platform/desktop_window.dart';
import '../platform/window_frame.dart';

import '../desktop/desktop_shell.dart';
import '../mobile/mobile_shell.dart';
import 'layout.dart';
import 'theme.dart';

class ZeroBeatApp extends ConsumerWidget {
  const ZeroBeatApp({required this.layout, super.key});

  final AppLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(guiSettingsProvider);
    return MaterialApp(
      title: '零拍',
      debugShowCheckedModeBanner: false,
      theme: buildZeroTheme(palette: settings.palette, accent: settings.accent),
      darkTheme: buildZeroTheme(
        brightness: Brightness.dark,
        palette: settings.palette,
        accent: settings.accent,
      ),
      themeMode: settings.theme == 'dark'
          ? ThemeMode.dark
          : settings.theme == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      builder: (context, child) {
        final gated = _ConnectionGate(child: child!);
        return layout == AppLayout.desktop && DesktopWindow.installed
            ? ZeroWindowFrame(child: gated)
            : gated;
      },
      home: layout == AppLayout.desktop
          ? const DesktopShell()
          : const MobileShell(),
    );
  }
}

class _ConnectionGate extends ConsumerWidget {
  const _ConnectionGate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(connectionProvider);
    return Stack(
      children: [
        ExcludeFocus(
          excluding: !connected,
          child: AbsorbPointer(absorbing: !connected, child: child),
        ),
        if (!connected)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('与核心的连接已断开，播放已停止'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: ref.read(reconnectActionProvider),
                          child: const Text('重新连接'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
