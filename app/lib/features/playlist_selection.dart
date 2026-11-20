import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/providers.dart';
import 'library_actions.dart';
import 'navigation.dart';
import 'session.dart';

/// Multi-select and batch actions for the open playlist. The mobile pane and
/// the desktop track table lay rows out differently but must select, batch,
/// and keep failures in exactly the same way.
mixin PlaylistSelection<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final selected = <String>{};
  final removedSongIds = <String>{};
  String? target;
  bool all = false;
  bool selecting = false;
  bool busy = false;

  /// Drops the selection when another playlist opens. Call from `build`.
  void syncSelectionTarget(LibraryState library) {
    if (target == library.selectedPlaylistId) return;
    target = library.selectedPlaylistId;
    selected.clear();
    removedSongIds.clear();
    all = false;
    selecting = false;
  }

  List<Song> visibleSongs(LibraryState library) => removedSongIds.isEmpty
      ? library.songs
      : library.songs
            .where((song) => !removedSongIds.contains(song.id))
            .toList();

  bool isChecked(Song song) => all || selected.contains(song.id);

  void toggleSong(Song song) => setState(() {
    selecting = true;
    all = false;
    if (!selected.add(song.id)) selected.remove(song.id);
  });

  void toggleSelecting() => setState(() {
    selecting = !selecting;
    selected.clear();
    all = false;
  });

  void selectLoaded(LibraryState library) => setState(() {
    all = false;
    selected.addAll(library.songs.map((s) => s.id));
  });

  void selectAll() => setState(() => all = true);

  bool get hasSelection => all || selected.isNotEmpty;

  Future<void> runBatch(String action) async {
    final library = ref.read(libraryProvider);
    final batchTarget = library.selectedPlaylistId;
    final songs = library.songs.where((s) => selected.contains(s.id)).toList();
    final playlist = all ? library.selectedPlaylistId ?? '' : '';
    final api = ref.read(coreApiProvider);
    setState(() => busy = true);
    await perform(context, () async {
      if (action == 'download') {
        final result = await api.downloadSelection(
          songs: songs,
          playlistId: playlist,
        );
        if (mounted) {
          showBatchResult(context, result);
          _keepFailures(result, batchTarget);
        }
        return;
      }
      if (action == 'add') {
        final result = await addSongs(
          context,
          api,
          songs,
          playlistId: playlist,
        );
        if (mounted && result != null) _keepFailures(result, batchTarget);
        return;
      }
      if (action == 'remove' &&
          !await confirmAction(
            context,
            '移除选中曲目',
            '歌曲将从当前歌单移除；若为混合歌单，这些歌曲以后也会隐藏。音频文件和来源歌单保留。',
          )) {
        return;
      }
      if (action == 'play') {
        ref.read(interruptionPolicyProvider).noteUserTransport();
      }
      final result = await api.batch(
        action,
        playlistId: playlist,
        songs: songs,
        target: action == 'play' ? '' : library.selectedPlaylistId ?? '',
      );
      if (!mounted) return;
      showBatchResult(context, result);
      _keepFailures(result, batchTarget);
    });
    if (mounted) setState(() => busy = false);
  }

  void _keepFailures(BatchResult result, String? batchTarget) {
    if (ref.read(libraryProvider).selectedPlaylistId != batchTarget) return;
    setState(() {
      all = false;
      selected.clear();
      selected.addAll(result.failed.map((f) => f.songId));
      selecting = selected.isNotEmpty;
    });
  }

  Future<void> playFromPlaylist(Song song) {
    final library = ref.read(libraryProvider);
    return perform(
      context,
      () => ref
          .read(transportProvider)
          .playPlaylistSong(song, library.selectedPlaylistId!, library.songs),
    );
  }

  Future<void> removeSong(Song song) async {
    final playlistId = ref.read(libraryProvider).selectedPlaylistId;
    if (playlistId == null) return;
    setState(() => removedSongIds.add(song.id));
    final api = ref.read(coreApiProvider);
    var removed = false;
    await perform(context, () async {
      final result = await api.batch(
        'remove',
        playlistId: playlistId,
        songs: [song],
      );
      removed = !result.failed.any((failure) => failure.songId == song.id);
      if (mounted) showBatchResult(context, result);
    });
    if (!removed && mounted) {
      setState(() => removedSongIds.remove(song.id));
    }
  }
}
