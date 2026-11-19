import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/theme.dart';

void main() {
  test('notices are capsules and stay readable in dark mode', () {
    final light = buildZeroTheme();
    final lightBar = light.snackBarTheme;
    expect(lightBar.behavior, SnackBarBehavior.floating);
    expect(lightBar.shape, isA<StadiumBorder>());
    expect(lightBar.backgroundColor, light.colorScheme.inverseSurface);
    expect(
      lightBar.contentTextStyle?.color,
      light.colorScheme.onInverseSurface,
    );

    final dark = buildZeroTheme(brightness: Brightness.dark);
    final darkBar = dark.snackBarTheme;
    final side = (darkBar.shape! as StadiumBorder).side;
    expect(side.style, BorderStyle.solid);
    expect(side.color, dark.colorScheme.outlineVariant);
    expect(darkBar.backgroundColor, dark.colorScheme.surfaceContainerHigh);
    expect(darkBar.contentTextStyle?.color, dark.colorScheme.onSurface);
    expect(darkBar.backgroundColor, isNot(dark.colorScheme.inverseSurface));
  });
}
