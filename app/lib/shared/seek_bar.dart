import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'playback.dart';

class SeekBar extends StatefulWidget {
  const SeekBar({
    required this.positionMs,
    required this.durationMs,
    required this.onSeek,
    super.key,
  });

  final int positionMs;
  final int durationMs;
  final ValueChanged<int> onSeek;

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
    return Row(
      children: [
        Text(
          formatClock(shown.round()),
          style: TextStyle(color: context.zero.muted, fontSize: 12),
        ),
        Expanded(
          child: Slider(
            value: shown.toDouble(),
            max: duration.toDouble(),
            activeColor: context.zero.accent,
            inactiveColor: context.zero.line,
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
          ),
        ),
        Text(
          formatClock(widget.durationMs),
          style: TextStyle(color: context.zero.muted, fontSize: 12),
        ),
      ],
    );
  }
}
