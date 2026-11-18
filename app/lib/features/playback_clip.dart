import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/providers.dart';
import '../engine/playback_host.dart';
import 'session.dart';

/// Clip range shown in mini player / continue row for the current song.
class DisplayedClip {
  const DisplayedClip({
    required this.songId,
    required this.startMs,
    required this.endMs,
  });

  final String songId;
  final int startMs;
  final int endMs;

  bool get active => startMs > 0 || endMs > 0;
}

class ClipUiOverride {
  const ClipUiOverride({
    required this.songId,
    required this.startMs,
    required this.endMs,
  });

  final String songId;
  final int startMs;
  final int endMs;
}

class ClipUiOverrideController extends Notifier<ClipUiOverride?> {
  @override
  ClipUiOverride? build() => null;

  void set(String songId, int startMs, int endMs) {
    state = ClipUiOverride(songId: songId, startMs: startMs, endMs: endMs);
  }

  void clearUnless(String? songId) {
    if (state == null) return;
    if (songId == null || state!.songId != songId) state = null;
  }
}

final clipUiOverrideProvider =
    NotifierProvider<ClipUiOverrideController, ClipUiOverride?>(
      ClipUiOverrideController.new,
    );

DisplayedClip? resolveDisplayedClip({
  required PlayerView player,
  required PlaybackHost? host,
  required ClipUiOverride? override,
  String? hostClipSongId,
}) {
  final song = player.snapshot.current;
  if (song == null) return null;
  var startMs = 0;
  var endMs = 0;
  final playbackId = player.playbackId;
  if (host != null &&
      playbackId != null &&
      playbackId.isNotEmpty &&
      host.activePlaybackId == playbackId &&
      hostClipSongId == song.id) {
    startMs = host.activeClipStartMs;
    endMs = host.activeClipEndMs;
  }
  if (override != null && override.songId == song.id) {
    startMs = override.startMs;
    endMs = override.endMs;
  }
  if (startMs <= 0 && endMs <= 0) return null;
  return DisplayedClip(songId: song.id, startMs: startMs, endMs: endMs);
}

class DisplayedClipController extends Notifier<DisplayedClip?> {
  PlaybackHost? _host;
  void Function()? _hostListener;
  String? _hostClipSongId;

  DisplayedClip? _resolve() {
    return resolveDisplayedClip(
      player: ref.read(playerProvider),
      host: _host,
      override: ref.read(clipUiOverrideProvider),
      hostClipSongId: _hostClipSongId,
    );
  }

  void _bindHostClipToCurrentSong() {
    final songId = ref.read(playerProvider).snapshot.current?.id;
    if (songId == null || songId.isEmpty) {
      _hostClipSongId = null;
      return;
    }
    _hostClipSongId = songId;
  }

  @override
  DisplayedClip? build() {
    _attachHost(ref.watch(playbackHostProvider));
    ref.listen(playerProvider, (previous, next) {
      final prevId = previous?.snapshot.current?.id;
      final id = next.snapshot.current?.id;
      ref.read(clipUiOverrideProvider.notifier).clearUnless(id);
      if (prevId != id) _hostClipSongId = null;
      state = resolveDisplayedClip(
        player: next,
        host: _host,
        override: ref.read(clipUiOverrideProvider),
        hostClipSongId: _hostClipSongId,
      );
    });
    ref.listen(clipUiOverrideProvider, (_, next) {
      state = resolveDisplayedClip(
        player: ref.read(playerProvider),
        host: _host,
        override: next,
        hostClipSongId: _hostClipSongId,
      );
    });
    return _resolve();
  }

  void _attachHost(PlaybackHost? host) {
    if (identical(_host, host)) return;
    if (_host != null && _hostListener != null) {
      _host!.removeListener(_hostListener!);
    }
    _host = host;
    if (host == null) return;
    _hostListener = () {
      _bindHostClipToCurrentSong();
      state = _resolve();
    };
    host.addListener(_hostListener!);
    ref.onDispose(() {
      if (_hostListener != null) host.removeListener(_hostListener!);
    });
  }

  void afterClipEdit({
    required String songId,
    required String action,
    required int startMs,
    required int endMs,
  }) {
    final player = ref.read(playerProvider);
    if (player.snapshot.current?.id != songId) return;
    if (action == 'save' || action == 'preview' || action == 'clear') {
      final nextStart = action == 'clear' ? 0 : startMs;
      final nextEnd = action == 'clear' ? 0 : endMs;
      ref.read(clipUiOverrideProvider.notifier).set(songId, nextStart, nextEnd);
      ref
          .read(playbackHostProvider)
          ?.applyClipBounds(startMs: nextStart, endMs: nextEnd);
      _hostClipSongId = songId;
      state = _resolve();
    }
  }
}

final displayedClipProvider =
    NotifierProvider<DisplayedClipController, DisplayedClip?>(
      DisplayedClipController.new,
    );
