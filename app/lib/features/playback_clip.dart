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
    required this.playbackId,
    required this.startMs,
    required this.endMs,
  });

  final String songId;

  /// Playback the edit was applied to. A later load mints a new id.
  final String? playbackId;
  final int startMs;
  final int endMs;
}

class ClipUiOverrideController extends Notifier<ClipUiOverride?> {
  @override
  ClipUiOverride? build() => null;

  void set(String songId, String? playbackId, int startMs, int endMs) {
    state = ClipUiOverride(
      songId: songId,
      playbackId: playbackId,
      startMs: startMs,
      endMs: endMs,
    );
  }

  void restore(ClipUiOverride? previous) {
    state = previous;
  }

  /// Drops an override that belongs to another song or playback.
  void retainOnly({required String? songId, required String? playbackId}) {
    final current = state;
    if (current == null) return;
    if (songId == null ||
        current.songId != songId ||
        current.playbackId != playbackId) {
      state = null;
    }
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
  if (override != null &&
      override.songId == song.id &&
      override.playbackId == playbackId) {
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
      final playbackChanged = previous?.playbackId != next.playbackId;
      if (prevId != id || playbackChanged) {
        ref
            .read(clipUiOverrideProvider.notifier)
            .retainOnly(songId: id, playbackId: next.playbackId);
      }
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
    // Load may already have completed. Bind the current song without waiting
    // for the next host tick, and without writing provider state during build.
    _bindHostClipToCurrentSong();
    ref.onDispose(() {
      if (_hostListener != null) host.removeListener(_hostListener!);
    });
  }

  /// Applies a clip edit to the subtitle for [playbackId] only.
  ///
  /// Returns false when the snapshot or the live host binding is no longer
  /// that playback. Core save, clear, preview, and cancel each call
  /// `startPlay`, which stops the old id and later `engine.load`s a new one.
  /// That load is what updates [PlaybackHost] clip bounds and `open(end:)`
  /// together. This method must not assign host bounds.
  bool afterClipEdit({
    required String songId,
    required String? playbackId,
    required String action,
    required int startMs,
    required int endMs,
  }) {
    if (action != 'save' && action != 'preview' && action != 'clear') {
      return false;
    }
    if (!_editStillOwns(songId, playbackId)) return false;
    final nextStart = action == 'clear' ? 0 : startMs;
    final nextEnd = action == 'clear' ? 0 : endMs;
    ref
        .read(clipUiOverrideProvider.notifier)
        .set(songId, playbackId, nextStart, nextEnd);
    state = _resolve();
    return true;
  }

  /// Undoes a preview subtitle. Does not write host clip bounds.
  ///
  /// Restores [previous] only while the snapshot and host still name
  /// [playbackId]. If that playback is gone, the preview overlay is dropped
  /// and [previous] is not installed on the replacement.
  void rollbackPreview({
    required String songId,
    required String? playbackId,
    required ClipUiOverride? previous,
  }) {
    final current = ref.read(clipUiOverrideProvider);
    if (current == null ||
        current.songId != songId ||
        current.playbackId != playbackId) {
      return;
    }
    final notifier = ref.read(clipUiOverrideProvider.notifier);
    final stillHere = _editStillOwns(songId, playbackId);
    if (stillHere &&
        previous != null &&
        previous.songId == songId &&
        previous.playbackId == playbackId) {
      notifier.restore(previous);
    } else {
      notifier.restore(null);
    }
    state = _resolve();
  }

  bool _editStillOwns(String songId, String? playbackId) {
    final player = ref.read(playerProvider);
    if (player.snapshot.current?.id != songId) return false;
    if (player.playbackId != playbackId) return false;
    final host = _host ?? ref.read(playbackHostProvider);
    return !_hostMovedOn(host, playbackId);
  }
}

/// True when [host] is already playing a different id than [playbackId].
/// A null binding means the old load was stopped and the next load has not
/// arrived; that is not a different song yet.
bool _hostMovedOn(PlaybackHost? host, String? playbackId) {
  if (host == null) return false;
  final hostId = host.activePlaybackId;
  if (hostId == null || hostId.isEmpty) return false;
  return hostId != playbackId;
}

final displayedClipProvider =
    NotifierProvider<DisplayedClipController, DisplayedClip?>(
      DisplayedClipController.new,
    );
