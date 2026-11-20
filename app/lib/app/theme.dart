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
  bool get _dark => scheme.brightness == Brightness.dark;
  Color get canvas => scheme.surfaceContainerLowest;
  Color get surface => scheme.surfaceContainerLow;
  Color get surfaceMuted => scheme.surfaceContainer;

  /// Floating chrome (mini player) that sits above the canvas.
  Color get raised =>
      _dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest;
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

ThemeMode zeroThemeMode(String theme) => switch (theme) {
  'dark' => ThemeMode.dark,
  'light' => ThemeMode.light,
  _ => ThemeMode.system,
};

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
  final accentScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  // Accent roles keep the seed hue; every surface, outline and text role comes
  // from the monochrome variant. Even the "neutral" variant leaves a visible
  // rose cast with the red seed, so pages, sheets and bars stay true grey and
  // the accent and cover art carry the colour.
  final neutral = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  );
  final scheme = accentScheme.copyWith(
    primary: brightness == Brightness.light ? seed : null,
    surface: neutral.surface,
    onSurface: neutral.onSurface,
    onSurfaceVariant: neutral.onSurfaceVariant,
    surfaceDim: neutral.surfaceDim,
    surfaceBright: neutral.surfaceBright,
    surfaceContainerLowest: neutral.surfaceContainerLowest,
    surfaceContainerLow: neutral.surfaceContainerLow,
    surfaceContainer: neutral.surfaceContainer,
    surfaceContainerHigh: neutral.surfaceContainerHigh,
    surfaceContainerHighest: neutral.surfaceContainerHighest,
    outline: neutral.outline,
    outlineVariant: neutral.outlineVariant,
    inverseSurface: neutral.inverseSurface,
    onInverseSurface: neutral.onInverseSurface,
  );
  final dark = brightness == Brightness.dark;
  final canvas = scheme.surfaceContainerLowest;
  final group = scheme.surfaceContainerLow;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    dividerColor: scheme.outlineVariant,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: dark ? 0.6 : 0.7),
      thickness: 1,
      space: 1,
    ),
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: scheme.onSurface, fontSize: 16, height: 1.45),
      bodyMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: const StadiumBorder()),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: group,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: group,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      minVerticalPadding: 10,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 13,
        height: 1.35,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: group,
      selectedColor: scheme.primaryContainer,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: group,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: brightness == Brightness.dark ? 0 : 2,
      insetPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      shape: StadiumBorder(
        side: brightness == Brightness.dark
            ? BorderSide(color: scheme.outlineVariant)
            : BorderSide.none,
      ),
      backgroundColor: brightness == Brightness.dark
          ? scheme.surfaceContainerHigh
          : scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: brightness == Brightness.dark
            ? scheme.onSurface
            : scheme.onInverseSurface,
        fontSize: 14,
        height: 1.35,
      ),
      actionTextColor: brightness == Brightness.dark
          ? scheme.primary
          : scheme.inversePrimary,
    ),
  );
}
