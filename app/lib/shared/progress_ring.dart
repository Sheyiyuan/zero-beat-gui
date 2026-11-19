import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// A circular playback progress ring drawn around a control.
///
/// The ring is painted inside a square of [size] and never affects layout, so
/// it can wrap an existing 48px control such as the play/pause button without
/// moving it. When [progress] is null (no known duration) nothing is painted.
class PlayProgressRing extends StatelessWidget {
  const PlayProgressRing({
    required this.progress,
    this.size = 48,
    this.strokeWidth = 3,
    super.key,
  });

  /// Playback progress in the range 0..1, or null when there is no duration.
  final double? progress;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    return SizedBox.square(
      dimension: size,
      child: value == null
          ? null
          : CustomPaint(
              size: Size.square(size),
              painter: _PlayProgressRingPainter(
                progress: value.clamp(0.0, 1.0),
                track: context.zero.line,
                accent: context.zero.accent,
                strokeWidth: strokeWidth,
              ),
            ),
    );
  }
}

class _PlayProgressRingPainter extends CustomPainter {
  const _PlayProgressRingPainter({
    required this.progress,
    required this.track,
    required this.accent,
    required this.strokeWidth,
  });

  final double progress;
  final Color track;
  final Color accent;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        paint..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlayProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.accent != accent ||
      oldDelegate.strokeWidth != strokeWidth;
}
