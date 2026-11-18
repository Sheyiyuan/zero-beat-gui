import 'package:flutter/material.dart';

/// Colors from zero-beat-gui/design/tokens.json.
abstract final class ZeroColors {
  static const canvas = Color(0xFFF7F3F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF0E8EC);
  static const text = Color(0xFF2B262B);
  static const muted = Color(0xFF6B5F66);
  static const line = Color(0xFFDFD4DA);
  static const accent = Color(0xFFB02A52);
  static const accentSoft = Color(0xFFF7DBE2);
  static const positive = Color(0xFF1A7F37);
  static const warning = Color(0xFF8A5A00);
  static const danger = Color(0xFFB42318);
}

class ZeroPalette {
  const ZeroPalette(this.scheme);
  final ColorScheme scheme;
  Color get canvas => scheme.surfaceContainerLowest;
  Color get surface => scheme.surface;
  Color get surfaceMuted => scheme.surfaceContainer;
  Color get text => scheme.onSurface;
  Color get muted => scheme.onSurfaceVariant;
  Color get line => scheme.outlineVariant;
  Color get accent => scheme.primary;
  Color get accentSoft => scheme.primaryContainer;
  Color get positive => scheme.brightness == Brightness.dark
      ? const Color(0xFF8BD69D)
      : ZeroColors.positive;
  Color get warning => scheme.brightness == Brightness.dark
      ? const Color(0xFFFFCB80)
      : ZeroColors.warning;
  Color get danger => scheme.error;
}

extension ZeroThemeContext on BuildContext {
  ZeroPalette get zero => ZeroPalette(Theme.of(this).colorScheme);
}

ThemeData buildZeroTheme({
  Brightness brightness = Brightness.light,
  String palette = 'zero-red',
  String accent = '',
}) {
  final custom = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(accent)
      ? int.parse(accent.substring(1), radix: 16)
      : null;
  final seed = custom != null
      ? Color(0xFF000000 | custom)
      : palette == 'hanpai-blue'
      ? const Color(0xFF245C9E)
      : ZeroColors.accent;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  ).copyWith(primary: brightness == Brightness.light ? seed : null);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    dividerColor: scheme.outlineVariant,
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: scheme.onSurface, fontSize: 14, height: 1.4),
      bodySmall: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        height: 1.4,
      ),
      titleMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surfaceContainerLowest,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 13,
      ),
    ),
  );
}
