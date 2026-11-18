import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('long titles ellipsize and keep the full semantics label', (
    tester,
  ) async {
    final song = sampleSong(id: 'long-1', title: longTitle);
    final api = FakeCoreApi()
      ..libraryPlaylists = [samplePlaylist(count: 1)]
      ..librarySongs = [song];
    addTearDown(api.closeControllers);
    final semantics = tester.ensureSemantics();
    try {
      await pumpApp(tester, api: api, layout: AppLayout.desktop);

      final title = tester.widget<Text>(
        find.byKey(const ValueKey('title-long-1')),
      );
      expect(title.data, longTitle);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(longTitle))),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
}
