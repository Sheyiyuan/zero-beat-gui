import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';

import '../app/icons.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../features/content_pages.dart';
import '../features/lyrics_page.dart';
import '../features/navigation.dart';
import '../features/playback_clip.dart';
import '../features/session.dart';
import '../features/song_actions.dart';
import '../shared/cover_art.dart';
import '../shared/playback.dart';
import '../shared/song_tile.dart';
import 'desktop_pages.dart';

/// Expanded now-playing view. It covers only the main column: the sidebar
/// and the docked player bar keep working underneath, so it carries no
/// transport controls of its own.
class DesktopNowPlaying extends ConsumerWidget {
  const DesktopNowPlaying({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerProvider.select((v) => v.snapshot.current));
    return Material(
      color: context.zero.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageTitle(
            title: '正在播放',
            actions: [
              IconButton(
                key: const Key('now-playing-close'),
                tooltip: '收起',
                onPressed: onClose,
                icon: const Icon(AppIcons.expand),
              ),
            ],
          ),
          Expanded(
            child: song == null
                ? Center(
                    child: Text(
                      '未在播放，双击曲库中的歌曲开始播放',
                      style: TextStyle(color: context.zero.muted),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 820;
                      final details = _Details(song: song, wide: wide);
                      final tabs = _Tabs(key: ValueKey(song.id), song: song);
                      if (wide) {
                        final side = (constraints.maxWidth * 0.36).clamp(
                          280.0,
                          400.0,
                        );
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            desktopPageInset,
                            0,
                            desktopPageInset,
                            16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: side,
                                child: SingleChildScrollView(child: details),
                              ),
                              const SizedBox(width: 40),
                              Expanded(child: tabs),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          desktopPageInset,
                          0,
                          desktopPageInset,
                          12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            const SizedBox(height: 12),
                            Expanded(child: tabs),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.song, required this.wide});

  final Song song;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(displayedClipProvider);
    final position = ref.watch(
      playerProvider.select((v) => v.snapshot.positionMs),
    );
    final clipLine = clip == null
        ? null
        : playbackClipSubtitle(
            clipStartMs: clip.startMs,
            clipEndMs: clip.endMs,
            positionMs: position,
          );
    final actionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          song.title.isNotEmpty ? song.title : '未知曲目',
          key: const Key('now-playing-title'),
          maxLines: wide ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.zero.text,
            fontSize: wide ? 26 : 22,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (song.artist.isNotEmpty)
              Text(
                song.artist,
                style: TextStyle(fontSize: 15, color: context.zero.muted),
              ),
            SourcePill(
              key: const Key('now-playing-source'),
              source: song.source,
              label: sourceLabel(song.source),
              fontSize: 12,
            ),
          ],
        ),
        if (clipLine != null) ...[
          const SizedBox(height: 8),
          Text(
            clipLine,
            style: TextStyle(color: context.zero.accent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              style: actionStyle,
              onPressed: () =>
                  openAuthors(context, ref.read(coreApiProvider), song),
              icon: const Icon(AppIcons.person, size: 16),
              label: const Text('作者'),
            ),
            OutlinedButton.icon(
              style: actionStyle,
              onPressed: () =>
                  openFeature(context, '片段编辑', ClipEditor(song: song)),
              icon: const Icon(AppIcons.clip, size: 16),
              label: const Text('片段'),
            ),
            SongActions(song: song),
          ],
        ),
      ],
    );
    if (!wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverArt(cover: song.cover, size: 132, radius: 12),
          const SizedBox(width: 20),
          Expanded(child: info),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverArt(cover: song.cover, size: constraints.maxWidth, radius: 16),
          const SizedBox(height: 24),
          info,
        ],
      ),
    );
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs({required this.song, super.key});

  final Song song;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final online = song.source.value != 'local';
    final labels = [
      '歌词',
      if (online) ...['评论', '相关推荐'],
    ];
    final tab = _tab.clamp(0, labels.length - 1);
    final body = switch (tab) {
      1 => ContentBody(song: song),
      2 => ContentBody(song: song, related: true),
      _ => LyricsBody(song: song),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: InkWell(
                  key: Key('now-playing-tab-$i'),
                  onTap: () => setState(() => _tab = i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: i == tab
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == tab
                                ? context.zero.accent
                                : context.zero.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 2,
                          width: i == tab ? 20 : 0,
                          color: context.zero.accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        Divider(height: 1, color: context.zero.line.withValues(alpha: 0.6)),
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: KeyedSubtree(key: ValueKey(tab), child: body),
          ),
        ),
      ],
    );
  }
}
