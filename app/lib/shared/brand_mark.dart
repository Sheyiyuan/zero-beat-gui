import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/theme.dart';

/// Official monochrome marks for Bilibili and NetEase Cloud Music.
///
/// The SVG files are the single-color brand paths. Color is applied here so
/// the same asset works on light and dark surfaces.
class BrandMark extends StatelessWidget {
  const BrandMark({
    required this.source,
    this.size = 18,
    this.color,
    this.excludeFromSemantics = false,
    super.key,
  });

  final String source;
  final double size;
  final Color? color;
  final bool excludeFromSemantics;

  static const assets = <String, String>{
    'bilibili': 'assets/brands/bilibili.svg',
    'netease': 'assets/brands/netease.svg',
  };

  static const colors = <String, Color>{
    'bilibili': Color(0xFFFB7299),
    'netease': Color(0xFFD43C33),
  };

  static bool supports(String source) => assets.containsKey(source);

  @override
  Widget build(BuildContext context) {
    final asset = assets[source];
    if (asset == null) return SizedBox.square(dimension: size);
    final tint =
        color ??
        colors[source] ??
        IconTheme.of(context).color ??
        context.zero.text;
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      excludeFromSemantics: excludeFromSemantics,
      semanticsLabel: source == 'bilibili' ? '哔哩哔哩' : '网易云音乐',
    );
  }
}
