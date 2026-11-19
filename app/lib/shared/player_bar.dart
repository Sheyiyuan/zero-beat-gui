import 'dart:async';

import '../features/song_actions.dart';
import '../features/content_pages.dart';
import '../features/lyrics_page.dart';
import '../features/navigation.dart';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart' hide Clip;
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/providers.dart';
import '../engine/playback_host.dart';
import '../app/theme.dart';
import '../features/playback_clip.dart';
import '../features/session.dart';
import '../platform/system_volume.dart';
import 'playback.dart';
import 'cover_art.dart';
import 'progress_ring.dart';
import 'seek_bar.dart';
import 'song_tile.dart';
import 'swipe_to_skip.dart';
import 'track_swipe_card.dart';

class _CompactNotice extends ConsumerWidget {
  const _CompactNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _line(context, ref.watch(playerProvider));
  }

  Widget _line(BuildContext context, PlayerView view) {
    final buffering = view.snapshot.state == PlaybackStatus.valueBuffering;
    final notice = _inlineNotice(view);
    final text = buffering ? '缓冲中' : notice;
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      key: buffering ? Key('buffering-label') : Key('player-notice'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.zero.warning, fontSize: 12),
    );
  }
}

class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({
    this.size = 48,
    this.iconSize,
    this.filled = false,
    super.key,
  });

  /// Outer tap target. The compact bar uses a smaller control to match the
  /// lighter mini-player treatment; the detail page uses a larger filled disc.
  final double size;
  final double? iconSize;
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = isPlaying(ref.watch(playerProvider));
    final label = playing ? '暂停' : '播放';
    final icon = Icon(playing ? AppIcons.pause : AppIcons.play);
    final constraints = BoxConstraints.tightFor(width: size, height: size);
    void toggle() => ref.read(transportProvider).toggle();
    if (filled) {
      final scheme = Theme.of(context).colorScheme;
      return IconButton.filled(
        key: const Key('play-pause'),
        tooltip: label,
        constraints: constraints,
        padding: EdgeInsets.zero,
        iconSize: iconSize ?? size * 0.4,
        style: IconButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
        onPressed: toggle,
        icon: Icon(
          playing ? AppIcons.pause : AppIcons.play,
          color: scheme.onPrimary,
        ),
      );
    }
    return IconButton(
      key: const Key('play-pause'),
      tooltip: label,
      constraints: constraints,
      padding: EdgeInsets.zero,
      iconSize: iconSize ?? size * 0.55,
      onPressed: toggle,
      icon: icon,
    );
  }
}

/// Play/pause control wrapped in a progress ring.
///
/// Used by the bottom [PlayerBar] so the compact mobile bar and the desktop
/// player bar show position/duration at a glance. The ring is painted behind
/// the button inside the same 48px square, so it does not shift layout or
/// squeeze the neighbouring restart/queue controls.
class ProgressRingPlayButton extends ConsumerWidget {
  const ProgressRingPlayButton({
    this.size = 42,
    this.strokeWidth = 2.5,
    this.iconSize,
    super.key,
  });

  final double size;
  final double strokeWidth;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playerProvider).snapshot;
    final duration = snapshot.durationMs;
    final progress = duration > 0 ? snapshot.positionMs / duration : null;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PlayProgressRing(
            key: const Key('play-progress-ring'),
            progress: progress,
            size: size,
            strokeWidth: strokeWidth,
          ),
          PlayPauseButton(size: size, iconSize: iconSize),
        ],
      ),
    );
  }
}

/// Restarts the current track from the beginning.
class RestartButton extends ConsumerWidget {
  const RestartButton({this.iconSize, super.key});

  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: '从头播放',
      iconSize: iconSize,
      onPressed: () => ref.read(transportProvider).seek(0),
      icon: const Icon(AppIcons.restart),
    );
  }
}

/// Core playback text that still belongs on the player. Failures and the
/// host's own warnings (compensation, loudnorm, focus) use a toast instead.
String _inlineNotice(PlayerView view) {
  if (view.noticeLevel == 'error') return '';
  return view.notice;
}

/// Shows a playback failure or host warning once, off the player surfaces.
class PlaybackErrorToast extends ConsumerStatefulWidget {
  const PlaybackErrorToast({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PlaybackErrorToast> createState() => _PlaybackErrorToastState();
}

class _PlaybackErrorToastState extends ConsumerState<PlaybackErrorToast> {
  PlaybackHost? _host;
  String _lastHostNotice = '';

  @override
  void dispose() {
    _host?.removeListener(_onHostNotice);
    super.dispose();
  }

  void _attach(PlaybackHost? host) {
    if (identical(_host, host)) return;
    _host?.removeListener(_onHostNotice);
    _host = host;
    _lastHostNotice = host?.playbackNotice ?? '';
    host?.addListener(_onHostNotice);
  }

  void _onHostNotice() {
    final notice = _host?.playbackNotice ?? '';
    if (notice.isEmpty) {
      _lastHostNotice = '';
      return;
    }
    if (notice == _lastHostNotice) return;
    _lastHostNotice = notice;
    _show(notice);
  }

  void _show(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playerProvider, (previous, next) {
      if (next.noticeLevel != 'error' || next.notice.isEmpty) return;
      if (previous?.notice == next.notice && previous?.noticeLevel == 'error') {
        return;
      }
      _show(next.notice);
    });
    _attach(ref.watch(playbackHostProvider));
    return widget.child;
  }
}

class PlayerNotices extends ConsumerWidget {
  const PlayerNotices({this.suppressNotice = '', super.key});

  /// Player notice text already dismissed on this surface. Playback failures
  /// are not shown here; they use a toast.
  final String suppressNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final buffering = view.snapshot.state == PlaybackStatus.valueBuffering;
    final raw = _inlineNotice(view);
    final notice = raw == suppressNotice ? '' : raw;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (buffering)
          Text(
            '缓冲中',
            key: Key('buffering-label'),
            style: TextStyle(color: context.zero.warning),
          ),
        if (notice.isNotEmpty)
          Text(
            notice,
            key: Key('player-notice'),
            style: TextStyle(color: context.zero.warning),
          ),
      ],
    );
  }
}

/// Volume row used by the desktop overlay and the mobile full player.
///
/// Android routes the row to the real media stream (`STREAM_MUSIC`) through
/// [systemVolumeProvider]. Desktop (and any platform without the channel)
/// keeps the existing core-backed volume, so playback volume and sync data are
/// untouched there.
class VolumeControl extends ConsumerWidget {
  const VolumeControl({this.expanded = false, super.key});

  /// Stretch the slider to the available width instead of a fixed 112px.
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = ref.watch(systemVolumeProvider);
    if (system != null) {
      return _SystemVolumeControl(source: system, expanded: expanded);
    }
    return _CoreVolumeControl(expanded: expanded);
  }
}

Widget _volumeSlider({required bool expanded, required Widget slider}) =>
    expanded ? Expanded(child: slider) : SizedBox(width: 112, child: slider);

class _CoreVolumeControl extends ConsumerWidget {
  const _CoreVolumeControl({this.expanded = false});

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final snapshot = view.snapshot;
    final volume = snapshot.volume.clamp(0.0, 1.0).toDouble();
    final muted = snapshot.muted;
    final transport = ref.read(transportProvider);
    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        IconButton(
          tooltip: muted ? '取消静音' : '静音',
          visualDensity: VisualDensity.compact,
          onPressed: () => perform(
            context,
            () => ref
                .read(coreApiProvider)
                .playbackSetting('mute', muted ? 0 : 1),
          ),
          icon: Icon(muted ? AppIcons.volumeOff : AppIcons.volume),
        ),
        _volumeSlider(
          expanded: expanded,
          slider: Slider(
            key: const Key('volume-slider'),
            value: volume,
            onChanged: (value) => ref
                .read(playerProvider.notifier)
                .show(playerViewWithVolume(view, value)),
            onChangeEnd: transport.setVolume,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            muted ? '静音' : '${(volume * 100).round()}%',
            key: const Key('volume-label'),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: muted ? context.zero.muted : context.zero.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// System media volume row. It deliberately never calls
/// `CoreApi.setVolume`/`playbackSetting('mute')`: Android applies the media
/// stream volume in the system mixer, and writing core volume here would both
/// double-attenuate playback and persist an unrelated preference.
class _SystemVolumeControl extends StatefulWidget {
  const _SystemVolumeControl({required this.source, this.expanded = false});

  final SystemVolume source;
  final bool expanded;

  @override
  State<_SystemVolumeControl> createState() => _SystemVolumeControlState();
}

class _SystemVolumeControlState extends State<_SystemVolumeControl> {
  SystemVolumeState? _state;
  StreamSubscription<SystemVolumeState>? _subscription;
  int? _restoreVolume;
  int? _lastAudibleVolume;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.source.changes.listen(
      _apply,
      onError: (Object _) => _fallBack(),
    );
    _refresh();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  void _fallBack() {
    if (!mounted || _unavailable) return;
    setState(() => _unavailable = true);
  }

  Future<void> _refresh() async {
    try {
      final state = await widget.source.read();
      if (mounted) _apply(state);
    } catch (_) {
      _fallBack();
    }
  }

  void _apply(SystemVolumeState state) {
    if (!mounted || _unavailable) return;
    if (state.volume > 0) _lastAudibleVolume = state.volume;
    setState(() => _state = state);
  }

  int _indexFor(double fraction, int max) {
    if (max <= 0) return 0;
    return (fraction.clamp(0.0, 1.0) * max).round().clamp(0, max);
  }

  Future<void> _write(int index) async {
    final current = _state;
    if (current == null) return;
    final target = current.max > 0
        ? index.clamp(0, current.max)
        : index.clamp(0, 100);
    // Move the thumb immediately; the event channel confirms the final value.
    setState(
      () => _state = SystemVolumeState(volume: target, max: current.max),
    );
    try {
      await widget.source.setVolume(target);
    } catch (_) {
      if (mounted) await _refresh();
    }
  }

  Future<void> _toggleMute() async {
    final state = _state;
    if (state == null) return;
    if (state.volume > 0) {
      _restoreVolume = state.volume;
      await _write(0);
      return;
    }
    final max = state.max;
    final target =
        _restoreVolume ??
        _lastAudibleVolume ??
        (max <= 0 ? 0 : (max / 2).ceil().clamp(1, max));
    await _write(target);
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return _CoreVolumeControl(expanded: widget.expanded);
    final state = _state;
    final muted = state != null && state.volume == 0;
    final percent = state == null ? '--%' : '${state.percent}%';
    return Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('volume-mute'),
          tooltip: muted ? '取消静音' : '静音',
          visualDensity: VisualDensity.compact,
          onPressed: state == null ? null : _toggleMute,
          icon: Icon(muted ? AppIcons.volumeOff : AppIcons.volume),
        ),
        _volumeSlider(
          expanded: widget.expanded,
          slider: Slider(
            key: const Key('volume-slider'),
            value: state?.fraction ?? 0,
            onChanged: state == null
                ? null
                : (value) {
                    final index = _indexFor(value, state.max);
                    setState(
                      () => _state = SystemVolumeState(
                        volume: index,
                        max: state.max,
                      ),
                    );
                    // The system slider follows the finger, not just the
                    // release. `_write` keeps the last value if a call fails.
                    unawaited(_write(index));
                  },
            onChangeEnd: state == null
                ? null
                : (value) => _write(_indexFor(value, state.max)),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            muted ? '静音' : percent,
            key: const Key('volume-label'),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: muted ? context.zero.muted : context.zero.text,
            ),
          ),
        ),
      ],
    );
  }
}

class PlayerBar extends ConsumerWidget {
  const PlayerBar({this.compact = false, this.onOpen, this.onQueue, super.key});

  final bool compact;
  final VoidCallback? onOpen;
  final VoidCallback? onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final song = view.snapshot.current;
    final narrow = MediaQuery.sizeOf(context).width < 820;
    final clip = ref.watch(displayedClipProvider);
    final clipLine = clip != null
        ? playbackClipSubtitle(
            clipStartMs: clip.startMs,
            clipEndMs: clip.endMs,
            positionMs: view.snapshot.positionMs,
          )
        : null;
    final transport = ref.read(transportProvider);
    Widget titleFor(Song? track, {bool tappable = true}) {
      final trackTitle = track?.title.isNotEmpty == true
          ? track!.title
          : '未在播放';
      final trackArtist = track?.artist ?? '';
      final column = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            trackTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.zero.text,
            ),
          ),
          if (clipLine != null)
            Text(
              clipLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.zero.accent, fontSize: 12),
            )
          else if (trackArtist.isNotEmpty)
            Text(
              trackArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.zero.muted, fontSize: 12),
            ),
        ],
      );
      if (!tappable) return column;
      return InkWell(key: Key('open-player'), onTap: onOpen, child: column);
    }

    if (compact) {
      return PlayerCard(
        child: SizedBox(
          height: 64,
          child: SwipeToSkip(
            key: const Key('player-bar-swipe'),
            onNext: transport.next,
            onPrevious: transport.previous,
            travelExtent: 200,
            builder: (context, frame) {
              final magnitude = frame.magnitude;
              // The old track drifts out with the finger and fades; the new
              // one arrives from the side the swipe was heading towards.
              final follow =
                  frame.progress * 56 -
                  frame.switchDirection * 56 * (1 - frame.entrance);
              final opacity = ((1 - magnitude) * frame.entrance).clamp(
                0.0,
                1.0,
              );
              return Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('open-player'),
                      onTap: onOpen,
                      child: ClipRect(
                        child: Transform.translate(
                          offset: Offset(follow, 0),
                          child: Opacity(
                            opacity: opacity,
                            child: Row(
                              key: const Key('player-bar-track'),
                              children: [
                                const SizedBox(width: 10),
                                CoverArt(
                                  cover: frame.current?.cover ?? '',
                                  size: 44,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      titleFor(frame.current, tappable: false),
                                      const _CompactNotice(),
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
                  RestartButton(key: const Key('player-bar-restart')),
                  const ProgressRingPlayButton(
                    size: 32,
                    strokeWidth: 1.8,
                    iconSize: 18,
                  ),
                  IconButton(
                    key: Key('queue-button'),
                    tooltip: '队列',
                    onPressed: onQueue,
                    icon: Icon(AppIcons.queue),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
    return PlayerCard(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 112),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              CoverArt(cover: song?.cover ?? '', size: 72),
              SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    titleFor(song),
                    PlayerNotices(),
                    SeekBar(
                      positionMs: view.snapshot.positionMs,
                      durationMs: view.snapshot.durationMs,
                      onSeek: transport.seek,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '上一首',
                onPressed: transport.previous,
                icon: Icon(AppIcons.previous),
              ),
              RestartButton(key: const Key('player-bar-restart')),
              const ProgressRingPlayButton(size: 44, strokeWidth: 2.5),
              IconButton(
                tooltip: '下一首',
                onPressed: transport.next,
                icon: Icon(AppIcons.next),
              ),
              if (narrow)
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(view.snapshot.volume.clamp(0, 1) * 100).round()}%',
                    key: const Key('volume-label'),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: context.zero.muted),
                  ),
                )
              else
                const VolumeControl(),
              IconButton(
                key: Key('queue-button'),
                tooltip: '队列',
                onPressed: onQueue,
                icon: Icon(AppIcons.queue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded surface for the docked now-playing bar.
class PlayerCard extends StatelessWidget {
  const PlayerCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 2,
                  ),
                ],
        ),
        child: Material(
          color: context.zero.raised,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: dark
                ? BorderSide(color: context.zero.line.withValues(alpha: 0.5))
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class NowPlayingBody extends ConsumerWidget {
  const NowPlayingBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final song = view.snapshot.current;
    final clip = ref.watch(displayedClipProvider);
    final clipLine = clip != null
        ? playbackClipSubtitle(
            clipStartMs: clip.startMs,
            clipEndMs: clip.endMs,
            positionMs: view.snapshot.positionMs,
          )
        : null;
    final transport = ref.read(transportProvider);
    final screen = MediaQuery.sizeOf(context);
    final cover = [
      screen.width - 56,
      screen.height * 0.44,
      380.0,
    ].reduce((a, b) => a < b ? a : b).clamp(180.0, 380.0);
    final actionStyle = TextButton.styleFrom(
      foregroundColor: context.zero.text,
      backgroundColor: context.zero.surface.withValues(alpha: 0.72),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
          children: [
            Center(
              child: SwipeToSkip(
                key: const Key('now-playing-swipe'),
                onNext: transport.next,
                onPrevious: transport.previous,
                travelExtent: cover + 32,
                builder: (context, frame) => TrackSwipeCard(
                  frame: frame,
                  size: cover,
                  gap: 32,
                  coverBuilder: (context, cover, size) =>
                      CoverArt(cover: cover, size: size),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // The core confirms a swiped track a beat after the cover lands;
            // cross-fading the text hides that hand-off.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, ?current],
              ),
              child: Column(
                key: ValueKey(song?.id),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NowPlayingTitle(
                    title: song?.title.isNotEmpty == true
                        ? song!.title
                        : '未在播放',
                  ),
                  const SizedBox(height: 6),
                  if (song != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (song.artist.isNotEmpty)
                          Text(
                            song.artist,
                            style: TextStyle(
                              fontSize: 16,
                              color: context.zero.muted,
                            ),
                          ),
                        SourcePill(
                          key: const Key('now-playing-source'),
                          source: song.source,
                          label: sourceLabel(song.source),
                          fontSize: 12,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (clipLine != null) ...[
              const SizedBox(height: 8),
              Text(
                clipLine,
                style: TextStyle(color: context.zero.accent, fontSize: 14),
              ),
            ],
            if (song != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    style: actionStyle,
                    onPressed: () =>
                        openAuthors(context, ref.read(coreApiProvider), song),
                    icon: const Icon(AppIcons.person, size: 16),
                    label: const Text('作者'),
                  ),
                  TextButton.icon(
                    style: actionStyle,
                    onPressed: () => openFeature(
                      context,
                      '${song.title} · 歌词',
                      LyricsBody(song: song),
                    ),
                    icon: const Icon(AppIcons.lyrics, size: 16),
                    label: const Text('歌词'),
                  ),
                  TextButton.icon(
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
            const SizedBox(height: 16),
            PlayerNotices(),
            SeekBar(
              stacked: true,
              positionMs: view.snapshot.positionMs,
              durationMs: view.snapshot.durationMs,
              onSeek: transport.seek,
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                // Phones keep both ends of the row as plain icons so the play
                // disc stays centred; the wide desktop overlay can afford the
                // mode label.
                final compactMode = constraints.maxWidth < 440;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const RestartButton(key: Key('now-playing-restart')),
                    IconButton(
                      tooltip: '上一首',
                      iconSize: 30,
                      onPressed: transport.previous,
                      icon: const Icon(AppIcons.previous),
                    ),
                    const PlayPauseButton(size: 68, filled: true),
                    IconButton(
                      tooltip: '下一首',
                      iconSize: 30,
                      onPressed: transport.next,
                      icon: const Icon(AppIcons.next),
                    ),
                    Flexible(
                      child: _ModeButton(
                        mode: view.snapshot.mode.value,
                        compact: compactMode,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const VolumeControl(expanded: true),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingTitle extends StatefulWidget {
  const _NowPlayingTitle({required this.title});

  final String title;

  @override
  State<_NowPlayingTitle> createState() => _NowPlayingTitleState();
}

class _NowPlayingTitleState extends State<_NowPlayingTitle> {
  static const _collapsedLines = 2;
  static const _expandedMaxHeight = 160.0;

  final _titleScroll = ScrollController();
  bool _expanded = false;

  @override
  void dispose() {
    _titleScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _NowPlayingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) _expanded = false;
  }

  TextStyle _style(BuildContext context) => TextStyle(
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: context.zero.text,
  );

  bool _overflows(BuildContext context, TextStyle style, double maxWidth) {
    if (!maxWidth.isFinite) return false;
    final painter = TextPainter(
      text: TextSpan(text: widget.title, style: style),
      maxLines: _collapsedLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    final exceeds = painter.didExceedMaxLines;
    painter.dispose();
    return exceeds;
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final style = _style(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final canToggle = _overflows(context, style, constraints.maxWidth);
        final body = _expanded
            ? ConstrainedBox(
                key: const Key('now-playing-title-scroll'),
                constraints: const BoxConstraints(
                  maxHeight: _expandedMaxHeight,
                ),
                child: Scrollbar(
                  controller: _titleScroll,
                  child: SingleChildScrollView(
                    controller: _titleScroll,
                    primary: false,
                    child: Text(
                      widget.title,
                      key: const Key('now-playing-title'),
                      style: style,
                    ),
                  ),
                ),
              )
            : Text(
                widget.title,
                key: const Key('now-playing-title'),
                maxLines: _collapsedLines,
                overflow: TextOverflow.ellipsis,
                style: style,
              );
        if (!canToggle) return body;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Tooltip(
                message: _expanded ? '点击收起标题' : '点击展开完整标题',
                child: InkWell(onTap: _toggle, child: body),
              ),
            ),
            IconButton(
              key: const Key('now-playing-title-toggle'),
              tooltip: _expanded ? '收起标题' : '展开完整标题',
              visualDensity: VisualDensity.compact,
              onPressed: _toggle,
              icon: Icon(_expanded ? AppIcons.collapse : AppIcons.expand),
            ),
          ],
        );
      },
    );
  }
}

class _ModeButton extends ConsumerWidget {
  const _ModeButton({required this.mode, this.compact = false});
  final String mode;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, label, next) = switch (mode) {
      'list_loop' => (AppIcons.repeat, '列表循环', 'loop_one'),
      'loop_one' => (AppIcons.repeatOne, '单曲循环', 'shuffle'),
      'shuffle' => (AppIcons.shuffle, '随机播放', 'ordered'),
      _ => (AppIcons.ordered, '顺序播放', 'list_loop'),
    };
    void cycle() => ref.read(transportProvider).setPlaybackMode(next);
    if (compact) {
      return IconButton(
        key: const Key('playback-mode'),
        tooltip: label,
        onPressed: cycle,
        icon: Icon(icon, color: context.zero.accent),
      );
    }
    return Tooltip(
      message: label,
      child: TextButton.icon(
        key: const Key('playback-mode'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: cycle,
        icon: Icon(icon, color: context.zero.accent),
        label: Text(
          label,
          key: const Key('playback-mode-label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
