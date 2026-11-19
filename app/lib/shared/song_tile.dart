import 'package:flutter/material.dart';
import 'package:zero_beat_core/zero_beat_core.dart';

import '../app/theme.dart';
import 'playback.dart';

Widget _sourcePill(BuildContext context, Song song) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: context.zero.accentSoft,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        sourceShortLabel(song.source),
        style: TextStyle(fontSize: 11, color: context.zero.accent),
      ),
    ),
  );
}

class SongTile extends StatelessWidget {
  const SongTile({
    required this.song,
    this.selected = false,
    this.current = false,
    this.onTap,
    this.onPlay,
    this.onLongPress,
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
  final bool doubleTapToPlay;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = '${song.title}，${song.artist}，${sourceLabel(song.source)}';
    return Semantics(
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: current ? context.zero.accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
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
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${song.artist} · ${formatClock(song.durationMs)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.zero.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  _sourcePill(context, song),
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
                        icon: const Icon(Icons.play_arrow),
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
              '曲库还是空的',
              key: Key('empty-library'),
              style: TextStyle(fontSize: 18, color: context.zero.text),
            ),
            SizedBox(height: 8),
            Text(
              '这里还没有歌曲。搜索或打开链接之后，保存进曲库的内容会显示在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.zero.muted),
            ),
          ],
        ),
      ),
    );
  }
}
