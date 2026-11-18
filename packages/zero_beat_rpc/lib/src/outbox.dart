/// Bounded outbound NDJSON queue. Position frames coalesce. A reliable frame
/// that does not fit marks [overflowed] instead of being dropped quietly.
class OutboundFrame {
  OutboundFrame(
    this.payload, {
    this.position = false,
    this.terminal = false,
    this.playbackId = '',
    this.seq = 0,
  });

  final String payload;
  final bool position;
  final bool terminal;
  final String playbackId;
  final int seq;
}

class FrameOutbox {
  FrameOutbox({this.limit = 64});

  final int limit;
  final List<OutboundFrame> items = [];
  bool overflowed = false;

  bool add(OutboundFrame frame) {
    if (overflowed) return false;
    if (frame.position) {
      for (var i = items.length - 1; i >= 0; i--) {
        final prev = items[i];
        if (prev.playbackId != frame.playbackId) continue;
        if (prev.terminal) return true;
        if (prev.position) {
          if (frame.seq >= prev.seq) items[i] = frame;
          return true;
        }
        break;
      }
    }
    if (frame.terminal) {
      for (final prev in items) {
        if (prev.terminal && prev.playbackId == frame.playbackId) return true;
      }
    }
    if (items.length >= limit) {
      if (frame.position) return true;
      overflowed = true;
      return false;
    }
    items.add(frame);
    return true;
  }

  OutboundFrame? pop() {
    if (items.isEmpty) return null;
    return items.removeAt(0);
  }
}
