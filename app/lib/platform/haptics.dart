import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' as platform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef HapticTrigger = Future<void> Function();
typedef HapticClock = DateTime Function();

/// Thin, injectable wrapper around the platform haptic channel.
///
/// Widget tests override [hapticFeedbackProvider] with a fake trigger instead
/// of touching the real platform channel.
class HapticFeedback {
  HapticFeedback({HapticTrigger? trigger})
    : _trigger = trigger ?? _platformSelectionClick;

  /// Native Android fallback. `HapticFeedback.selectionClick()` goes through
  /// `View.performHapticFeedback`, which MIUI silences when its system touch
  /// feedback switch is off. The native channel uses the vibrator directly.
  static const platform.MethodChannel androidChannel = platform.MethodChannel(
    'zero_beat/haptics',
  );

  final HapticTrigger _trigger;

  /// A short, subtle tick suitable for confirming a button tap.
  Future<void> selectionClick() async {
    try {
      await _trigger();
    } catch (_) {
      // Haptics are best-effort; unsupported devices must not break input.
    }
  }

  static Future<void> _platformSelectionClick() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final handled = await androidChannel.invokeMethod<bool>(
          'selectionClick',
        );
        if (handled == true) return;
        // Native side found no usable vibrator: use the platform channel.
      } catch (_) {
        // Older builds without the native handler or a transient channel
        // failure still get the standard Flutter haptic path.
      }
    }
    await platform.HapticFeedback.selectionClick();
  }
}

final hapticFeedbackProvider = Provider<HapticFeedback>(
  (ref) => HapticFeedback(),
);

/// Fires a haptic tick only for deliberate, short taps.
///
/// The listener uses pointer distance and duration so scroll, drag, progress
/// slider and long-press gestures never trigger a tick. It is installed at the
/// app root so every button gets the same behavior without per-widget wiring.
class HapticTapListener extends ConsumerStatefulWidget {
  const HapticTapListener({
    required this.enabled,
    required this.child,
    this.clock,
    super.key,
  });

  final bool enabled;
  final Widget child;

  /// Injectable clock for deterministic gesture-duration tests.
  final HapticClock? clock;

  static const double maxTapDistance = 18;
  static const Duration maxTapDuration = Duration(milliseconds: 400);

  @override
  ConsumerState<HapticTapListener> createState() => _HapticTapListenerState();
}

class _HapticTapListenerState extends ConsumerState<HapticTapListener> {
  int? _pointer;
  Offset? _downPosition;
  DateTime? _downAt;
  bool _moved = false;
  bool _multiTouch = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    // Android touch pointers report buttons == 0 (only mice report the
    // primary button bit). Reject right/middle clicks, but accept touch.
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    if (_pointer != null) {
      // A second finger means pinch/zoom, not a button tap.
      _multiTouch = true;
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    _downAt = _now();
    _moved = false;
    _multiTouch = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer || _moved) return;
    final origin = _downPosition;
    if (origin == null) return;
    if ((event.position - origin).distance > HapticTapListener.maxTapDistance) {
      _moved = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    final downAt = _downAt;
    final shouldTap =
        widget.enabled &&
        !_moved &&
        !_multiTouch &&
        downAt != null &&
        _now().difference(downAt) <= HapticTapListener.maxTapDuration;
    _reset();
    if (shouldTap) {
      unawaited(ref.read(hapticFeedbackProvider).selectionClick());
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_pointer == event.pointer) _reset();
  }

  void _reset() {
    _pointer = null;
    _downPosition = null;
    _downAt = null;
    _moved = false;
    _multiTouch = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onPointerDown,
    onPointerMove: _onPointerMove,
    onPointerUp: _onPointerUp,
    onPointerCancel: _onPointerCancel,
    child: widget.child,
  );
}
