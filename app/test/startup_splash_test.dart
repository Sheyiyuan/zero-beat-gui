import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/core/startup_appearance.dart';
import 'package:zero_beat_gui/core/startup_splash.dart';

void main() {
  Widget splash({required bool ready, required VoidCallback onExited}) =>
      StartupSplash(
        appearance: const StartupAppearance(theme: 'dark'),
        ready: ready,
        onExited: onExited,
      );

  testWidgets('a fast core still waits for the intro before fading out', (
    tester,
  ) async {
    var exited = false;
    await tester.pumpWidget(splash(ready: false, onExited: () => {}));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(splash(ready: true, onExited: () => exited = true));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(exited, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(exited, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(exited, isTrue);
  });

  testWidgets('shows the startup error with a retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      StartupSplash(
        appearance: const StartupAppearance(),
        ready: false,
        error: 'Connection refused',
        onRetry: () => retried = true,
        onExited: () {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('无法连接播放服务'), findsOneWidget);
    expect(find.text('Connection refused'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
  });
}
