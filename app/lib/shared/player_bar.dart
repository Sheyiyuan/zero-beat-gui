import '../features/song_actions.dart';
import '../features/content_pages.dart';
import '../features/lyrics_page.dart';
import '../features/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../features/session.dart';
import 'playback.dart';
import 'seek_bar.dart';

class _CompactNotice extends ConsumerWidget {
  const _CompactNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final host = ref.watch(playbackHostProvider);
    if (host == null) return _line(context, view, '');
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) => _line(
        context,
        view,
        (host.focusNotice.isNotEmpty ? host.focusNotice : host.loudnormNotice),
      ),
    );
  }

  Widget _line(BuildContext context, PlayerView view, String hostNotice) {
    final buffering = view.snapshot.state == PlaybackStatus.valueBuffering;
    final text = buffering
        ? '缓冲中'
        : view.notice.isNotEmpty
        ? view.notice
        : hostNotice;
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
  const PlayPauseButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = isPlaying(ref.watch(playerProvider));
    final label = playing ? '暂停' : '播放';
    return IconButton(
      key: Key('play-pause'),
      tooltip: label,
      onPressed: () => ref.read(transportProvider).toggle(),
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
    );
  }
}

class PlayerNotices extends ConsumerWidget {
  const PlayerNotices({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final host = ref.watch(playbackHostProvider);
    final buffering = view.snapshot.state == PlaybackStatus.valueBuffering;
    final notice = view.notice;
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
        if (host != null)
          ListenableBuilder(
            listenable: host,
            builder: (context, _) {
              if ((host.focusNotice.isNotEmpty
                      ? host.focusNotice
                      : host.loudnormNotice)
                  .isEmpty) {
                return const SizedBox.shrink();
              }
              return Text(
                (host.focusNotice.isNotEmpty
                    ? host.focusNotice
                    : host.loudnormNotice),
                key: Key('loudnorm-notice'),
                style: TextStyle(color: context.zero.warning),
              );
            },
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
    final title = song?.title.isNotEmpty == true ? song!.title : '未在播放';
    final artist = song?.artist ?? '';
    final transport = ref.read(transportProvider);
    final titleButton = InkWell(
      key: Key('open-player'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14),
          ),
          if (artist.isNotEmpty)
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.zero.muted, fontSize: 12),
            ),
        ],
      ),
    );
    if (compact) {
      return Material(
        color: context.zero.surface,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              SizedBox(width: 12),
              CoverArt(cover: song?.cover ?? '', size: 40),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleButton, const _CompactNotice()],
                ),
              ),
              PlayPauseButton(),
              IconButton(
                key: Key('queue-button'),
                tooltip: '队列',
                onPressed: onQueue,
                icon: Icon(Icons.queue_music),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: context.zero.surface,
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
                    titleButton,
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
                icon: Icon(Icons.skip_previous),
              ),
              PlayPauseButton(),
              IconButton(
                tooltip: '下一首',
                onPressed: transport.next,
                icon: Icon(Icons.skip_next),
              ),
              SizedBox(
                width: 120,
                child: Slider(
                  value: view.snapshot.volume.clamp(0, 1).toDouble(),
                  activeColor: context.zero.accent,
                  onChanged: (value) => ref
                      .read(playerProvider.notifier)
                      .show(playerViewWithVolume(view, value)),
                  onChangeEnd: transport.setVolume,
                ),
              ),
              IconButton(
                key: Key('queue-button'),
                tooltip: '队列',
                onPressed: onQueue,
                icon: Icon(Icons.queue_music),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CoverArt extends StatelessWidget {
  const CoverArt({required this.cover, required this.size, super.key});

  final String cover;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(cover);
    final remote =
        uri != null && (uri.isScheme('http') || uri.isScheme('https'));
    return ClipRRect(
      borderRadius: BorderRadius.circular(size >= 160 ? 20 : 10),
      child: SizedBox(
        width: size,
        height: size,
        child: remote
            ? Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _placeholder(context),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: context.zero.accentSoft,
      child: Center(child: Icon(Icons.album, color: context.zero.accent)),
    );
  }
}

class NowPlayingBody extends ConsumerWidget {
  const NowPlayingBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(playerProvider);
    final song = view.snapshot.current;
    final transport = ref.read(transportProvider);
    final width = MediaQuery.sizeOf(context).width;
    final cover = (width - 80).clamp(180.0, 320.0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        Center(
          child: CoverArt(cover: song?.cover ?? '', size: cover),
        ),
        const SizedBox(height: 28),
        Text(
          song?.title.isNotEmpty == true ? song!.title : '未在播放',
          style: TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: context.zero.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          song?.artist ?? '',
          style: TextStyle(fontSize: 16, color: context.zero.muted),
        ),
        if (song != null)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () =>
                    openAuthors(context, ref.read(coreApiProvider), song),
                child: const Text('作者'),
              ),
              TextButton(
                onPressed: () => openFeature(
                  context,
                  '${song.title} · 歌词',
                  LyricsBody(song: song),
                ),
                child: const Text('歌词'),
              ),
              TextButton(
                onPressed: () =>
                    openFeature(context, '片段编辑', ClipEditor(song: song)),
                child: const Text('片段'),
              ),
              SongActions(song: song),
            ],
          ),
        const SizedBox(height: 12),
        PlayerNotices(),
        SeekBar(
          positionMs: view.snapshot.positionMs,
          durationMs: view.snapshot.durationMs,
          onSeek: transport.seek,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '上一首',
              iconSize: 32,
              onPressed: transport.previous,
              icon: const Icon(Icons.skip_previous),
            ),
            const PlayPauseButton(),
            IconButton(
              tooltip: '下一首',
              iconSize: 32,
              onPressed: transport.next,
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Center(child: _ModeButton(mode: view.snapshot.mode.value)),
      ],
    );
  }
}

class _ModeButton extends ConsumerWidget {
  const _ModeButton({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, label, next) = switch (mode) {
      'list_loop' => (Icons.repeat, '列表循环', 'loop_one'),
      'loop_one' => (Icons.repeat_one, '单曲循环', 'shuffle'),
      'shuffle' => (Icons.shuffle, '随机播放', 'ordered'),
      _ => (Icons.playlist_play, '顺序播放', 'list_loop'),
    };
    return TextButton.icon(
      key: const Key('playback-mode'),
      onPressed: () => ref.read(transportProvider).setPlaybackMode(next),
      icon: Icon(icon, color: context.zero.accent),
      label: Text(label),
    );
  }
}
