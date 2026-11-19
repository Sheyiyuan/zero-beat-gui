import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/features/settings_page.dart';
import 'package:zero_beat_gui/platform/haptics.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';

class HapticFeatureApi extends FakeCoreApi implements CoreFeatureTransport {
  final updates = StreamController<String>.broadcast();
  final saves = <GUISettings>[];
  GUISettings preferences = defaultGUISettings();

  @override
  Stream<String> get changes => updates.stream;

  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'settings.gui.get':
        return preferences.toJson();
      case 'settings.gui.set':
        final next = GUISettings.fromJson(
          Map<String, Object?>.from(params['settings'] as Map),
        );
        saves.add(next);
        preferences = next;
        return {};
      case 'settings.get':
        return Preferences(
          volume: 0.8,
          compDb: 0,
          autoGain: false,
          quality: Quality.valueAuto,
          mode: PlaybackMode.valueOrdered,
          playingPlaylist: '',
          localFirst: false,
          mouse: false,
        ).toJson();
      default:
        throw UnsupportedError(method);
    }
  }

  @override
  Future<void> closeControllers() async {
    await updates.close();
    await super.closeControllers();
  }
}

void main() {
  testWidgets('button taps vibrate by default, stop when disabled, resume', (
    tester,
  ) async {
    final api = HapticFeatureApi();
    addTearDown(api.closeControllers);
    var ticks = 0;
    final haptics = HapticFeedback(
      trigger: () async {
        ticks += 1;
      },
    );
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.desktop,
      overrides: [hapticFeedbackProvider.overrideWithValue(haptics)],
    );

    expect(defaultGUISettings().haptics, isTrue);
    await tester.tap(find.byKey(const Key('play-pause')));
    await tester.pump();
    expect(ticks, 1);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('触摸振动'), findsOneWidget);
    expect(find.byKey(const Key('haptics-switch')), findsOneWidget);

    await tester.tap(find.byKey(const Key('haptics-switch')));
    await tester.pumpAndSettle();
    expect(api.preferences.haptics, isFalse);
    expect(api.saves, isNotEmpty);
    expect(api.saves.last.haptics, isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();
    ticks = 0;
    await tester.tap(find.byKey(const Key('play-pause')));
    await tester.pump();
    expect(ticks, 0);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('haptics-switch')));
    await tester.pumpAndSettle();
    expect(api.preferences.haptics, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    ticks = 0;
    await tester.tap(find.byKey(const Key('play-pause')));
    await tester.pump();
    expect(ticks, 1);
  });

  testWidgets('touch pointers with zero buttons still trigger haptics', (
    tester,
  ) async {
    var ticks = 0;
    final haptics = HapticFeedback(
      trigger: () async {
        ticks += 1;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hapticFeedbackProvider.overrideWithValue(haptics)],
        child: const HapticTapListener(enabled: true, child: SizedBox.expand()),
      ),
    );
    final gesture = await tester.startGesture(
      const Offset(120, 120),
      buttons: 0,
    );
    await gesture.up();
    await tester.pump();
    expect(ticks, 1);
  });

  testWidgets('drag, long press and multi-touch do not trigger haptics', (
    tester,
  ) async {
    var ticks = 0;
    var now = DateTime(2026);
    final haptics = HapticFeedback(
      trigger: () async {
        ticks += 1;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hapticFeedbackProvider.overrideWithValue(haptics)],
        child: HapticTapListener(
          enabled: true,
          clock: () => now,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.tapAt(const Offset(120, 120));
    await tester.pump();
    expect(ticks, 1);

    final drag = await tester.startGesture(const Offset(120, 120));
    await drag.moveBy(const Offset(40, 0));
    await drag.up();
    await tester.pump();
    expect(ticks, 1);

    final longPress = await tester.startGesture(const Offset(120, 120));
    now = now.add(const Duration(milliseconds: 900));
    await longPress.up();
    await tester.pump();
    expect(ticks, 1);

    final first = await tester.startGesture(const Offset(100, 120));
    final second = await tester.startGesture(const Offset(160, 120));
    await first.up();
    await second.up();
    await tester.pump();
    expect(ticks, 1);
  });

  testWidgets('disabled listener never triggers', (tester) async {
    var ticks = 0;
    final haptics = HapticFeedback(
      trigger: () async {
        ticks += 1;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hapticFeedbackProvider.overrideWithValue(haptics)],
        child: const HapticTapListener(
          enabled: false,
          child: SizedBox.expand(),
        ),
      ),
    );
    await tester.tapAt(const Offset(120, 120));
    await tester.pump();
    expect(ticks, 0);
  });

  group('Android native vibrator fallback', () {
    late List<services.MethodCall> calls;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HapticFeedback.androidChannel, (
            call,
          ) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HapticFeedback.androidChannel, null);
    });

    test('selectionClick uses the native vibrator channel once', () async {
      await HapticFeedback().selectionClick();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'selectionClick');
    });

    testWidgets(
      'one quick tap sends one native tick, disabled taps send none',
      (tester) async {
        try {
          await tester.pumpWidget(
            ProviderScope(
              child: const HapticTapListener(
                enabled: true,
                child: SizedBox.expand(),
              ),
            ),
          );
          await tester.tapAt(const Offset(120, 120));
          await tester.pump();
          expect(calls, hasLength(1));
          expect(calls.single.method, 'selectionClick');

          await tester.pumpWidget(
            ProviderScope(
              child: const HapticTapListener(
                enabled: false,
                child: SizedBox.expand(),
              ),
            ),
          );
          await tester.tapAt(const Offset(120, 120));
          await tester.pump();
          expect(calls, hasLength(1));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  test('non-Android keeps using the Flutter haptic channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final calls = <services.MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(services.SystemChannels.platform, (
          call,
        ) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(services.SystemChannels.platform, null);
    });

    await HapticFeedback().selectionClick();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'HapticFeedback.vibrate');
    expect(calls.single.arguments, 'HapticFeedbackType.selectionClick');
  });

  test('Android channel failure falls back to the Flutter channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <services.MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(services.SystemChannels.platform, (
          call,
        ) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(services.SystemChannels.platform, null);
    });

    // No mock handler for HapticFeedback.androidChannel on purpose.
    await HapticFeedback().selectionClick();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'HapticFeedback.vibrate');
  });
}
