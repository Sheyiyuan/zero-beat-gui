/// TUI loudnorm target: I=-16, TP=-1.5, LRA=11.
const String kLoudnormFilter = 'loudnorm=I=-16:TP=-1.5:LRA=11';

const String kLimiterFilter =
    'alimiter=limit=0.95:attack=5:release=50:level=disabled';

String compensationFilter(double compDb) =>
    'volume=${compDb.toStringAsFixed(3)}dB,$kLimiterFilter';

String playbackFilter({required bool loudnorm, required double compDb}) {
  final parts = <String>[
    if (loudnorm) kLoudnormFilter,
    if (compDb != 0) 'volume=${compDb.toStringAsFixed(3)}dB',
    if (compDb != 0 || loudnorm) kLimiterFilter,
  ];
  return parts.join(',');
}
