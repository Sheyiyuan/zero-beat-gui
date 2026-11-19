import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/icons.dart';
import 'package:zero_beat_gui/shared/brand_mark.dart';
import 'package:zero_beat_gui/shared/song_tile.dart';

void main() {
  testWidgets('mixed playlists use a layers badge and bilibili uses its mark', (
    tester,
  ) async {
    final mixed = Playlist(
      id: 'mix-1',
      source: SourceID.valueLocal,
      title: '混合歌单',
      kind: PlaylistKind.valueMixin,
      remoteId: '',
      count: 3,
      frozen: false,
      syncExcluded: false,
      rootPath: '',
      scanStatus: '',
      hasScanError: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            PlaylistSourceIcon(playlist: mixed),
            const PlatformSourceIcon(source: SourceID.valueBilibili),
          ],
        ),
      ),
    );
    expect(find.byIcon(AppIcons.mixed), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.bySemanticsLabel('混合歌单'), findsOneWidget);
    expect(find.bySemanticsLabel('来源：哔哩哔哩'), findsOneWidget);
  });
}
