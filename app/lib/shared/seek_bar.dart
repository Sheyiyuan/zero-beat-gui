import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'playback.dart';

class SeekBar extends StatefulWidget {
  const SeekBar({
    required this.positionMs,
    required this.durationMs,
    required this.onSeek,
    this.stacked = false,
    super.key,
  });

  final int positionMs;
  final int durationMs;
  final ValueChanged<int> onSeek;

  /// Put the elapsed/total labels under a full-width track instead of beside
  /// it. Used by the now-playing page where the bar spans the column.
  final bool stacked;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final duration = widget.durationMs <= 0 ? 1 : widget.durationMs;
    final shown = (_drag ?? widget.positionMs.toDouble()).clamp(
      0,
      duration.toDouble(),
    );
    final labelStyle = TextStyle(
      color: context.zero.muted,
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final slider = Slider(
      padding: widget.stacked
          ? const EdgeInsets.symmetric(horizontal: 2, vertical: 12)
          : null,
      value: shown.toDouble(),
      max: duration.toDouble(),
      label: formatClock(shown.round()),
      onChanged: widget.durationMs <= 0
          ? null
          : (value) => setState(() => _drag = value),
      onChangeEnd: widget.durationMs <= 0
          ? null
          : (value) {
              setState(() => _drag = null);
              widget.onSeek(value.round());
            },
    );
    final elapsed = Text(formatClock(shown.round()), style: labelStyle);
    final total = Text(formatClock(widget.durationMs), style: labelStyle);
    if (widget.stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          slider,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [elapsed, total],
          ),
        ],
      );
    }
    return Row(
      children: [
        elapsed,
        Expanded(child: slider),
        total,
      ],
    );
  }
}
