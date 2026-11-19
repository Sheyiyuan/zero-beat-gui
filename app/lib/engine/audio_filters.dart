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

/// mpv rejects an unknown `af` entry and leaves the option unchanged.
/// `setProperty("af")` logs `Option af: …`; the `af set` command logs
/// `Option af-set: …`. Android libmpv ships almost no audio filters, so
/// `volume` and `alimiter` hit this path; compensation then uses the volume
/// property.
bool isUnsupportedAudioFilterError(String message) {
  final text = message.trim();
  return text.startsWith('Option af:') || text.startsWith('Option af-');
}
