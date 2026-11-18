import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/core/audio_focus.dart';
import 'package:zero_beat_gui/core/interruption_policy.dart';

void main() {
  test('focus is acquired once and released on stop', () async {
    final calls = <bool>[];
    final focus = AudioFocusCoordinator((active) async {
      calls.add(active);
      return true;
    });
    expect(await focus.acquire(), isTrue);
    expect(await focus.acquire(), isTrue);
    await focus.close();
    expect(calls, [true, false]);
  });
  test('late focus grant is abandoned after user pause', () async {
    final gate = Completer<bool>();
    final calls = <bool>[];
    final focus = AudioFocusCoordinator((active) async {
      calls.add(active);
      return active ? gate.future : true;
    });
    final pending = focus.acquire();
    await Future<void>.delayed(Duration.zero);
    final release = focus.release();
    gate.complete(true);
    expect(await pending, isFalse);
    await release;
    expect(calls, [true, false]);
  });
  test(
    'transient interruption keeps subscription until gain or shutdown',
    () async {
      final calls = <bool>[];
      final focus = AudioFocusCoordinator((active) async {
        calls.add(active);
        return true;
      });
      await focus.acquire();
      focus.interrupted = true;
      await focus.release();
      expect(await focus.acquire(), isFalse);
      expect(calls, [true]);
      await focus.close();
      expect(calls, [true, false]);
    },
  );
  test('platform focus errors are refusal, not playback failure', () async {
    final focus = AudioFocusCoordinator(
      (_) async => throw StateError('platform'),
    );
    expect(await focus.acquire(), isFalse);
    await focus.close();
  });
  test('only uninterrupted temporary loss may resume', () {
    final policy = InterruptionPolicy();
    policy.onBegin(active: true);
    expect(policy.shouldResume(temporary: true), isTrue);
    policy.onBegin(active: true);
    policy.noteUserTransport();
    expect(policy.shouldResume(temporary: true), isFalse);
    policy.onBegin(active: true);
    policy.blockResume();
    expect(policy.shouldResume(temporary: true), isFalse);
    policy.onBegin(active: true);
    expect(policy.shouldResume(temporary: false), isFalse);
  });
}
