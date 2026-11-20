import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app/theme.dart';

/// The GUI theme settings live in the core, which is not reachable until
/// startup finishes. The splash reads this local copy instead.
class StartupAppearance {
  const StartupAppearance({
    this.theme = 'system',
    this.palette = 'zero-red',
    this.accent = '',
  });

  final String theme;
  final String palette;
  final String accent;

  ThemeMode get mode => zeroThemeMode(theme);

  ThemeData themeData(Brightness brightness) => buildZeroTheme(
    brightness: brightness,
    palette: palette,
    accent: accent,
  );

  static Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/startup_appearance.json',
  );

  /// Never blocks startup for long; a missing or unreadable copy falls back
  /// to the defaults.
  static Future<StartupAppearance> load() async {
    try {
      return await _read().timeout(const Duration(milliseconds: 300));
    } catch (_) {
      return const StartupAppearance();
    }
  }

  static Future<StartupAppearance> _read() async {
    final text = await (await _file()).readAsString();
    final json = jsonDecode(text) as Map<String, dynamic>;
    return StartupAppearance(
      theme: json['theme'] as String? ?? 'system',
      palette: json['palette'] as String? ?? 'zero-red',
      accent: json['accent'] as String? ?? '',
    );
  }

  Future<void> save() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'theme': theme, 'palette': palette, 'accent': accent}),
      );
    } catch (_) {}
  }

  @override
  bool operator ==(Object other) =>
      other is StartupAppearance &&
      other.theme == theme &&
      other.palette == palette &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(theme, palette, accent);
}
