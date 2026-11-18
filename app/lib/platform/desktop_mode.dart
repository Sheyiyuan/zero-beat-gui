import 'package:flutter/foundation.dart';

/// Mini-window flag shared by the shell and the desktop window bridge.
class DesktopMode {
  static final mini = ValueNotifier<bool>(false);
  static Future<void> Function()? enterMiniWindow;
  static Future<void> Function()? restoreWindow;

  static Future<void> enterMini() async {
    mini.value = true;
    final hook = enterMiniWindow;
    if (hook != null) await hook();
  }

  static Future<void> restore() async {
    mini.value = false;
    final hook = restoreWindow;
    if (hook != null) await hook();
  }
}
