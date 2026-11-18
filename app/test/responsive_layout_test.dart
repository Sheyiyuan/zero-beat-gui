import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  for (final scenario in [
    (AppLayout.mobile, const Size(390, 844), 2.0),
    (AppLayout.mobile, const Size(800, 400), 1.5),
    (AppLayout.desktop, const Size(640, 480), 1.5),
  ]) {
    testWidgets('navigation remains usable at $scenario', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = FakeCoreApi()
        ..libraryPlaylists = [samplePlaylist(title: '测试歌单')]
        ..librarySongs = [sampleSong(title: longTitle)];
      addTearDown(api.closeControllers);
      await pumpApp(tester, api: api, layout: scenario.$1, size: scenario.$2);
      expect(tester.takeException(), isNull);
      if (scenario.$1 == AppLayout.mobile) {
        await tester.tap(find.text('发现').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('曲库').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('测试歌单'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
