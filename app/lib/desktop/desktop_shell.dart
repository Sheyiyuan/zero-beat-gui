import 'key_bindings.dart';
import '../features/downloads_page.dart';
import '../features/sync_page.dart';
import '../features/navigation.dart';
import '../features/library_actions.dart';
import '../features/accounts_page.dart';
import '../features/content_pages.dart';
import '../features/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../features/session.dart';
import '../platform/desktop_mode.dart';
import '../shared/library_pane.dart';
import '../shared/playback.dart';
import '../shared/player_bar.dart';
import '../shared/queue_panel.dart';
import '../shared/search_box.dart';
import '../shared/seek_bar.dart';

class ToggleIntent extends Intent {
  const ToggleIntent();
}

class AuthorsIntent extends Intent {
  const AuthorsIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class PreviousIntent extends Intent {
  const PreviousIntent();
}

class NextIntent extends Intent {
  const NextIntent();
}

class VolumeDownIntent extends Intent {
  const VolumeDownIntent();
}

class VolumeUpIntent extends Intent {
  const VolumeUpIntent();
}

class PlaySelectedIntent extends Intent {
  const PlaySelectedIntent();
}

class CloseOverlayIntent extends Intent {
  const CloseOverlayIntent();
}

bool primaryFocusIsEditable() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorStateOfType<EditableTextState>() != null;
}

class _GuardedAction extends Action<Intent> {
  _GuardedAction(this._run, {this.enabled = true});
  final bool enabled;

  final VoidCallback _run;

  @override
  bool isEnabled(Intent intent) => enabled && !primaryFocusIsEditable();

  @override
  Object? invoke(Intent intent) {
    _run();
    return null;
  }
}

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scope = FocusNode(debugLabel: 'desktop-scope');
  bool _nowPlaying = false;
  final _navigatorKey = GlobalKey<NavigatorState>();

  static const _intents = <String, Intent>{
    'authors': AuthorsIntent(),
    'toggle': ToggleIntent(),
    'search': SearchIntent(),
    'previous': PreviousIntent(),
    'next': NextIntent(),
    'volume_down': VolumeDownIntent(),
    'volume_up': VolumeUpIntent(),
    'play_selected': PlaySelectedIntent(),
    'close_panel': CloseOverlayIntent(),
  };

  Map<ShortcutActivator, Intent> _shortcuts(Map<String, String> overrides) {
    final result = <ShortcutActivator, Intent>{};
    for (final entry in {...guiShortcutDefaults, ...overrides}.entries) {
      final intent = _intents[entry.key];
      if (intent == null) continue;
      try {
        final key = parseGUIShortcut(entry.value);
        if (key != null) result[key] = intent;
      } on FormatException {
        /* Ignore malformed preferences from older clients. */
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus && !primaryFocusIsEditable()) {
        _scope.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  void _closeOverlay() {
    if (_nowPlaying) {
      setState(() => _nowPlaying = false);
      return;
    }
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
      Navigator.of(context).pop();
      return;
    }
    _navigatorKey.currentState?.maybePop();
  }

  Future<void> _playSelected() async {
    final search = ref.read(searchProvider);
    final transport = ref.read(transportProvider);
    if (search.submitted && search.error.isEmpty) {
      final song = search.selectedSong;
      if (song != null) {
        final songs = [
          for (final item in search.results) songFromTrack(item.track),
        ];
        await transport.playSong(song, context: songs);
      }
      return;
    }
    final library = ref.read(libraryProvider);
    final song = library.selectedSong;
    if (song != null) {
      await transport.playPlaylistSong(
        song,
        library.selectedPlaylistId!,
        library.songs,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transport = ref.read(transportProvider);
    final connected = ref.watch(connectionProvider);
    return Shortcuts(
      shortcuts: _shortcuts(ref.watch(guiSettingsProvider).shortcuts),
      child: Actions(
        actions: <Type, Action<Intent>>{
          AuthorsIntent: _GuardedAction(() {
            final song = ref.read(playerProvider).snapshot.current;
            if (song != null) {
              openAuthors(
                _navigatorKey.currentContext ?? context,
                ref.read(coreApiProvider),
                song,
              );
            }
          }),
          ToggleIntent: _GuardedAction(
            () => perform(context, transport.toggle),
            enabled: connected,
          ),
          SearchIntent: _GuardedAction(() {
            _navigatorKey.currentState?.popUntil((r) => r.isFirst);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) ref.read(searchFocusProvider).requestFocus();
            });
          }),
          PreviousIntent: _GuardedAction(
            () => perform(context, transport.previous),
            enabled: connected,
          ),
          NextIntent: _GuardedAction(
            () => perform(context, transport.next),
            enabled: connected,
          ),
          VolumeDownIntent: _GuardedAction(
            () => perform(context, () => transport.bumpVolume(-0.05)),
            enabled: connected,
          ),
          VolumeUpIntent: _GuardedAction(
            () => perform(context, () => transport.bumpVolume(0.05)),
            enabled: connected,
          ),
          PlaySelectedIntent: _GuardedAction(
            () => perform(context, _playSelected),
            enabled: connected,
          ),
          CloseOverlayIntent: _GuardedAction(_closeOverlay),
        },
        child: Focus(
          focusNode: _scope,
          autofocus: true,
          child: ValueListenableBuilder<bool>(
            valueListenable: DesktopMode.mini,
            builder: (context, mini, _) {
              if (mini) return const _MiniPlayer();
              return _DesktopFrame(
                scaffoldKey: _scaffoldKey,
                navigatorKey: _navigatorKey,
                nowPlaying: _nowPlaying,
                onOpenNowPlaying: () =>
                    setState(() => _nowPlaying = !_nowPlaying),
                onCloseNowPlaying: () => setState(() => _nowPlaying = false),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DesktopFrame extends ConsumerWidget {
  const _DesktopFrame({
    required this.scaffoldKey,
    required this.navigatorKey,
    required this.nowPlaying,
    required this.onOpenNowPlaying,
    required this.onCloseNowPlaying,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final GlobalKey<NavigatorState> navigatorKey;
  final bool nowPlaying;
  final VoidCallback onOpenNowPlaying;
  final VoidCallback onCloseNowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final narrow = MediaQuery.sizeOf(context).width < 900;
    Widget sidebar(BuildContext context) => ColoredBox(
      color: context.zero.surfaceMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '曲库',
              style: TextStyle(fontSize: 18, color: context.zero.text),
            ),
          ),
          Wrap(
            children: [
              IconButton(
                tooltip: '下载管理',
                icon: const Icon(Icons.download_outlined),
                onPressed: () =>
                    openFeature(context, '下载管理', const DownloadsBody()),
              ),
              IconButton(
                tooltip: '仓库同步',
                icon: const Icon(Icons.sync),
                onPressed: () => openFeature(context, '仓库同步', const SyncBody()),
              ),
              LibraryTools(
                playlist: library.playlists
                    .where((p) => p.id == library.selectedPlaylistId)
                    .firstOrNull,
              ),
              IconButton(
                tooltip: '本地搜索',
                icon: const Icon(Icons.manage_search),
                onPressed: () => openFeature(
                  context,
                  '本地曲库搜索',
                  LocalSearchBody(playlistId: library.selectedPlaylistId ?? ''),
                ),
              ),
              IconButton(
                tooltip: '发现与电台',
                icon: const Icon(Icons.explore_outlined),
                onPressed: () =>
                    openFeature(context, '发现与电台', const BrowseRootsBody()),
              ),
              IconButton(
                tooltip: '账号',
                icon: const Icon(Icons.person_outline),
                onPressed: () =>
                    openFeature(context, '账号', const AccountsBody()),
              ),
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () =>
                    openFeature(context, '设置', const SettingsBody()),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: library.playlists.length,
              itemBuilder: (context, index) {
                final playlist = library.playlists[index];
                final selected = playlist.id == library.selectedPlaylistId;
                return ListTile(
                  selected: selected,
                  selectedTileColor: context.zero.accentSoft,
                  title: Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    if (narrow) scaffoldKey.currentState?.closeDrawer();
                    navigatorKey.currentState?.popUntil(
                      (route) => route.isFirst,
                    );
                    ref.read(searchProvider.notifier).clearResults();
                    ref
                        .read(libraryProvider.notifier)
                        .selectPlaylist(playlist.id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
    return FeatureNavigation(
      navigatorKey: navigatorKey,
      child: Builder(
        builder: (context) => Scaffold(
          key: scaffoldKey,
          drawer: narrow ? Drawer(child: sidebar(context)) : null,
          backgroundColor: context.zero.canvas,
          endDrawer: Drawer(
            width: 360,
            backgroundColor: context.zero.surface,
            child: QueuePanel(),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!narrow)
                          SizedBox(width: 224, child: sidebar(context)),
                        if (narrow)
                          SizedBox(
                            width: 56,
                            child: Column(
                              children: [
                                IconButton(
                                  tooltip: '展开曲库',
                                  icon: const Icon(Icons.menu),
                                  onPressed: () =>
                                      scaffoldKey.currentState?.openDrawer(),
                                ),
                              ],
                            ),
                          ),
                        VerticalDivider(width: 1),
                        Expanded(
                          child: Navigator(
                            key: navigatorKey,
                            onGenerateRoute: (_) => MaterialPageRoute(
                              builder: (context) => Consumer(
                                builder: (context, ref, _) {
                                  final search = ref.watch(searchProvider);
                                  return search.submitted
                                      ? ListView(
                                          padding: const EdgeInsets.all(24),
                                          children: [
                                            SearchBox(),
                                            SizedBox(height: 16),
                                            SearchBody(),
                                          ],
                                        )
                                      : Padding(
                                          padding: EdgeInsets.all(24),
                                          child: Column(
                                            children: [
                                              SearchBox(),
                                              SizedBox(height: 16),
                                              Expanded(child: LibraryPane()),
                                            ],
                                          ),
                                        );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1),
                  PlayerBar(
                    onOpen: onOpenNowPlaying,
                    onQueue: () => scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ],
              ),
              if (nowPlaying)
                Positioned.fill(
                  child: Material(
                    color: context.zero.canvas,
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: '关闭',
                            onPressed: onCloseNowPlaying,
                            icon: Icon(Icons.close),
                          ),
                        ),
                        Expanded(child: NowPlayingBody()),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlayer extends ConsumerWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final song = view.snapshot.current;
    final title = song?.title.isNotEmpty == true ? song!.title : '未在播放';
    final transport = ref.read(transportProvider);
    return Material(
      color: context.zero.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Row(
              children: [
                CoverArt(cover: song?.cover ?? '', size: 36),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '上一首',
                  onPressed: transport.previous,
                  icon: Icon(Icons.skip_previous),
                ),
                PlayPauseButton(),
                IconButton(
                  tooltip: '下一首',
                  onPressed: transport.next,
                  icon: Icon(Icons.skip_next),
                ),
                IconButton(
                  tooltip: '恢复',
                  onPressed: DesktopMode.restore,
                  icon: Icon(Icons.open_in_full),
                ),
                IconButton(
                  key: Key('quit'),
                  tooltip: '退出',
                  onPressed: () => ref.read(quitActionProvider)(),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            SeekBar(
              positionMs: view.snapshot.positionMs,
              durationMs: view.snapshot.durationMs,
              onSeek: transport.seek,
            ),
          ],
        ),
      ),
    );
  }
}
