import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/features/developer_mode.dart';
import 'package:zero_beat_gui/app/zero_beat_app.dart';
import 'package:zero_beat_gui/platform/desktop_mode.dart';
import 'package:zero_beat_gui/platform/system_volume.dart';

import 'fake_core.dart';
import 'fake_system_volume.dart';
import 'memory_developer_mode_store.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeCoreApi api,
  required AppLayout layout,
  Size size = const Size(1440, 960),
  List<Override> overrides = const [],
  SystemVolume? systemVolume,
}) async {
  DesktopMode.mini.value = false;
  final volume =
      systemVolume ?? (layout == AppLayout.mobile ? FakeSystemVolume() : null);
  if (layout == AppLayout.mobile && systemVolume == null) {
    addTearDown(volume!.dispose);
  }
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
        developerModeStoreProvider.overrideWithValue(
          MemoryDeveloperModeStore(),
        ),
        quitActionProvider.overrideWith((ref) {
          final core = ref.watch(coreApiProvider);
          return () => core.quit();
        }),
        platformLabelProvider.overrideWithValue(
          layout == AppLayout.mobile ? 'android' : 'linux',
        ),
        if (volume != null) systemVolumeProvider.overrideWithValue(volume),
        ...overrides,
      ],
      child: ZeroBeatApp(layout: layout),
    ),
  );
  await tester.pumpAndSettle();
}
