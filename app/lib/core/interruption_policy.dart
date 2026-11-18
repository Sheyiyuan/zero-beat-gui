/// Decides whether an audio interruption may resume playback.
///
/// Resume only when the interruption is temporary, playback was active before
/// it began, and the user did not pause, skip, or seek in between.
class InterruptionPolicy {
  void Function()? onUserTransport;
  bool wasActive = false;
  bool userIntervened = false;

  void noteUserTransport() {
    userIntervened = true;
    onUserTransport?.call();
  }

  /// Headset unplug stays paused and cancels a pending temporary resume.
  void blockResume() {
    wasActive = false;
    userIntervened = true;
    onUserTransport?.call();
  }

  void onBegin({required bool active}) {
    wasActive = active;
    userIntervened = false;
  }

  bool shouldResume({required bool temporary}) {
    final resume = temporary && wasActive && !userIntervened;
    wasActive = false;
    return resume;
  }
}
