import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/icons.dart';
import '../app/theme.dart';

/// music.163.com's image CDN rejects any User-Agent containing "Dart"
/// (`ua_acl.access` → 403 HTML). [Image.network] always sends that agent and
/// cannot replace it, so covers are fetched with a browser agent instead.
final HttpClient _coverHttpClient = HttpClient()
  ..userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

@immutable
class CoverImageProvider extends ImageProvider<CoverImageProvider> {
  const CoverImageProvider(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  @override
  Future<CoverImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CoverImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CoverImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<CoverImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _load(
    CoverImageProvider key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      final resolved = Uri.base.resolve(key.url);
      final request = await _coverHttpClient.getUrl(resolved);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<List<int>>(<int>[]);
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: resolved,
        );
      }
      final bytes = await consolidateHttpClientResponseBytes(
        response,
        onBytesReceived: (cumulative, total) {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: cumulative,
              expectedTotalBytes: total,
            ),
          );
        },
      );
      if (bytes.isEmpty) {
        throw StateError('封面响应是空的: $resolved');
      }
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (error) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }

  @override
  bool operator ==(Object other) {
    return other is CoverImageProvider &&
        other.url == url &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);
}

/// NetEase originals are often multi-megabyte progressive JPEGs, and Android
/// blocks cleartext HTTP. Ask the CDN for a small HTTPS rendition so list
/// thumbnails and the now-playing cover can actually decode.
String coverImageUrl(String raw) {
  var url = raw.trim();
  if (url.startsWith('//')) url = 'https:$url';
  if (url.startsWith('http://') && url.contains('music.126.net')) {
    url = 'https://${url.substring('http://'.length)}';
  }
  final host = Uri.tryParse(url)?.host ?? '';
  if (!host.endsWith('music.126.net') || url.contains('param=')) return url;
  return url.contains('?') ? '$url&param=640y640' : '$url?param=640y640';
}

class CoverArt extends StatelessWidget {
  const CoverArt({
    required this.cover,
    required this.size,
    this.radius,
    super.key,
  });

  final String cover;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final requested = coverImageUrl(cover);
    final uri = Uri.tryParse(requested);
    final remote =
        uri != null && (uri.isScheme('http') || uri.isScheme('https'));
    // Covers are square or 16:9 (video sources); decode wide enough that a
    // 16:9 frame still fills the square crop without upscaling.
    final decodeWidth = (size * MediaQuery.devicePixelRatioOf(context) * 1.8)
        .ceil();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? (size >= 160 ? 20 : 10)),
      child: SizedBox(
        width: size,
        height: size,
        child: remote
            ? Image(
                image: ResizeImage.resizeIfNeeded(
                  decodeWidth,
                  null,
                  CoverImageProvider(requested),
                ),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, synchronous) {
                  if (synchronous) return child;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _placeholder(context),
                      AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 180),
                        child: child,
                      ),
                    ],
                  );
                },
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
      child: Center(
        child: Icon(
          AppIcons.album,
          size: (size * 0.42).clamp(16.0, 64.0),
          color: context.zero.accent,
        ),
      ),
    );
  }
}
