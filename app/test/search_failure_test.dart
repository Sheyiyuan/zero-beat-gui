import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('search failure stays on screen and retry runs again', (
    tester,
  ) async {
    final api = FakeCoreApi()..searchError = '搜索失败：网络不可用';
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(800, 900),
    );

    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), '夜航');
    await tester.pump();
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-error')), findsOneWidget);
    expect(find.text('搜索失败：网络不可用'), findsOneWidget);
    expect(api.searchCalls, 1);

    await tester.tap(find.byKey(const Key('search-retry')));
    await tester.pumpAndSettle();
    expect(api.searchCalls, 2);
    expect(find.text('搜索失败：网络不可用'), findsOneWidget);
  });
}
