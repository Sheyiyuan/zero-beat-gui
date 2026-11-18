import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/app/zero_beat_app.dart';
import 'package:zero_beat_gui/platform/desktop_mode.dart';

import 'fake_core.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeCoreApi api,
  required AppLayout layout,
  Size size = const Size(1440, 960),
}) async {
  DesktopMode.mini.value = false;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coreApiProvider.overrideWithValue(api),
        quitActionProvider.overrideWith((ref) {
          final core = ref.watch(coreApiProvider);
          return () => core.quit();
        }),
        platformLabelProvider.overrideWithValue(
          layout == AppLayout.mobile ? 'android' : 'linux',
        ),
      ],
      child: ZeroBeatApp(layout: layout),
    ),
  );
  await tester.pumpAndSettle();
}
