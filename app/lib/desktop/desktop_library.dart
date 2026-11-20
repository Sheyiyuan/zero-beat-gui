import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';

import '../app/icons.dart';
import '../app/theme.dart';
import '../features/library_actions.dart';
import '../features/navigation.dart';
import '../features/playlist_selection.dart';
import '../features/session.dart';
import '../features/song_actions.dart';
import '../shared/cover_art.dart';
import '../shared/playback.dart';
import '../shared/song_tile.dart';
import 'desktop_pages.dart';

const _rowHeight = 56.0;
const _indexWidth = 48.0;
const _sourceWidth = 108.0;
const _durationWidth = 64.0;
const _actionsWidth = 48.0;

/// Which optional table columns fit the current width.
class DesktopTrackColumns {
  const DesktopTrackColumns({required this.source, required this.album});

  factory DesktopTrackColumns.forWidth(
    double width, {
    required bool hasAlbum,
  }) => DesktopTrackColumns(
    source: width >= 640,
    album: hasAlbum && width >= 980,
  );

  final bool source;
  final bool album;
}

class DesktopLibraryView extends ConsumerStatefulWidget {
  const DesktopLibraryView({super.key});

  @override
  ConsumerState<DesktopLibraryView> createState() => _DesktopLibraryViewState();
}

class _DesktopLibraryViewState extends ConsumerState<DesktopLibraryView>
    with PlaylistSelection {
  final _filter = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  void syncSelectionTarget(LibraryState library) {
    if (target != library.selectedPlaylistId && _query.isNotEmpty) {
      _filter.clear();
      _query = '';
    }
    super.syncSelectionTarget(library);
  }

  List<Song> _filtered(List<Song> songs) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return songs;
    return songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(query) ||
              s.artist.toLowerCase().contains(query) ||
              s.album.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _confirmRemove(Song song) async {
    if (!await confirmAction(
      context,
      '从歌单移除「${song.title}」',
      '只从当前歌单移除，不会删除音频文件。',
    )) {
      return;
    }
    await removeSong(song);
  }

  void _songMenu(Song song, {Offset? position}) {
    showSongMenu(
      context,
      ref,
      song,
      position: position,
      extra: const [
        SongAction(id: 'select', label: '多选此曲', icon: AppIcons.select),
        SongAction(id: 'remove', label: '从歌单移除', icon: AppIcons.removeFromList),
      ],
      onExtra: (action) =>
          action == 'select' ? toggleSong(song) : _confirmRemove(song),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    syncSelectionTarget(library);
    if (library.loading && !library.loaded && library.playlists.isEmpty) {
      return const Center(child: Text('正在读取曲库'));
    }
    if (library.error.isNotEmpty && library.songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              library.error,
              key: const Key('library-error'),
              style: TextStyle(color: context.zero.danger),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(libraryProvider.notifier).retry(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final playlist = library.playlists
        .where((item) => item.id == library.selectedPlaylistId)
        .firstOrNull;
    if (playlist == null) return const EmptyLibrary();
    final view = ref.watch(playerProvider);
    final current = view.snapshot.current?.id;
    final playing = isPlaying(view);
    final loaded = visibleSongs(library);
    final songs = _filtered(loaded);
    final hasAlbum = loaded.any((s) => s.album.isNotEmpty);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = DesktopTrackColumns.forWidth(
          constraints.maxWidth,
          hasAlbum: hasAlbum,
        );
        return CustomScrollView(
          key: PageStorageKey('desktop-library-${library.selectedPlaylistId}'),
          slivers: [
            SliverToBoxAdapter(
              child: _PlaylistHero(
                playlist: playlist,
                library: library,
                compact: constraints.maxWidth < 640,
              ),
            ),
            PinnedHeaderSliver(
              child: ColoredBox(
                color: context.zero.canvas,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    selecting
                        ? _selectionBar(library)
                        : _toolbar(library, loaded.length),
                    if (busy || library.refreshing)
                      LinearProgressIndicator(
                        key: library.refreshing
                            ? const Key('library-refresh-progress')
                            : null,
                        minHeight: 2,
                      )
                    else
                      const SizedBox(height: 2),
                    _TableHeader(columns: columns),
                  ],
                ),
              ),
            ),
            if (library.warning.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    desktopPageInset,
                    8,
                    desktopPageInset,
                    8,
                  ),
                  child: Text(
                    library.warning,
                    style: TextStyle(color: context.zero.warning),
                  ),
                ),
              ),
            if (library.isEmpty)
              const SliverToBoxAdapter(
                child: SizedBox(height: 240, child: EmptyLibrary()),
              )
            else if (songs.isEmpty && _query.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Text(
                      '已加载的歌曲中没有匹配「$_query」的结果',
                      style: TextStyle(color: context.zero.muted),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: desktopPageInset - 12,
              ),
              sliver: SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return DesktopTrackRow(
                    key: ValueKey('track-${song.id}'),
                    song: song,
                    index: _query.isEmpty
                        ? index + 1
                        : loaded.indexOf(song) + 1,
                    columns: columns,
                    current: current == song.id,
                    playing: playing && current == song.id,
                    selected: !selecting && song.id == library.selectedSongId,
                    checked: selecting ? isChecked(song) : null,
                    onCheck: busy ? null : () => toggleSong(song),
                    onSelect: () =>
                        ref.read(libraryProvider.notifier).selectSong(song.id),
                    onPlay: () => playFromPlaylist(song),
                    onMenu: (position) => _songMenu(song, position: position),
                  );
                },
              ),
            ),
            if (library.hasMore && _query.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (library.moreError.isNotEmpty)
                        Text(
                          library.moreError,
                          style: TextStyle(color: context.zero.danger),
                        ),
                      TextButton(
                        key: const Key('library-load-more'),
                        onPressed: library.loadingMore
                            ? null
                            : ref.read(libraryProvider.notifier).loadMore,
                        child: Text(
                          library.loadingMore
                              ? '正在加载'
                              : library.moreError.isEmpty
                              ? '加载更多（已显示 ${library.songs.length} / ${library.total} 首）'
                              : '重试加载',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }

  Widget _toolbar(LibraryState library, int loadedCount) {
    final countText = _query.isEmpty
        ? '${library.total} 首'
        : '筛选 $loadedCount / ${library.total} 首';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        desktopPageInset,
        8,
        desktopPageInset - 8,
        8,
      ),
      child: Row(
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: SizedBox(
                height: 36,
                child: TextField(
                  key: const Key('library-filter'),
                  controller: _filter,
                  onChanged: (value) => setState(() => _query = value),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '在歌单中筛选',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    fillColor: context.zero.surface,
                    prefixIcon: const Icon(AppIcons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              countText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.zero.muted, fontSize: 12.5),
            ),
          ),
          TextButton.icon(
            onPressed: busy ? null : toggleSelecting,
            icon: const Icon(AppIcons.select, size: 16),
            label: const Text('多选'),
          ),
          IconButton(
            tooltip: '搜索本地曲库',
            onPressed: () => openFeature(
              context,
              '本地曲库搜索',
              LocalSearchBody(playlistId: library.selectedPlaylistId ?? ''),
            ),
            icon: const Icon(AppIcons.localSearch, size: 18),
          ),
          IconButton(
            key: const Key('library-refresh-pane'),
            tooltip: '刷新歌单',
            onPressed: library.refreshing
                ? null
                : () => refreshPlaylistNow(context, ref),
            icon: const Icon(AppIcons.refresh, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar(LibraryState library) {
    final enabled = !busy && hasSelection;
    Widget action(String id, String label, IconData icon) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        key: Key('batch-$id'),
        onPressed: enabled ? () => runBatch(id) : null,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        desktopPageInset - 8,
        8,
        desktopPageInset - 8,
        8,
      ),
      child: Material(
        color: context.zero.accentSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Text(
                all ? '已选全部 ${library.total} 首' : '已选 ${selected.length} 首',
                style: TextStyle(
                  color: context.zero.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => selectLoaded(library),
                        child: const Text('全选已加载'),
                      ),
                      if (library.hasMore)
                        TextButton(
                          onPressed: selectAll,
                          child: Text('选择全部 ${library.total} 首'),
                        ),
                      const SizedBox(width: 8),
                      action('play', '播放', AppIcons.play),
                      action('next', '下一首播放', AppIcons.playNext),
                      action('enqueue', '加入队列', AppIcons.queue),
                      action('add', '加入歌单', AppIcons.addToPlaylist),
                      action('download', '下载', AppIcons.download),
                      action('remove', '移除', AppIcons.removeFromList),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '取消多选',
                onPressed: busy ? null : toggleSelecting,
                icon: const Icon(AppIcons.close, size: 18),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistHero extends ConsumerWidget {
  const _PlaylistHero({
    required this.playlist,
    required this.library,
    required this.compact,
  });

  final Playlist playlist;
  final LibraryState library;
  final bool compact;

  String get _kind => switch (playlist.kind.value) {
    'remote' => '${sourceLabel(playlist.source)}歌单',
    'mixin' => '混合歌单',
    'folder' => '文件夹歌单',
    _ => playlist.syncExcluded ? '仅本机歌单' : '本地歌单',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = compact ? 104.0 : 148.0;
    final cover = library.songs
        .map((s) => s.cover)
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');
    final canPlay = library.songs.isNotEmpty;
    final totalMs = library.hasMore
        ? 0
        : library.songs.fold<int>(0, (sum, s) => sum + s.durationMs);
    final minutes = (totalMs / 60000).round();
    final meta = [
      playlistMeta(playlist),
      if (minutes > 0)
        minutes >= 60
            ? '${minutes ~/ 60} 小时 ${minutes % 60} 分钟'
            : '$minutes 分钟',
    ].join(' · ');
    void menu(Offset? position) =>
        showPlaylistMenu(context, ref, playlist, position: position);
    return GestureDetector(
      key: ValueKey('playlist-header-${playlist.id}'),
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => menu(details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          desktopPageInset,
          8,
          desktopPageInset,
          20,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            cover.isNotEmpty
                ? CoverArt(cover: cover, size: size, radius: 12)
                : PlaylistSourceIcon(playlist: playlist, size: size),
            SizedBox(width: compact ? 16 : 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kind,
                    style: TextStyle(
                      color: context.zero.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    playlist.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.zero.text,
                      fontSize: compact ? 22 : 30,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      PlaylistSourceIcon(
                        key: ValueKey('playlist-header-source-${playlist.id}'),
                        playlist: playlist,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.zero.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const Key('play-playlist'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: canPlay
                            ? () => playPlaylist(
                                context,
                                ref,
                                playlist,
                                songs: library.songs,
                              )
                            : null,
                        icon: const Icon(AppIcons.play, size: 16),
                        label: const Text('播放全部'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('shuffle-playlist'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: canPlay
                            ? () async {
                                await perform(
                                  context,
                                  () => ref
                                      .read(transportProvider)
                                      .setPlaybackMode('shuffle'),
                                );
                                if (context.mounted) {
                                  await playPlaylist(
                                    context,
                                    ref,
                                    playlist,
                                    songs: library.songs,
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(AppIcons.shuffle, size: 16),
                        label: const Text('随机播放'),
                      ),
                      Builder(
                        builder: (context) => IconButton(
                          tooltip: '歌单操作',
                          style: IconButton.styleFrom(
                            side: BorderSide(color: context.zero.line),
                          ),
                          onPressed: () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            menu(
                              box?.localToGlobal(
                                box.size.bottomLeft(Offset.zero),
                              ),
                            );
                          },
                          icon: const Icon(AppIcons.more, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.columns});

  final DesktopTrackColumns columns;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: context.zero.muted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: desktopPageInset - 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.zero.line)),
        ),
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              SizedBox(
                width: _indexWidth,
                child: Text('#', textAlign: TextAlign.center, style: style),
              ),
              Expanded(flex: 5, child: Text('标题', style: style)),
              if (columns.album)
                Expanded(flex: 3, child: Text('专辑', style: style)),
              if (columns.source)
                SizedBox(
                  width: _sourceWidth,
                  child: Text('来源', style: style),
                ),
              SizedBox(
                width: _durationWidth,
                child: Text('时长', textAlign: TextAlign.right, style: style),
              ),
              const SizedBox(width: _actionsWidth),
            ],
          ),
        ),
      ),
    );
  }
}

/// One track in the desktop table. Click selects, double-click plays, the
/// index cell turns into a play button on hover, and right click opens the
/// shared song menu.
class DesktopTrackRow extends StatefulWidget {
  const DesktopTrackRow({
    required this.song,
    required this.index,
    required this.columns,
    required this.current,
    required this.playing,
    required this.selected,
    required this.checked,
    required this.onCheck,
    required this.onSelect,
    required this.onPlay,
    required this.onMenu,
    super.key,
  });

  final Song song;
  final int index;
  final DesktopTrackColumns columns;
  final bool current;
  final bool playing;
  final bool selected;

  /// Null outside multi-select.
  final bool? checked;
  final VoidCallback? onCheck;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final ValueChanged<Offset?> onMenu;

  @override
  State<DesktopTrackRow> createState() => _DesktopTrackRowState();
}

class _DesktopTrackRowState extends State<DesktopTrackRow> {
  bool _hover = false;
  DateTime? _lastTap;

  void _tap() {
    if (widget.checked != null) {
      widget.onCheck?.call();
      return;
    }
    final now = DateTime.now();
    final last = _lastTap;
    _lastTap = now;
    widget.onSelect();
    if (last != null && now.difference(last) < kDoubleTapTimeout) {
      _lastTap = null;
      widget.onPlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final zero = context.zero;
    final checked = widget.checked;
    final highlighted = widget.selected || (checked ?? false);
    final background = highlighted
        ? zero.accentSoft.withValues(alpha: 0.7)
        : _hover
        ? zero.surfaceMuted.withValues(alpha: 0.7)
        : Colors.transparent;
    final titleColor = widget.current ? zero.accent : zero.text;
    final mutedStyle = TextStyle(color: zero.muted, fontSize: 12.5);
    Widget indexCell;
    if (checked != null) {
      indexCell = Checkbox(
        value: checked,
        onChanged: widget.onCheck == null ? null : (_) => widget.onCheck!(),
      );
    } else if (_hover || widget.selected) {
      indexCell = IconButton(
        tooltip: '播放',
        iconSize: 16,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: zero.accent,
        ),
        onPressed: widget.onPlay,
        icon: const Icon(AppIcons.play),
      );
    } else if (widget.current) {
      indexCell = Icon(
        widget.playing ? AppIcons.waveform : AppIcons.pause,
        key: const Key('song-current-mark'),
        size: 16,
        color: zero.accent,
      );
    } else {
      indexCell = Text(
        '${widget.index}',
        style: mutedStyle.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${song.title}，${song.artist}，${sourceLabel(song.source)}',
      selected: highlighted,
      button: true,
      onTap: _tap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              widget.onMenu(details.globalPosition),
          onLongPress: () => widget.onMenu(null),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(10),
              onTap: _tap,
              child: Stack(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: _rowHeight),
                    child: Row(
                      children: [
                        SizedBox(
                          width: _indexWidth,
                          child: Center(child: indexCell),
                        ),
                        Expanded(
                          flex: 5,
                          child: ExcludeSemantics(
                            child: Row(
                              children: [
                                CoverArt(
                                  key: ValueKey('song-cover-${song.id}'),
                                  cover: song.cover,
                                  size: 40,
                                  radius: 6,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        key: ValueKey('title-${song.id}'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: titleColor,
                                          fontSize: 14,
                                          fontWeight: widget.current
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: mutedStyle,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                            ),
                          ),
                        ),
                        if (widget.columns.album)
                          Expanded(
                            flex: 3,
                            child: ExcludeSemantics(
                              child: Text(
                                song.album,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mutedStyle,
                              ),
                            ),
                          ),
                        if (widget.columns.source)
                          SizedBox(
                            width: _sourceWidth,
                            child: ExcludeSemantics(
                              child: Row(
                                children: [
                                  PlatformSourceIcon(
                                    key: ValueKey('song-source-${song.id}'),
                                    source: song.source,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      sourceLabel(song.source),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: mutedStyle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SizedBox(
                          width: _durationWidth,
                          child: Text(
                            formatClock(song.durationMs),
                            textAlign: TextAlign.right,
                            style: mutedStyle.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: _actionsWidth,
                          child: Opacity(
                            opacity: _hover || highlighted ? 1 : 0.55,
                            child: SongActions(song: song),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.current)
                    Positioned(
                      left: 0,
                      top: 12,
                      bottom: 12,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: zero.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
