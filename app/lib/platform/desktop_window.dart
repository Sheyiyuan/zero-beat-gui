import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'desktop_mode.dart';

/// The native window and tray outlive socket connections and page navigation.
class DesktopWindow with WindowListener, TrayListener {
  static final instance = DesktopWindow._();
  DesktopWindow._();
  static bool get installed => instance._installed;
  bool _installed = false;
  bool _tray = false;
  bool _switching = false;
  bool _maximized = false;
  Rect _normal = const Rect.fromLTWH(80, 80, 1280, 800);
  Rect _mini = const Rect.fromLTWH(80, 80, 420, 200);
  Timer? _debounce;
  String closeAction = 'background';
  Future<void> Function()? quit;
  Future<void> Function()? toggle;
  Future<void> Function()? next;
  Future<void> Function(String)? save;
  static const _channel = MethodChannel('zero_beat/desktop');

  static Future<void> install() => instance._install();
  Future<void> _install() async {
    if (_installed) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.setTitle('零拍');
    await windowManager.setMinimumSize(const Size(640, 480));
    DesktopMode.enterMiniWindow = _enterMini;
    DesktopMode.restoreWindow = _restore;
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      await trayManager.setIcon('assets/tray.png');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'restore', label: '显示零拍'),
            MenuItem(key: 'toggle', label: '播放／暂停'),
            MenuItem(key: 'next', label: '下一首'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出'),
          ],
        ),
      );
      _tray = true;
    } catch (_) {
      _tray = false;
    }
    _installed = true;
  }

  Future<void> restoreSaved(String raw) async {
    if (!_installed || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map;
      Rect rect(Object? value, Rect fallback) {
        if (value is! List || value.length != 4) return fallback;
        final n = value.map((v) => (v as num).toDouble()).toList();
        if (n.any((v) => !v.isFinite) || n[2] <= 0 || n[3] <= 0) {
          return fallback;
        }
        return Rect.fromLTWH(n[0], n[1], n[2], n[3]);
      }

      _normal = rect(data['normal'], _normal);
      _mini = rect(data['mini'], _mini);
      _maximized = data['maximized'] == true;
      await _restore();
    } catch (_) {
      /* A damaged preference must not prevent startup. */
    }
  }

  /// Restore entirely onto an available monitor after unplugging a display.
  static Rect fitBounds(Rect wanted, List<Rect> displays) {
    if (displays.isEmpty) return wanted;
    var screen = displays.first;
    var area = 0.0;
    for (final candidate in displays) {
      final intersection = candidate.intersect(wanted);
      final visible = intersection.isEmpty
          ? 0.0
          : intersection.width * intersection.height;
      if (visible > area) {
        area = visible;
        screen = candidate;
      }
    }
    final width = wanted.width.clamp(
      math.min(380.0, screen.width),
      screen.width,
    );
    final height = wanted.height.clamp(
      math.min(180.0, screen.height),
      screen.height,
    );
    return Rect.fromLTWH(
      wanted.left.clamp(screen.left, screen.right - width).toDouble(),
      wanted.top.clamp(screen.top, screen.bottom - height).toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }

  Future<Rect> _fit(Rect bounds) async {
    final displays = await screenRetriever.getAllDisplays();
    return fitBounds(
      bounds,
      displays
          .map(
            (d) =>
                (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
          )
          .toList(),
    );
  }

  Future<void> _enterMini() async {
    _switching = true;
    try {
      _maximized = await windowManager.isMaximized();
      if (!_maximized) _normal = await windowManager.getBounds();
      await windowManager.unmaximize();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setMinimumSize(const Size(380, 180));
      await windowManager.setBounds(await _fit(_mini));
      await show();
    } finally {
      _switching = false;
    }
  }

  Future<void> _restore() async {
    _switching = true;
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(640, 480));
      await windowManager.setBounds(await _fit(_normal));
      if (_maximized) await windowManager.maximize();
      await show();
    } finally {
      _switching = false;
    }
  }

  Future<void> show() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  static Future<void> closeWindow() => instance._close();
  Future<void> _close() async {
    try {
      await _persist();
    } catch (_) {
      /* Closing works while disconnected. */
    }
    switch (closeAction) {
      case 'quit':
        await quit?.call();
      case 'mini':
        await DesktopMode.enterMini();
      default:
        var available = _tray;
        if (Platform.isLinux && available) {
          try {
            available =
                await _channel.invokeMethod<bool>('trayAvailable') ?? false;
          } catch (_) {
            available = false;
          }
        }
        if (available) {
          await windowManager.hide();
        } else {
          await windowManager.minimize();
        }
    }
  }

  Future<void> _persist() async {
    if (!_installed || _switching || await windowManager.isMinimized()) return;
    final maximized = await windowManager.isMaximized();
    if (DesktopMode.mini.value) {
      _mini = await windowManager.getBounds();
    } else {
      _maximized = maximized;
      if (!maximized) _normal = await windowManager.getBounds();
    }
    List<double> rect(Rect r) => [r.left, r.top, r.width, r.height];
    await save?.call(
      jsonEncode({
        'normal': rect(_normal),
        'mini': rect(_mini),
        'maximized': _maximized,
      }),
    );
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _persist();
      } catch (_) {}
    });
  }

  @override
  void onWindowClose() {
    unawaited(_close());
  }

  @override
  void onWindowMoved() => _scheduleSave();
  @override
  void onWindowResized() => _scheduleSave();
  @override
  void onWindowMaximize() => _scheduleSave();
  @override
  void onWindowUnmaximize() => _scheduleSave();
  @override
  void onTrayIconMouseDown() {
    unawaited(show());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'restore':
        unawaited(show());
      case 'toggle':
        unawaited(toggle?.call());
      case 'next':
        unawaited(next?.call());
      case 'quit':
        unawaited(quit?.call());
    }
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    try {
      await _persist();
    } catch (_) {
      // A disconnected core cannot persist bounds; cleanup must still run.
    }
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _installed = false;
    save = null;
    toggle = null;
    next = null;
    if (_tray) {
      _tray = false;
      await trayManager.destroy();
    }
  }
}
