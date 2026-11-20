import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/icons.dart';
import '../app/providers.dart';
import '../features/accounts_page.dart';
import '../features/content_pages.dart';
import '../features/downloads_page.dart';
import '../features/navigation.dart';
import '../features/session.dart';
import '../features/settings_page.dart';
import '../features/sync_page.dart';
import '../platform/desktop_mode.dart';
import '../shared/cover_art.dart';
import '../shared/playback.dart';
import '../shared/player_bar.dart';
import '../shared/queue_panel.dart';
import '../shared/seek_bar.dart';
import '../app/theme.dart';
import 'desktop_library.dart';
import 'desktop_now_playing.dart';
import 'desktop_pages.dart';
import 'desktop_player_bar.dart';
import 'desktop_sections.dart';
import 'desktop_sidebar.dart';
import 'desktop_top_bar.dart';
import 'key_bindings.dart';

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

/// Windows narrower than this collapse the sidebar into an icon rail.
const _railBelow = 960.0;

/// Windows at least this wide dock the queue beside the main column instead of
/// sliding it over as a drawer.
const _dockQueueFrom = 1280.0;

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scope = FocusNode(debugLabel: 'desktop-scope');
  final _section = ValueNotifier(DesktopSection.library);
  bool _nowPlaying = false;
  bool _queueDocked = false;
  late final _dismissNowPlaying = _DismissNowPlayingObserver(() {
    if (mounted && _nowPlaying) setState(() => _nowPlaying = false);
  });

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
    _section.dispose();
    super.dispose();
  }

  void _go(DesktopSection section) {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _nowPlaying = false;
      _section.value = section;
    });
  }

  void _openPlaylist(String id) {
    ref.read(searchProvider.notifier).clearResults();
    final library = ref.read(libraryProvider);
    if (library.selectedPlaylistId != id || !library.loaded) {
      ref.read(libraryProvider.notifier).selectPlaylist(id);
    }
    _go(DesktopSection.library);
  }

  void _toggleQueue() {
    if (MediaQuery.sizeOf(context).width >= _dockQueueFrom) {
      setState(() => _queueDocked = !_queueDocked);
    } else {
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  void _closeOverlay() {
    if (_nowPlaying) {
      setState(() => _nowPlaying = false);
      return;
    }
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isEndDrawerOpen ?? false) {
      scaffold!.closeEndDrawer();
      return;
    }
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
      return;
    }
    _navigatorKey.currentState?.maybePop();
  }

  Future<void> _playSelected() async {
    final search = ref.read(searchProvider);
    final transport = ref.read(transportProvider);
    if (_section.value == DesktopSection.discover &&
        search.submitted &&
        search.error.isEmpty) {
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
          SearchIntent: _GuardedAction(
            () => ref.read(searchFocusProvider).requestFocus(),
          ),
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
              return _frame(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _frame(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final rail = width < _railBelow;
    final dockQueue = _queueDocked && width >= _dockQueueFrom;
    final section = _section.value;
    Widget sidebar() => DesktopSidebar(
      section: section,
      onSection: _go,
      onPlaylist: _openPlaylist,
    );
    return FeatureNavigation(
      navigatorKey: _navigatorKey,
      pageBuilder: (context, title, body) =>
          DesktopFeaturePage(title: title, body: body),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: context.zero.canvas,
        drawer: rail ? Drawer(width: 280, child: sidebar()) : null,
        endDrawer: Drawer(
          width: 380,
          backgroundColor: context.zero.surface,
          child: const SafeArea(child: QueuePanel()),
        ),
        body: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rail)
                    DesktopRail(
                      section: section,
                      onSection: _go,
                      onExpand: () => _scaffoldKey.currentState?.openDrawer(),
                    )
                  else
                    SizedBox(width: 240, child: sidebar()),
                  VerticalDivider(
                    width: 1,
                    color: context.zero.line.withValues(alpha: 0.6),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            DesktopTopBar(
                              onSearch: () => _go(DesktopSection.discover),
                            ),
                            Expanded(child: _navigator()),
                          ],
                        ),
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween(
                                      begin: const Offset(0, 0.04),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: _nowPlaying
                                ? DesktopNowPlaying(
                                    key: const Key('desktop-now-playing'),
                                    onClose: () =>
                                        setState(() => _nowPlaying = false),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (dockQueue) ...[
                    VerticalDivider(
                      width: 1,
                      color: context.zero.line.withValues(alpha: 0.6),
                    ),
                    SizedBox(
                      width: 340,
                      child: Material(
                        color: context.zero.surface,
                        child: const QueuePanel(key: Key('docked-queue')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            DesktopPlayerBar(
              nowPlaying: _nowPlaying,
              queueOpen: dockQueue,
              onNowPlaying: () => setState(() => _nowPlaying = !_nowPlaying),
              onQueue: _toggleQueue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigator() => Navigator(
    key: _navigatorKey,
    observers: [_dismissNowPlaying],
    onGenerateRoute: (_) => MaterialPageRoute(
      builder: (context) => ValueListenableBuilder<DesktopSection>(
        valueListenable: _section,
        builder: (context, section, _) => Material(
          color: context.zero.canvas,
          child: switch (section) {
            DesktopSection.library => const DesktopLibraryView(),
            DesktopSection.discover => const DesktopDiscoverPage(),
            DesktopSection.downloads => const DesktopSectionPage(
              title: '下载管理',
              subtitle: '下载任务、失败原因与已下载的内容',
              body: DownloadsBody(),
            ),
            DesktopSection.sync => const DesktopSectionPage(
              title: '曲库同步',
              subtitle: '歌单与注释的跨设备同步、冲突处理',
              body: SyncBody(),
            ),
            DesktopSection.accounts => const DesktopSectionPage(
              title: '账号与登录',
              subtitle: '平台账号状态；未登录也可以播放公开内容',
              body: AccountsBody(),
            ),
            DesktopSection.settings => const DesktopSectionPage(
              title: '设置',
              subtitle: '播放、外观、快捷键与窗口行为',
              body: SettingsBody(),
            ),
          },
        ),
      ),
    ),
  );
}

/// The now-playing view lives above the nested feature navigator. A feature
/// opened from it would otherwise be hidden behind the view.
class _DismissNowPlayingObserver extends NavigatorObserver {
  _DismissNowPlayingObserver(this.onPush);

  final VoidCallback onPush;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) onPush();
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
    return PlayerCard(
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
                  icon: Icon(AppIcons.previous),
                ),
                PlayPauseButton(),
                IconButton(
                  tooltip: '下一首',
                  onPressed: transport.next,
                  icon: Icon(AppIcons.next),
                ),
                IconButton(
                  tooltip: '恢复',
                  onPressed: DesktopMode.restore,
                  icon: Icon(AppIcons.expandWindow),
                ),
                IconButton(
                  key: Key('quit'),
                  tooltip: '退出',
                  onPressed: () => ref.read(quitActionProvider)(),
                  icon: Icon(AppIcons.close),
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
