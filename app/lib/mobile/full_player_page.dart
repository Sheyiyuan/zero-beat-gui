import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../features/session.dart';
import '../shared/cover_art.dart';
import '../shared/player_bar.dart';

class FullPlayerPage extends ConsumerWidget {
  const FullPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(
      playerProvider.select((view) => view.snapshot.current?.cover ?? ''),
    );
    return Stack(
      children: [
        Positioned.fill(child: CoverBackdrop(cover: cover)),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            foregroundColor: context.zero.text,
            title: const Text('正在播放'),
          ),
          body: const NowPlayingBody(),
        ),
      ],
    );
  }
}

ColorFilter _saturate(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final i = 1 - s;
  return ColorFilter.matrix([
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0, //
    r * i, g * i, b * i + s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
}

/// Soft wash of the current cover behind the now-playing page. The image is
/// decoded at a tiny size, so the blur stays cheap, and it fades into the
/// canvas before the text and controls start.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({required this.cover, super.key});

  final String cover;

  @override
  Widget build(BuildContext context) {
    final canvas = context.zero.canvas;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final requested = coverImageUrl(cover);
    final uri = Uri.tryParse(requested);
    final remote =
        uri != null && (uri.isScheme('http') || uri.isScheme('https'));
    return RepaintBoundary(
      child: ColoredBox(
        color: canvas,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: remote
                  ? Opacity(
                      key: ValueKey(requested),
                      opacity: dark ? 0.6 : 0.55,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: 40,
                          sigmaY: 40,
                          tileMode: TileMode.clamp,
                        ),
                        child: ColorFiltered(
                          colorFilter: _saturate(1.6),
                          child: Image(
                            image: ResizeImage.resizeIfNeeded(
                              48,
                              null,
                              CoverImageProvider(requested),
                            ),
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-cover')),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.45, 0.8],
                  colors: [
                    canvas.withValues(alpha: dark ? 0.15 : 0.1),
                    canvas.withValues(alpha: dark ? 0.55 : 0.6),
                    canvas,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
