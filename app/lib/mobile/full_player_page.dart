import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../shared/player_bar.dart';

class FullPlayerPage extends StatelessWidget {
  const FullPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zero.canvas,
      appBar: AppBar(
        backgroundColor: context.zero.canvas,
        foregroundColor: context.zero.text,
        title: Text('正在播放'),
      ),
      body: NowPlayingBody(),
    );
  }
}
