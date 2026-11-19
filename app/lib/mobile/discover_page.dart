import '../app/chrome.dart';
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const PageHeader(title: '发现', subtitle: '搜索哔哩哔哩、网易云和本机曲库，或从公开电台进入。'),
        SearchBox(),
        const SizedBox(height: 20),
        Text('继续浏览', style: TextStyle(color: context.zero.muted, fontSize: 13)),
        const SizedBox(height: 8),
        InsetGroup(
          children: [
            ListTile(
              title: const Text('热门电台与公开主页'),
              subtitle: const Text('电台、歌手和用户的公开内容'),
              leading: const Icon(Icons.podcasts),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  openFeature(context, '发现与电台', const BrowseRootsBody()),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SearchBody(),
      ],
    );
  }
}
