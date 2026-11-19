import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/session.dart';
import 'developer_log_collectors.dart';
import 'providers.dart';
import '../features/settings_page.dart';
import '../platform/desktop_window.dart';
import '../platform/haptics.dart';
import '../platform/window_frame.dart';

import '../desktop/desktop_shell.dart';
import '../mobile/mobile_shell.dart';
import '../shared/player_bar.dart';
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
        final gated = HapticTapListener(
          enabled: settings.haptics,
          child: _ConnectionGate(child: child!),
        );
        final observed = DeveloperLogCollectors(
          child: PlaybackErrorToast(child: gated),
        );
        return layout == AppLayout.desktop && DesktopWindow.installed
            ? ZeroWindowFrame(child: observed)
            : observed;
      },
      home: _LibraryRefreshOnResume(
        child: layout == AppLayout.desktop
            ? const DesktopShell()
            : const MobileShell(),
      ),
    );
  }
}

/// Keeps the library reasonably fresh after the window was in the background.
/// A short session switch does not hit the core, and the refresh reuses the
/// selected playlist so it cannot override the user's choice.
class _LibraryRefreshOnResume extends ConsumerStatefulWidget {
  const _LibraryRefreshOnResume({required this.child});

  final Widget child;

  @override
  ConsumerState<_LibraryRefreshOnResume> createState() =>
      _LibraryRefreshOnResumeState();
}

class _LibraryRefreshOnResumeState
    extends ConsumerState<_LibraryRefreshOnResume>
    with WidgetsBindingObserver {
  static const _staleAfter = Duration(seconds: 30);

  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null ||
        DateTime.now().difference(backgroundedAt) < _staleAfter) {
      return;
    }
    final library = ref.read(libraryProvider);
    if (library.loading || library.refreshing) return;
    ref.read(libraryProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
                        const Text('播放服务已断开，播放已停止'),
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
