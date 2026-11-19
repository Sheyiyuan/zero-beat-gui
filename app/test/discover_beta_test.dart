import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('discover marks radio and public pages as unfinished', (
    tester,
  ) async {
    final api = FakeCoreApi();
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(800, 900),
    );

    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();

    expect(find.text('电台与公开主页'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });
}
