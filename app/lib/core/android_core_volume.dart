import 'package:zero_beat_rpc/zero_beat_rpc.dart';

/// Keeps the core/mpv output at unity on Android so the final loudness is
/// decided only by the system `STREAM_MUSIC` volume.
///
/// This is startup-only: call it once after the RPC connection is established,
/// never from a widget build or a volume-slider callback. The write goes to the
/// core's local `settings.volume`; sync's snapshot only exports playlists,
/// annotations, keymap and account ciphertexts, so the value cannot enter the
/// sync repository. Desktop never calls this helper and keeps its core volume.
///
/// Core `SetVolume` also clears its muted flag. Doing that here is intentional:
/// a persisted core mute would otherwise make the system volume row show a
/// percentage that produces no sound.
Future<void> alignAndroidCoreVolume(CoreApi api) async {
  final player = api.helloResult?.player;
  final volume = player?.snapshot.volume;
  final muted = player?.snapshot.muted ?? false;
  final alreadyUnity = volume != null && (volume - 1.0).abs() <= 0.001;
  if (alreadyUnity && !muted) return;
  try {
    await api.setVolume(1);
  } catch (_) {
    // Startup should not fail just because the core rejected the initial
    // volume; playback remains usable at the persisted value.
  }
}
