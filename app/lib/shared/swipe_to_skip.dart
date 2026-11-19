import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';

import '../features/session.dart';

typedef SwipeTrackBuilder =
    Widget Function(BuildContext context, SwipeTrackFrame frame);

/// Immutable snapshot handed to a [SwipeTrackBuilder].
///
/// [progress] is the carousel position: 0 is the current track, -1 means the
/// next cover has fully taken over the center and 1 means the previous cover
/// has. [entrance] runs from 0 to 1 right after a committed swipe so compact
/// layouts can fade the new track in; it is 1 while idle.
class SwipeTrackFrame {
  const SwipeTrackFrame({
    required this.current,
    required this.previous,
    required this.next,
    required this.progress,
    required this.entrance,
    required this.switchDirection,
    required this.dragging,
    required this.animating,
  });

  final Song? current;
  final Song? previous;
  final Song? next;
  final double progress;
  final double entrance;

  /// -1 when the last committed switch moved to the next track, 1 for the
  /// previous track, 0 when no switch has happened yet.
  final int switchDirection;
  final bool dragging;
  final bool animating;

  bool get canGoNext => next != null;
  bool get canGoPrevious => previous != null;
  double get magnitude => progress.abs().clamp(0.0, 1.0);
}

/// Tinder/NetEase style horizontal carousel for playback controls.
///
/// The current track follows the finger. A release commits only when the drag
/// covers [distanceThreshold] pixels or ends with a fling faster than
/// [velocityThreshold]; otherwise the card springs back. Both the commit and
/// the spring-back are spring simulations seeded with the release velocity, so
/// the card keeps the finger's speed instead of restarting on a fixed curve. A switch is only
/// possible when [SwipeTrackFrame.next]/[SwipeTrackFrame.previous] are known
/// (from the player queue), so the first/last track simply bounces.
///
/// While the core acknowledges the switch asynchronously the widget keeps
/// showing the optimistic target track, which prevents the old cover from
/// flashing back during the transition.
class SwipeToSkip extends ConsumerStatefulWidget {
  const SwipeToSkip({
    required this.builder,
    this.onNext,
    this.onPrevious,
    this.travelExtent,
    this.distanceThreshold = 72,
    this.velocityThreshold = 700,
    super.key,
  });

  final SwipeTrackBuilder builder;

  /// Called after the outgoing card has animated off screen.
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  /// Distance that maps to a full 0..1 carousel move. Defaults to the widget
  /// width; card layouts pass their cover travel so dragging stays 1:1.
  final double? travelExtent;
  final double distanceThreshold;
  final double velocityThreshold;

  @override
  ConsumerState<SwipeToSkip> createState() => _SwipeToSkipState();
}

class _PendingSwipe {
  const _PendingSwipe({
    required this.song,
    required this.index,
    required this.direction,
    required this.staleId,
  });

  final Song song;
  final int index;
  final int direction;
  final String? staleId;
}

class _SwipeToSkipState extends ConsumerState<SwipeToSkip>
    with TickerProviderStateMixin {
  // Critically damped for commits so the cover lands without overshooting
  // into the next slot; slightly underdamped for the spring-back.
  static final _commitSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 1,
  );
  static final _bounceSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 520,
    ratio: 0.78,
  );
  static const _tolerance = Tolerance(distance: 0.002, velocity: 0.02);

  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  late final Listenable _repaint = Listenable.merge([_slide, _entrance]);

  double _progress = 0;
  bool _dragging = false;
  double _dragDx = 0;
  double _dragDy = 0;
  int _switchDirection = 0;
  Song? _manualSong;
  int? _manualIndex;
  String? _staleSongId;
  _PendingSwipe? _pending;
  int? _pointer;
  final List<({Duration time, double x})> _samples = [];
  double _pointerVelocity = 0;

  @override
  void initState() {
    super.initState();
    _slide.addStatusListener(_onSlideStatus);
  }

  @override
  void dispose() {
    _slide.dispose();
    _entrance.dispose();
    super.dispose();
  }

  double get _shownProgress => _slide.isAnimating ? _slide.value : _progress;

  void _onSlideStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final pending = _pending;
    _pending = null;
    if (pending == null) {
      // A bounce finished: make sure the card is exactly at rest.
      setState(() => _progress = 0);
      return;
    }
    _staleSongId = pending.staleId;
    setState(() {
      _manualSong = pending.song;
      _manualIndex = pending.index;
      _progress = 0;
      _switchDirection = pending.direction;
    });
    // The incoming card is now the current one; fade it in for compact rows
    // that cannot show a full neighbour card behind it.
    _entrance.value = 0;
    _entrance.animateTo(1, curve: Curves.easeOutCubic);
    if (pending.direction < 0) {
      widget.onNext?.call();
    } else {
      widget.onPrevious?.call();
    }
  }

  void _onStart(DragStartDetails details) {
    final shown = _shownProgress;
    _slide.stop();
    _pending = null;
    _entrance.stop();
    _entrance.value = 1;
    _dragDx = 0;
    _dragDy = 0;
    _dragging = true;
    setState(() => _progress = shown.clamp(-1.1, 1.1));
  }

  void _onUpdate(DragUpdateDetails details, double travel) {
    if (travel <= 0) return;
    _dragDx += details.delta.dx;
    _dragDy += details.delta.dy;
    final resolved = _resolve(ref.read(playerProvider).snapshot);
    final towardsNext = details.delta.dx < 0;
    final hasTarget = towardsNext
        ? resolved.next != null
        : resolved.previous != null;
    // Rubber-band when there is nothing to switch to.
    final resistance = hasTarget ? 1.0 : 0.35;
    setState(() {
      _progress = (_progress + details.delta.dx / travel * resistance).clamp(
        -1.1,
        1.1,
      );
    });
  }

  void _onEnd(DragEndDetails details, double travel) {
    _dragging = false;
    final resolved = _resolve(ref.read(playerProvider).snapshot);
    // The drag recognizer occasionally reports a zero velocity for synthetic
    // flings; fall back to the raw pointer samples so a fast flick still wins.
    final reported = details.velocity.pixelsPerSecond.dx;
    final velocity = reported.abs() >= 1 ? reported : _pointerVelocity;
    final distancePx = _progress.abs() * travel;
    final horizontal = _dragDx.abs();
    final vertical = _dragDy.abs();
    final travelled =
        distancePx >= widget.distanceThreshold && horizontal >= vertical;
    final flung = velocity.abs() >= widget.velocityThreshold;

    var direction = 0;
    if (travelled && _progress != 0) {
      direction = _progress < 0 ? -1 : 1;
    } else if (flung) {
      direction = velocity < 0 ? -1 : 1;
    }

    if (direction != 0 && resolved.index >= 0) {
      final target = direction < 0 ? resolved.next : resolved.previous;
      final targetIndex = direction < 0
          ? resolved.index + 1
          : resolved.index - 1;
      if (target != null) {
        _pending = _PendingSwipe(
          song: target,
          index: targetIndex,
          direction: direction,
          staleId: resolved.song?.id,
        );
        _animateTo(
          direction < 0 ? -1.0 : 1.0,
          _commitSpring,
          velocity / travel,
        );
        return;
      }
    }

    _pending = null;
    _animateTo(0, _bounceSpring, velocity / travel);
  }

  void _onCancel() {
    if (!_dragging) return;
    _dragging = false;
    _pending = null;
    _animateTo(0, _bounceSpring, 0);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _samples
      ..clear()
      ..add((time: event.timeStamp, x: event.position.dx));
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _samples.add((time: event.timeStamp, x: event.position.dx));
    if (_samples.length > 8) _samples.removeAt(0);
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointerVelocity = _estimatePointerVelocity(event.timeStamp);
    _pointer = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointerVelocity = 0;
    _pointer = null;
  }

  double _estimatePointerVelocity(Duration upTime) {
    final samples = _samples
        .where(
          (sample) => upTime - sample.time <= const Duration(milliseconds: 100),
        )
        .toList();
    if (samples.length < 2) return 0;
    final last = samples.last;
    // A pointer that rested for a moment before lifting is not a fling.
    if (upTime - last.time > const Duration(milliseconds: 40)) return 0;
    final first = samples.first;
    final span = last.time - first.time;
    if (span <= Duration.zero) return 0;
    return (last.x - first.x) / (span.inMicroseconds / 1000000);
  }

  /// [velocity] is in carousel units per second (1 = one full slot).
  void _animateTo(double target, SpringDescription spring, double velocity) {
    final from = _shownProgress;
    _slide.stop();
    _slide.value = from;
    _slide.animateWith(
      SpringSimulation(
        spring,
        from,
        target,
        velocity.clamp(-12.0, 12.0),
        tolerance: _tolerance,
      ),
    );
    setState(() {});
  }

  /// Resolve the current track and its queue neighbours, preferring the
  /// optimistic target while the core is still reporting the previous track.
  ({Song? song, int index, Song? previous, Song? next}) _resolve(
    PlaybackSnapshot snapshot,
  ) {
    final queue = snapshot.queue;
    Song? song = snapshot.current;
    var index = snapshot.index;
    final manual = _manualSong;
    if (manual != null) {
      final providerId = snapshot.current?.id;
      if (providerId == manual.id) {
        // Core caught up; drop the optimistic override.
        _manualSong = null;
        _manualIndex = null;
      } else if (providerId == null || providerId != _staleSongId) {
        // Something else changed playback; trust the core again.
        _manualSong = null;
        _manualIndex = null;
      } else {
        song = manual;
        final found = queue.indexWhere((item) => item.id == manual.id);
        if (found >= 0) {
          index = found;
        } else if (_manualIndex != null &&
            _manualIndex! >= 0 &&
            _manualIndex! < queue.length) {
          index = _manualIndex!;
        } else {
          _manualSong = null;
          _manualIndex = null;
        }
      }
    }
    if (song == null && index >= 0 && index < queue.length) {
      song = queue[index];
    }
    final valid =
        song != null &&
        index >= 0 &&
        index < queue.length &&
        queue[index].id == song.id;
    final previous = valid && index > 0 ? queue[index - 1] : null;
    final next = valid && index + 1 < queue.length ? queue[index + 1] : null;
    return (
      song: song,
      index: valid ? index : -1,
      previous: previous,
      next: next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve(ref.watch(playerProvider).snapshot);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final travel = (widget.travelExtent ?? width)
            .clamp(1.0, 1e6)
            .toDouble();
        return AnimatedBuilder(
          animation: _repaint,
          builder: (context, _) {
            final frame = SwipeTrackFrame(
              current: resolved.song,
              previous: resolved.previous,
              next: resolved.next,
              progress: _shownProgress,
              entrance: _entrance.value.clamp(0.0, 1.0),
              switchDirection: _switchDirection,
              dragging: _dragging,
              animating: _slide.isAnimating || _entrance.isAnimating,
            );
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onStart,
                onHorizontalDragUpdate: (details) => _onUpdate(details, travel),
                onHorizontalDragEnd: (details) => _onEnd(details, travel),
                onHorizontalDragCancel: _onCancel,
                child: widget.builder(context, frame),
              ),
            );
          },
        );
      },
    );
  }
}
