import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/providers.dart';
import '../shared/song_tile.dart';
import 'library_actions.dart';
import 'navigation.dart';
import 'session.dart';
import 'song_actions.dart';

/// Selection belongs to the content target, persists across pages, and never
/// follows the currently playing song. It contains explicit stable song IDs.
class SongSelectionScope extends ConsumerStatefulWidget {
  const SongSelectionScope({
    required this.target,
    required this.child,
    super.key,
  });
  final Object target;
  final Widget child;
  @override
  ConsumerState<SongSelectionScope> createState() => _SongSelectionState();
}

class _SongSelectionState extends ConsumerState<SongSelectionScope> {
  final selected = <String, Song>{};
  String? focused;
  bool selecting = false, busy = false;
  @override
  void didUpdateWidget(covariant SongSelectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      selected.clear();
      focused = null;
      selecting = false;
    }
  }

  void toggle(Song song) {
    if (busy) return;
    setState(() {
      selecting = true;
      if (selected.containsKey(song.id)) {
        selected.remove(song.id);
      } else {
        selected[song.id] = song;
      }
    });
  }

  void toggleMode() => setState(() {
    selecting = !selecting;
    selected.clear();
  });

  void focusSong(Song song) => setState(() => focused = song.id);

  Future<void> act(String action) async {
    final target = widget.target;
    final songs = selected.values.toList(growable: false);
    if (songs.isEmpty || busy) return;
    setState(() => busy = true);
    await perform(context, () async {
      final api = ref.read(coreApiProvider);
      BatchResult? result;
      if (action == 'add') {
        result = await addSongs(context, api, songs);
      } else {
        if (action == 'play') {
          ref.read(interruptionPolicyProvider).noteUserTransport();
        }
        result = action == 'download'
            ? await api.downloadSelection(songs: songs)
            : await api.batch(action, songs: songs);
        if (mounted) showBatchResult(context, result);
      }
      if (!mounted || widget.target != target || result == null) return;
      final failed = result.failed.map((f) => f.songId).toSet();
      setState(() {
        selected.removeWhere((id, _) => !failed.contains(id));
        selecting = selected.isNotEmpty;
      });
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) =>
      _SelectionHost(state: this, child: widget.child);
}

class _SelectionHost extends InheritedWidget {
  const _SelectionHost({required this.state, required super.child});
  final _SongSelectionState state;
  static _SongSelectionState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SelectionHost>()!.state;
  @override
  bool updateShouldNotify(_SelectionHost oldWidget) => true;
}

class SongSelectionBar extends StatelessWidget {
  const SongSelectionBar({super.key});
  @override
  Widget build(BuildContext context) {
    final selection = _SelectionHost.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: selection.busy ? null : selection.toggleMode,
          child: Text(selection.selecting ? '取消多选' : '多选歌曲'),
        ),
        if (selection.selecting) ...[
          Text('已选 ${selection.selected.length} 首 · 可跨页选择'),
          PopupMenuButton<String>(
            tooltip: '批量操作',
            enabled: !selection.busy && selection.selected.isNotEmpty,
            onSelected: selection.act,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'play', child: Text('播放')),
              PopupMenuItem(value: 'next', child: Text('下一首播放')),
              PopupMenuItem(value: 'enqueue', child: Text('加入队列')),
              PopupMenuItem(value: 'add', child: Text('加入歌单')),
              PopupMenuItem(value: 'download', child: Text('下载')),
            ],
          ),
        ],
        if (selection.busy)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}

class SelectableSong extends ConsumerWidget {
  const SelectableSong({
    required this.song,
    this.onSelect,
    this.selected,
    this.queue,
    super.key,
  });
  final Song song;
  final VoidCallback? onSelect;
  final bool? selected;
  final List<Song>? queue;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = _SelectionHost.of(context);
    final mobile = ref.watch(platformLabelProvider) == 'android';
    final checked = selection.selected.containsKey(song.id);
    Future<void> play() => perform(
      context,
      () => ref.read(transportProvider).playSong(song, context: queue),
    );
    return Row(
      children: [
        if (selection.selecting)
          Checkbox(
            value: checked,
            onChanged: selection.busy ? null : (_) => selection.toggle(song),
          ),
        Expanded(
          child: SongTile(
            song: song,
            selected: selection.selecting
                ? checked
                : selected ?? selection.focused == song.id,
            current: ref.watch(playerProvider).snapshot.current?.id == song.id,
            doubleTapToPlay: !mobile,
            onLongPress: () => selection.toggle(song),
            onTap: () {
              if (selection.selecting) {
                selection.toggle(song);
              } else if (mobile) {
                play();
              } else {
                selection.focusSong(song);
                onSelect?.call();
              }
            },
            onPlay: play,
            trailing: SongActions(song: song),
          ),
        ),
      ],
    );
  }
}
