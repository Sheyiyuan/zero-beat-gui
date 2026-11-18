import '../features/navigation.dart';
import '../features/content_pages.dart';
import 'package:flutter/material.dart';
import '../app/theme.dart';

import '../shared/search_box.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        Text('发现', style: TextStyle(fontSize: 22, color: context.zero.text)),
        ListTile(
          title: const Text('热门电台与公开主页'),
          leading: const Icon(Icons.podcasts),
          onTap: () => openFeature(context, '发现与电台', const BrowseRootsBody()),
        ),
        SizedBox(height: 16),
        SearchBox(),
        SizedBox(height: 16),
        SearchBody(),
      ],
    );
  }
}
