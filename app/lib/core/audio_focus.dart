/// Serializes platform focus requests and releases. An abandoned pending
/// request must not let a stale load start playing when permission arrives.
class AudioFocusCoordinator {
  AudioFocusCoordinator(this.setActive);
  final Future<bool> Function(bool active) setActive;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _active = false;
  bool interrupted = false;

  Future<bool> acquire() {
    final generation = _generation;
    final result = _tail.then((_) async {
      if (generation != _generation || interrupted) return false;
      if (_active) return true;
      final bool granted;
      try {
        granted = await setActive(true);
      } catch (_) {
        return false;
      }
      if (generation != _generation || interrupted) {
        if (granted) await _abandon();
        return false;
      }
      _active = granted;
      return granted;
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> release() {
    // Preserve the platform's transient-loss subscription until gain arrives.
    if (interrupted) return Future<void>.value();
    _generation++;
    final result = _tail.then((_) async {
      if (_active) await _abandon();
      _active = false;
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _abandon() async {
    try {
      await setActive(false);
    } catch (_) {
      // A platform failure must not prevent the player from being disposed.
    }
  }

  Future<void> close() {
    interrupted = false;
    return release();
  }
}
