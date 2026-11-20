import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';

import '../app/icons.dart';
import '../app/theme.dart';
import '../features/library_actions.dart';
import '../features/session.dart';
import '../shared/playback.dart';
import '../shared/song_tile.dart';
import 'desktop_sections.dart';

/// Full desktop sidebar: destinations, the playlist collection, and the
/// account/settings footer.
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    required this.section,
    required this.onSection,
    required this.onPlaylist,
    super.key,
  });

  final DesktopSection section;
  final SectionCallback onSection;
  final ValueChanged<String> onPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final selectedPlaylist = library.playlists
        .where((p) => p.id == library.selectedPlaylistId)
        .firstOrNull;
    return ColoredBox(
      color: context.zero.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          for (final item in DesktopSection.primary)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
              child: _NavItem(
                section: item,
                selected: section == item,
                onTap: () => onSection(item),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '歌单',
                    style: TextStyle(
                      color: context.zero.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                _SmallIconButton(
                  key: const Key('library-refresh-sidebar'),
                  tooltip: '刷新歌单',
                  onPressed: library.refreshing
                      ? null
                      : () => refreshPlaylistNow(context, ref),
                  child: library.refreshing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        )
                      : const Icon(AppIcons.refresh, size: 16),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconTheme.merge(
                    data: const IconThemeData(size: 18),
                    child: LibraryTools(playlist: selectedPlaylist),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: library.playlists.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      library.loading ? '正在读取曲库' : '还没有歌单，点击 ＋ 新建或导入',
                      style: TextStyle(color: context.zero.muted, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    key: const PageStorageKey('desktop-playlists'),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: library.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = library.playlists[index];
                      return DesktopPlaylistItem(
                        key: ValueKey('playlist-item-${playlist.id}'),
                        playlist: playlist,
                        selected:
                            section == DesktopSection.library &&
                            playlist.id == library.selectedPlaylistId,
                        onTap: () => onPlaylist(playlist.id),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: context.zero.line.withValues(alpha: 0.6)),
          _SidebarFooter(section: section, onSection: onSection),
        ],
      ),
    );
  }
}

/// Collapsed sidebar for narrow windows. Playlists move into a drawer.
class DesktopRail extends StatelessWidget {
  const DesktopRail({
    required this.section,
    required this.onSection,
    required this.onExpand,
    super.key,
  });

  final DesktopSection section;
  final SectionCallback onSection;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    Widget item(DesktopSection target) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: IconButton(
        tooltip: target.label,
        isSelected: section == target,
        style: IconButton.styleFrom(
          foregroundColor: context.zero.muted,
          backgroundColor: section == target ? context.zero.accentSoft : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        selectedIcon: Icon(target.icon, color: context.zero.accent),
        onPressed: () => onSection(target),
        icon: Icon(target.icon, size: 20),
      ),
    );
    return ColoredBox(
      color: context.zero.surface,
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            const SizedBox(height: 12),
            IconButton(
              tooltip: '展开曲库',
              onPressed: onExpand,
              icon: const Icon(AppIcons.menu, size: 20),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final target in DesktopSection.primary) item(target),
                  ],
                ),
              ),
            ),
            item(DesktopSection.accounts),
            item(DesktopSection.settings),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final DesktopSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.zero.accent : context.zero.text;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? context.zero.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('desktop-nav-${section.name}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  section.icon,
                  size: 18,
                  color: selected ? color : context.zero.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sidebar playlist entry. Right click or long press opens the same playlist
/// menu as the header's overflow button.
class DesktopPlaylistItem extends ConsumerStatefulWidget {
  const DesktopPlaylistItem({
    required this.playlist,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final Playlist playlist;
  final bool selected;
  final VoidCallback onTap;

  @override
  ConsumerState<DesktopPlaylistItem> createState() =>
      _DesktopPlaylistItemState();
}

class _DesktopPlaylistItemState extends ConsumerState<DesktopPlaylistItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final selected = widget.selected;
    final background = selected
        ? context.zero.accentSoft
        : _hover
        ? context.zero.surfaceMuted
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: ValueKey('playlist-row-${playlist.id}'),
        behavior: HitTestBehavior.opaque,
        onLongPress: () => showPlaylistMenu(context, ref, playlist),
        onSecondaryTapDown: (details) => showPlaylistMenu(
          context,
          ref,
          playlist,
          position: details.globalPosition,
        ),
        child: Semantics(
          selected: selected,
          button: true,
          label: '${playlist.title}，${playlistMeta(playlist)}',
          excludeSemantics: true,
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    PlaylistSourceIcon(
                      key: ValueKey('playlist-row-source-${playlist.id}'),
                      playlist: playlist,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        playlist.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? context.zero.accent
                              : context.zero.text,
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (playlist.frozen)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Tooltip(
                          message: '已停止同步',
                          child: Icon(
                            AppIcons.unlock,
                            size: 12,
                            color: context.zero.muted,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      '${playlist.count}',
                      style: TextStyle(
                        color: context.zero.muted,
                        fontSize: 11.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter({required this.section, required this.onSection});

  final DesktopSection section;
  final SectionCallback onSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(helloProvider).result?.accounts ?? const {};
    final signedIn = [
      for (final entry in accounts.entries)
        if (entry.value.loggedIn) accountLabel(entry.key),
    ];
    final summary = signedIn.isEmpty ? '未登录平台账号' : '已登录 ${signedIn.join('、')}';
    final accountSelected = section == DesktopSection.accounts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: '账号',
              child: Material(
                color: accountSelected
                    ? context.zero.accentSoft
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSection(DesktopSection.accounts),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: context.zero.accentSoft,
                          foregroundColor: context.zero.accent,
                          child: const Icon(AppIcons.person, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '本机曲库',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.zero.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.zero.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '设置',
            isSelected: section == DesktopSection.settings,
            selectedIcon: Icon(AppIcons.settings, color: context.zero.accent),
            onPressed: () => onSection(DesktopSection.settings),
            icon: const Icon(AppIcons.settings, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      minimumSize: const Size(32, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: child,
  );
}
