import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/icons.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../features/content_pages.dart';
import '../features/navigation.dart';
import '../features/playback_clip.dart';
import '../features/session.dart';
import '../platform/desktop_mode.dart';
import '../shared/cover_art.dart';
import '../shared/playback.dart';
import '../shared/player_bar.dart';
import '../shared/seek_bar.dart';

/// Docked transport for the desktop window: track on the left, controls and
/// progress in the middle, view toggles and volume on the right.
class DesktopPlayerBar extends ConsumerWidget {
  const DesktopPlayerBar({
    required this.nowPlaying,
    required this.queueOpen,
    required this.onNowPlaying,
    required this.onQueue,
    super.key,
  });

  final bool nowPlaying;
  final bool queueOpen;
  final VoidCallback onNowPlaying;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final transport = ref.read(transportProvider);
    return Material(
      color: context.zero.canvas,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.zero.line)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final trackWidth = (width * 0.28).clamp(180.0, 340.0);
            final wide = width >= 1080;
            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 84),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: trackWidth,
                      child: _TrackInfo(onOpen: onNowPlaying),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Transport(
                                mode: view.snapshot.mode.value,
                                compact: width < 760,
                              ),
                              _CompactSeek(
                                positionMs: view.snapshot.positionMs,
                                durationMs: view.snapshot.durationMs,
                                onSeek: transport.seek,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _Toggle(
                      tooltip: nowPlaying ? '收起正在播放' : '歌词与正在播放',
                      icon: AppIcons.lyrics,
                      selected: nowPlaying,
                      onPressed: onNowPlaying,
                    ),
                    _Toggle(
                      key: const Key('queue-button'),
                      tooltip: '队列',
                      icon: AppIcons.queue,
                      selected: queueOpen,
                      onPressed: onQueue,
                    ),
                    if (wide)
                      const VolumeControl()
                    else
                      _VolumePercent(view: view),
                    if (width >= 860)
                      IconButton(
                        tooltip: '迷你播放器',
                        onPressed: DesktopMode.enterMini,
                        icon: const Icon(AppIcons.pip, size: 18),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrackInfo extends ConsumerWidget {
  const _TrackInfo({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final song = view.snapshot.current;
    final clip = ref.watch(displayedClipProvider);
    final clipLine = clip == null
        ? null
        : playbackClipSubtitle(
            clipStartMs: clip.startMs,
            clipEndMs: clip.endMs,
            positionMs: view.snapshot.positionMs,
          );
    final buffering = view.snapshot.state == PlaybackStatus.valueBuffering;
    final notice = view.noticeLevel == 'error' ? '' : view.notice;
    final noticeStyle = TextStyle(color: context.zero.warning, fontSize: 11.5);
    return Row(
      children: [
        Tooltip(
          message: '展开正在播放',
          child: InkWell(
            key: const Key('open-player'),
            borderRadius: BorderRadius.circular(8),
            onTap: onOpen,
            child: CoverArt(cover: song?.cover ?? '', size: 52, radius: 8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onOpen,
                child: Text(
                  song?.title.isNotEmpty == true ? song!.title : '未在播放',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.zero.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (clipLine != null)
                Text(
                  clipLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.zero.accent, fontSize: 12),
                )
              else if (song != null && song.artist.isNotEmpty)
                Tooltip(
                  message: '查看作者主页',
                  child: InkWell(
                    onTap: () =>
                        openAuthors(context, ref.read(coreApiProvider), song),
                    child: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.zero.muted, fontSize: 12),
                    ),
                  ),
                ),
              if (buffering || notice.isNotEmpty)
                Row(
                  children: [
                    if (buffering)
                      Text(
                        '缓冲中',
                        key: const Key('buffering-label'),
                        style: noticeStyle,
                      ),
                    if (buffering && notice.isNotEmpty)
                      Text(' · ', style: noticeStyle),
                    if (notice.isNotEmpty)
                      Flexible(
                        child: Text(
                          notice,
                          key: const Key('player-notice'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: noticeStyle,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport({required this.mode, required this.compact});

  final String mode;

  /// Narrow windows keep only previous / play / next.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transport = ref.read(transportProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!compact) ...[
          const RestartButton(key: Key('player-bar-restart'), iconSize: 18),
          const SizedBox(width: 4),
        ],
        IconButton(
          tooltip: '上一首',
          iconSize: 20,
          onPressed: transport.previous,
          icon: const Icon(AppIcons.previous),
        ),
        const SizedBox(width: 6),
        const PlayPauseButton(size: 40, iconSize: 18, filled: true),
        const SizedBox(width: 6),
        IconButton(
          tooltip: '下一首',
          iconSize: 20,
          onPressed: transport.next,
          icon: const Icon(AppIcons.next),
        ),
        if (!compact) ...[
          const SizedBox(width: 4),
          PlaybackModeButton(mode: mode, compact: true),
        ],
      ],
    );
  }
}

class _CompactSeek extends StatelessWidget {
  const _CompactSeek({
    required this.positionMs,
    required this.durationMs,
    required this.onSeek,
  });

  final int positionMs;
  final int durationMs;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),
      child: SizedBox(
        height: 28,
        child: SeekBar(
          positionMs: positionMs,
          durationMs: durationMs,
          onSeek: onSeek,
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      style: IconButton.styleFrom(
        backgroundColor: selected ? context.zero.accentSoft : null,
      ),
      selectedIcon: Icon(icon, size: 18, color: context.zero.accent),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
    );
  }
}

class _VolumePercent extends ConsumerWidget {
  const _VolumePercent({required this.view});

  final PlayerView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transport = ref.read(transportProvider);
    final volume = view.snapshot.volume.clamp(0.0, 1.0);
    return Tooltip(
      message: '滚动或使用 +/- 调整音量',
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            perform(
              context,
              () =>
                  transport.bumpVolume(event.scrollDelta.dy < 0 ? 0.05 : -0.05),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                view.snapshot.muted ? AppIcons.volumeOff : AppIcons.volume,
                size: 18,
                color: context.zero.muted,
              ),
              const SizedBox(width: 4),
              Text(
                '${(volume * 100).round()}%',
                key: const Key('volume-label'),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: context.zero.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
