import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/platform/desktop_mode.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('space toggles playback unless a search field is focused', (
    tester,
  ) async {
    final api = FakeCoreApi();
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.desktop);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.toggles, 1);

    await tester.tap(find.byKey(const Key('search-field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.toggles, 1);
  });

  testWidgets('mini player quit calls the core and restore leaves mini mode', (
    tester,
  ) async {
    final api = FakeCoreApi();
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.desktop);

    DesktopMode.mini.value = true;
    await tester.pump();
    expect(find.byTooltip('恢复'), findsOneWidget);
    expect(find.byTooltip('退出'), findsOneWidget);

    await tester.tap(find.byTooltip('退出'));
    await tester.pump();
    expect(api.quits, 1);

    await tester.tap(find.byTooltip('恢复'));
    await tester.pump();
    expect(DesktopMode.mini.value, isFalse);
    expect(find.text('曲库'), findsWidgets);
  });
}
