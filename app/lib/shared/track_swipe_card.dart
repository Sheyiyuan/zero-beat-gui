import 'package:flutter/material.dart';

import 'swipe_to_skip.dart';

/// Builds one cover for a swipe card; [size] is the square edge length.
typedef TrackCoverBuilder =
    Widget Function(BuildContext context, String cover, double size);

/// Full-bleed cover carousel used by the now-playing screen.
///
/// The current cover follows [SwipeTrackFrame.progress] and the neighbouring
/// covers slide in beside it, scaling up as they reach the centre. Keys `now-playing-current-cover`, `now-playing-next-cover` and
/// `now-playing-previous-cover` are stable for widget tests; the nested
/// `now-playing-cover-<id>` key identifies which track is currently shown.
class TrackSwipeCard extends StatelessWidget {
  const TrackSwipeCard({
    required this.frame,
    required this.size,
    required this.coverBuilder,
    this.gap = 16,
    super.key,
  });

  final SwipeTrackFrame frame;
  final double size;
  final TrackCoverBuilder coverBuilder;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final progress = frame.progress.clamp(-1.0, 1.0);
          final magnitude = progress.abs();
          // Covers stay opaque and slide as one strip, like a physical
          // carousel. The outgoing cover recedes a little and the incoming one
          // grows into place; neighbours only become visible once a drag
          // starts so they never peek at the screen edge while idle.
          final base = (constraints.maxWidth - size) / 2;
          final left = base + progress * (size + gap);
          final reveal = Curves.easeOut.transform((magnitude * 3).clamp(0, 1));
          final neighborScale = 0.92 + 0.08 * magnitude;
          final currentScale = 1 - 0.08 * magnitude;
          final currentOpacity = 1 - 0.35 * magnitude;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (frame.previous != null)
                _cover(
                  key: const Key('now-playing-previous-cover'),
                  trackKey: ValueKey('now-playing-cover-${frame.previous!.id}'),
                  left: left - size - gap,
                  size: size,
                  opacity: progress > 0 ? reveal : 0,
                  scale: neighborScale,
                  child: coverBuilder(context, frame.previous!.cover, size),
                ),
              if (frame.next != null)
                _cover(
                  key: const Key('now-playing-next-cover'),
                  trackKey: ValueKey('now-playing-cover-${frame.next!.id}'),
                  left: left + size + gap,
                  size: size,
                  opacity: progress < 0 ? reveal : 0,
                  scale: neighborScale,
                  child: coverBuilder(context, frame.next!.cover, size),
                ),
              _cover(
                key: const Key('now-playing-current-cover'),
                trackKey: ValueKey(
                  'now-playing-cover-${frame.current?.id ?? ''}',
                ),
                left: left,
                size: size,
                opacity: currentOpacity,
                scale: currentScale,
                child: coverBuilder(context, frame.current?.cover ?? '', size),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cover({
    required Key key,
    required Key trackKey,
    required double left,
    required double size,
    required double opacity,
    required double scale,
    required Widget child,
  }) {
    return Positioned(
      left: left,
      top: 0,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: KeyedSubtree(
              key: key,
              child: KeyedSubtree(key: trackKey, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
