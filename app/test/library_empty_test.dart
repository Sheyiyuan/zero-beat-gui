import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('empty library shows an empty state', (tester) async {
    final api = FakeCoreApi();
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(800, 900),
    );

    expect(find.byKey(const Key('empty-library')), findsOneWidget);
    expect(find.text('这里还没有歌曲'), findsOneWidget);
    expect(find.text('示例歌曲'), findsNothing);
  });
}
