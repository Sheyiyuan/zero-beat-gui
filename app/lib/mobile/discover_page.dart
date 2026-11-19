import '../app/chrome.dart';
import '../features/navigation.dart';
import '../features/content_pages.dart';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import '../app/theme.dart';

import '../shared/search_box.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const PageHeader(title: '发现', subtitle: '搜索哔哩哔哩、网易云与本机歌曲。'),
        SearchBox(),
        const SizedBox(height: 12),
        SearchBody(),
        const SizedBox(height: 12),
        const GroupLabel('继续浏览'),
        InsetGroup(
          children: [
            ListTile(
              title: const Row(
                children: [Text('电台与公开主页'), SizedBox(width: 8), _BetaMark()],
              ),
              subtitle: const Text('电台、歌手和用户的公开内容'),
              leading: const Icon(AppIcons.podcast),
              trailing: const Icon(AppIcons.chevronRight, size: 18),
              onTap: () =>
                  openFeature(context, '发现与电台', const BrowseRootsBody()),
            ),
          ],
        ),
      ],
    );
  }
}

class _BetaMark extends StatelessWidget {
  const _BetaMark();

  @override
  Widget build(BuildContext context) {
    final color = context.zero.warning;
    return Semantics(
      label: 'Beta，未完成',
      container: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              'Beta',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
