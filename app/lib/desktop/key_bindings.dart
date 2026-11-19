import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// GUI bindings are stored separately from the TUI key map. Empty means disabled.
const guiShortcutDefaults = <String, String>{
  'toggle': 'Space',
  'search': 'Ctrl+F',
  'previous': 'Ctrl+ArrowLeft',
  'next': 'Ctrl+ArrowRight',
  'authors': 'U',
  'volume_down': 'Minus',
  'volume_up': 'Shift+Equal',
  'play_selected': 'Enter',
  'close_panel': 'Escape',
};
const guiShortcutLabels = <String, String>{
  'toggle': '播放／暂停',
  'search': '搜索',
  'previous': '上一首',
  'next': '下一首',
  'authors': '当前作者',
  'volume_down': '降低音量',
  'volume_up': '提高音量',
  'play_selected': '播放选中曲目',
  'close_panel': '关闭面板',
};
final _keys = <String, LogicalKeyboardKey>{
  'space': LogicalKeyboardKey.space,
  'arrowleft': LogicalKeyboardKey.arrowLeft,
  'arrowright': LogicalKeyboardKey.arrowRight,
  'arrowup': LogicalKeyboardKey.arrowUp,
  'arrowdown': LogicalKeyboardKey.arrowDown,
  'minus': LogicalKeyboardKey.minus,
  'equal': LogicalKeyboardKey.equal,
  'enter': LogicalKeyboardKey.enter,
  'escape': LogicalKeyboardKey.escape,
  for (var i = 0; i < 26; i++)
    String.fromCharCode(97 + i): LogicalKeyboardKey(97 + i),
  for (var i = 0; i < 10; i++) '$i': LogicalKeyboardKey(48 + i),
};

SingleActivator? parseGUIShortcut(String value) {
  if (value.trim().isEmpty) return null;
  final parts = value.toLowerCase().split('+').map((s) => s.trim()).toList();
  final key = _keys[parts.last];
  final modifiers = parts.take(parts.length - 1).toSet();
  if (key == null ||
      modifiers.length != parts.length - 1 ||
      modifiers.any((s) => !{'ctrl', 'alt', 'shift', 'meta'}.contains(s))) {
    throw const FormatException(
      '使用 Ctrl、Alt、Shift、Meta 和字母、数字或 Space、Enter、Escape、ArrowLeft 等按键',
    );
  }
  return SingleActivator(
    key,
    control: modifiers.contains('ctrl'),
    alt: modifiers.contains('alt'),
    shift: modifiers.contains('shift'),
    meta: modifiers.contains('meta'),
    includeRepeats: false,
  );
}

void validateGUIShortcuts(Map<String, String> overrides) {
  final used = <String>{};
  for (final entry in {...guiShortcutDefaults, ...overrides}.entries) {
    final key = parseGUIShortcut(entry.value);
    if (key == null) continue;
    final identity =
        '${key.trigger.keyId}:${key.control}:${key.alt}:${key.shift}:${key.meta}';
    if (!used.add(identity)) {
      throw const FormatException('此快捷键已被使用，请换一个或先修改原设置。');
    }
  }
}
