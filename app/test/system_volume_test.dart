import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/icons.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/core/android_core_volume.dart';
import 'package:zero_beat_gui/shared/playback.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/fake_core.dart';
import 'support/fake_system_volume.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

/// Records core settings writes so the test can prove the system-volume row
/// never falls through to the core's persisted `volume`/`mute` settings.
class _VolumeCoreApi extends FakeCoreApi implements CoreFeatureTransport {
  _VolumeCoreApi({super.view});

  final settings = <(String, num)>[];

  @override
  Stream<String> get changes => const Stream.empty();

  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) async {
    if (method == 'settings.set') {
      settings.add((params['key']! as String, params['value']! as num));
    }
    return const <String, Object?>{};
  }
}

Future<void> _openFullPlayer(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-player')));
  await tester.pumpAndSettle();
}

HelloResult _helloWithVolume(double volume) {
  final base = sampleHello();
  return HelloResult(
    api: base.api,
    repo: base.repo,
    coreVersion: base.coreVersion,
    guiVersion: base.guiVersion,
    dataDir: base.dataDir,
    capabilities: base.capabilities,
    accounts: base.accounts,
    player: playerView(volume: volume),
  );
}

void main() {
  test('android startup aligns the persisted core volume to unity', () async {
    final api = FakeCoreApi(view: playerView(volume: 0.55));
    addTearDown(api.closeControllers);
    await alignAndroidCoreVolume(api);
    expect(api.volumes, [1.0]);
  });

  test('android startup leaves an already-unity core volume alone', () async {
    final api = FakeCoreApi();
    api.helloResult = _helloWithVolume(1.0);
    addTearDown(api.closeControllers);
    await alignAndroidCoreVolume(api);
    expect(api.volumes, isEmpty);
  });

  testWidgets('android volume slider reads/writes STREAM_MUSIC, not core', (
    tester,
  ) async {
    final song = sampleSong();
    final api = _VolumeCoreApi(
      view: playerView(current: song, volume: 0.8, durationMs: song.durationMs),
    );
    addTearDown(api.closeControllers);
    final system = FakeSystemVolume(volume: 5, max: 100);
    addTearDown(system.dispose);

    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
      systemVolume: system,
    );
    await _openFullPlayer(tester);

    expect(system.listeners, 1);
    expect(find.text('5%'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('volume-slider')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();

    expect(system.writes, isNotEmpty);
    expect(system.writes.last, greaterThan(5));
    expect(api.volumes, isEmpty);
    expect(api.settings, isEmpty);
    expect(find.text('5%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hardware volume changes refresh and mute restores volume', (
    tester,
  ) async {
    final song = sampleSong();
    final api = _VolumeCoreApi(
      view: playerView(current: song, volume: 0.8, durationMs: song.durationMs),
    );
    addTearDown(api.closeControllers);
    final system = FakeSystemVolume(volume: 8, max: 20);
    addTearDown(system.dispose);

    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
      systemVolume: system,
    );
    await _openFullPlayer(tester);

    expect(find.text('40%'), findsOneWidget);

    // A hardware volume key / another app changes the stream directly.
    system.emit(12);
    await tester.pumpAndSettle();
    expect(find.text('60%'), findsOneWidget);
    expect(api.volumes, isEmpty);

    await tester.tap(find.byKey(const Key('volume-mute')));
    await tester.pumpAndSettle();
    expect(system.writes.last, 0);
    expect(system.state.volume, 0);
    expect(find.text('静音'), findsOneWidget);
    expect(find.byIcon(AppIcons.volumeOff), findsOneWidget);

    await tester.tap(find.byKey(const Key('volume-mute')));
    await tester.pumpAndSettle();
    expect(system.writes.last, 12);
    expect(find.text('60%'), findsOneWidget);
    expect(find.byIcon(AppIcons.volume), findsOneWidget);

    expect(api.volumes, isEmpty);
    expect(api.settings, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system volume listener stops when the player page is disposed', (
    tester,
  ) async {
    final api = FakeCoreApi(
      view: playerView(
        current: sampleSong(),
        durationMs: sampleSong().durationMs,
      ),
    );
    addTearDown(api.closeControllers);
    final system = FakeSystemVolume();
    addTearDown(system.dispose);

    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(430, 900),
      systemVolume: system,
    );
    expect(system.listeners, 0);
    await _openFullPlayer(tester);
    expect(system.listeners, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(system.listeners, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop volume slider still writes the core volume', (
    tester,
  ) async {
    final api = FakeCoreApi(
      view: playerView(current: sampleSong(), volume: 0.05),
    );
    addTearDown(api.closeControllers);
    await pumpApp(tester, api: api, layout: AppLayout.desktop);

    await tester.drag(
      find.byKey(const Key('volume-slider')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();

    expect(api.volumes, isNotEmpty);
    expect(api.volumes.last, greaterThan(0.05));
    expect(tester.takeException(), isNull);
  });
}
