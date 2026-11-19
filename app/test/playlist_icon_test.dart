import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/theme.dart';
import 'package:zero_beat_gui/shared/brand_mark.dart';
import 'package:zero_beat_gui/shared/song_tile.dart';

import 'support/samples.dart';

void main() {
  testWidgets('library playlist marks use the theme accent', (tester) async {
    final theme = buildZeroTheme(palette: 'hanpai-blue');
    final accent = theme.colorScheme.primary;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Column(
          children: [
            PlaylistSourceIcon(
              playlist: _playlist(
                source: SourceID.valueBilibili,
                kind: PlaylistKind.valueRemote,
              ),
            ),
            PlaylistSourceIcon(
              playlist: _playlist(
                source: SourceID.valueNetease,
                kind: PlaylistKind.valueRemote,
              ),
            ),
            PlaylistSourceIcon(
              playlist: _playlist(kind: PlaylistKind.valueMixin),
            ),
            PlaylistSourceIcon(playlist: samplePlaylist()),
          ],
        ),
      ),
    );

    final marks = tester.widgetList<BrandMark>(find.byType(BrandMark));
    expect(marks.map((mark) => mark.color), everyElement(accent));
    expect(
      marks.map((mark) => mark.color),
      isNot(contains(BrandMark.colors['bilibili'])),
    );
    final icons = tester.widgetList<Icon>(find.byType(Icon));
    expect(icons.map((icon) => icon.color), everyElement(accent));
    expect(find.byIcon(LucideIcons.gitFork), findsOneWidget);
  });
}

Playlist _playlist({
  SourceID source = SourceID.valueLocal,
  PlaylistKind kind = PlaylistKind.valueLocal,
}) {
  return Playlist(
    id: '${source.value}-${kind.value}',
    source: source,
    title: kind.value,
    kind: kind,
    remoteId: '',
    count: 1,
    frozen: false,
    syncExcluded: false,
    rootPath: '',
    scanStatus: '',
    hasScanError: false,
  );
}
