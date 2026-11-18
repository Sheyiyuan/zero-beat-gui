import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('system back closes the queue sheet before leaving the page', (
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

    await tester.tap(find.byKey(const Key('queue-button')));
    await tester.pumpAndSettle();
    expect(find.text('播放队列'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('播放队列'), findsNothing);
    expect(find.text('曲库'), findsWidgets);
    expect(api.pauses, 0);
    expect(api.toggles, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('曲库'), findsWidgets);
    expect(api.pauses, 0);

    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
    expect(find.text('正在播放'), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('曲库'), findsWidgets);
    expect(api.pauses, 0);
    expect(api.toggles, 0);
  });
}
