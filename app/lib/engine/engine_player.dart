/// Platform player used by the playback host. Tests supply a fake.
abstract class EnginePlayer {
  Future<void> open({
    required String url,
    required Map<String, String> headers,
    Duration? start,
    Duration? end,
    required bool play,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double percent);

  /// Returns whether the filter is actually active on this player.
  Future<bool> trySetFilter(String filter);

  void listen(EnginePlayerListener listener);

  Future<void> dispose();
}

class EnginePlayerListener {
  const EnginePlayerListener({
    required this.onPosition,
    required this.onPlaying,
    required this.onBuffering,
    required this.onCompleted,
    required this.onError,
  });

  final void Function(Duration position, Duration duration) onPosition;
  final void Function(bool playing) onPlaying;
  final void Function(bool buffering) onBuffering;
  final void Function() onCompleted;
  final void Function(String message) onError;
}
