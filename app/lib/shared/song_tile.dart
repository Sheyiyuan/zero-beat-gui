import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:zero_beat_core/zero_beat_core.dart';

import '../app/theme.dart';
import 'brand_mark.dart';
import 'cover_art.dart';
import 'playback.dart';

/// Small source badge shared by song rows and the now-playing panel so platform
/// names keep the same shape and colors everywhere.
class SourcePill extends StatelessWidget {
  const SourcePill({
    required this.source,
    this.label,
    this.fontSize = 11,
    super.key,
  });

  final SourceID source;
  final String? label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.zero.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label ?? sourceShortLabel(source),
          style: TextStyle(fontSize: fontSize, color: context.zero.accent),
        ),
      ),
    );
  }
}

/// Compact source badge for song and playlist rows. The rendered form is an
/// icon only, but the full platform name stays in the tooltip and semantics so
/// the compact rows remain understandable without adding text everywhere.
class PlatformSourceIcon extends StatelessWidget {
  const PlatformSourceIcon({required this.source, this.size = 18, super.key});

  final SourceID source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = sourceLabel(source);
    final branded = BrandMark.supports(source.value);
    final color = branded
        ? BrandMark.colors[source.value]!
        : context.zero.muted;
    return Tooltip(
      message: label,
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        label: '来源：$label',
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: branded
              ? BrandMark(
                  source: source.value,
                  size: size * (size >= 32 ? 0.5 : 0.62),
                  color: color,
                  excludeFromSemantics: true,
                )
              : Icon(AppIcons.local, size: size * 0.68, color: color),
        ),
      ),
    );
  }
}

/// Source badge for playlist rows. The mark still says where a list came from;
/// the color is the theme accent so the library reads as one collection.
class PlaylistSourceIcon extends StatelessWidget {
  const PlaylistSourceIcon({required this.playlist, this.size = 18, super.key});

  final Playlist playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = context.zero.accent;
    if (playlist.kind.value == 'mixin') {
      return _PlaylistBadge(
        icon: AppIcons.mixed,
        color: color,
        label: '混合歌单',
        size: size,
      );
    }
    if (playlist.kind.value == 'remote' &&
        BrandMark.supports(playlist.source.value)) {
      return _PlaylistBadge(
        brand: playlist.source.value,
        color: color,
        label: sourceLabel(playlist.source),
        semanticsLabel: '来源：${sourceLabel(playlist.source)}',
        size: size,
      );
    }
    return _PlaylistBadge(
      icon: AppIcons.folder,
      color: color,
      label: '本机歌单',
      size: size,
    );
  }
}

class _PlaylistBadge extends StatelessWidget {
  const _PlaylistBadge({
    this.icon,
    this.brand,
    required this.color,
    required this.label,
    this.semanticsLabel,
    required this.size,
  });

  final IconData? icon;
  final String? brand;
  final Color color;
  final String label;
  final String? semanticsLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mark =
        size *
        (size >= 32
            ? 0.5
            : brand != null
            ? 0.62
            : 0.68);
    return Tooltip(
      message: label,
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        label: semanticsLabel ?? label,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: brand != null
              ? BrandMark(
                  source: brand!,
                  size: mark,
                  color: color,
                  excludeFromSemantics: true,
                )
              : Icon(icon, size: mark, color: color),
        ),
      ),
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile({
    required this.song,
    this.selected = false,
    this.current = false,
    this.onTap,
    this.onPlay,
    this.onLongPress,
    this.onSecondaryTap,
    this.doubleTapToPlay = true,
    this.trailing,
    super.key,
  });

  final Song song;
  final bool selected;
  final bool current;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onLongPress;
  final ValueChanged<Offset>? onSecondaryTap;
  final bool doubleTapToPlay;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = '${song.title}，${song.artist}，${sourceLabel(song.source)}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        selected: selected,
        button: onTap != null,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Material(
          color: selected ? context.zero.accentSoft : Colors.transparent,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    _SongCover(song: song, current: current),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        excludeFromSemantics: true,
                        onDoubleTap: doubleTapToPlay ? onPlay : null,
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                key: ValueKey('title-${song.id}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: current
                                      ? context.zero.accent
                                      : context.zero.text,
                                  fontSize: 15,
                                  fontWeight: current
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  PlatformSourceIcon(
                                    key: ValueKey('song-source-${song.id}'),
                                    source: song.source,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${song.artist} · ${formatClock(song.durationMs)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.zero.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (onPlay != null)
                      IconButton(
                        tooltip: '播放',
                        onPressed: onPlay,
                        icon: const Icon(AppIcons.play),
                      ),
                    ?trailing,
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

/// Square cover thumbnail for song rows. The playing track gets a scrim with
/// a waveform glyph on top of its cover instead of an extra icon in the title.
class _SongCover extends StatelessWidget {
  const _SongCover({required this.song, required this.current});

  static const size = 44.0;

  final Song song;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final cover = CoverArt(
      key: ValueKey('song-cover-${song.id}'),
      cover: song.cover,
      size: size,
      radius: 8,
    );
    if (!current) return cover;
    return Stack(
      children: [
        cover,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              AppIcons.waveform,
              key: Key('song-current-mark'),
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '这里还没有歌曲',
              key: Key('empty-library'),
              style: TextStyle(fontSize: 18, color: context.zero.text),
            ),
            SizedBox(height: 8),
            Text(
              '搜索歌曲或打开歌曲链接后，选择「加入歌单」。也可以导入平台歌单或添加本地文件夹。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.zero.muted),
            ),
          ],
        ),
      ),
    );
  }
}
