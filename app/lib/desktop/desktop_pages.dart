import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/icons.dart';
import '../app/theme.dart';
import '../features/content_pages.dart';
import '../features/navigation.dart';
import '../features/session.dart';
import '../shared/search_box.dart';

/// Horizontal inset shared by every desktop page so titles, toolbars, and
/// table rows line up down the main column.
const desktopPageInset = 32.0;

/// Readable width for forms and long lists; tables use the full column.
const desktopReadableWidth = 920.0;

class DesktopPageTitle extends StatelessWidget {
  const DesktopPageTitle({
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        desktopPageInset,
        4,
        desktopPageInset - 8,
        16,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.zero.text,
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.zero.muted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A top-level destination: title block, then the feature body in a readable
/// column.
class DesktopSectionPage extends StatelessWidget {
  const DesktopSectionPage({
    required this.title,
    required this.body,
    this.subtitle,
    this.maxWidth = desktopReadableWidth,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.zero.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageTitle(title: title, subtitle: subtitle),
          Expanded(
            child: _Readable(maxWidth: maxWidth, child: body),
          ),
        ],
      ),
    );
  }
}

/// Chrome for pages pushed with `openFeature` on desktop: an inline back
/// button and title instead of a mobile app bar.
class DesktopFeaturePage extends StatelessWidget {
  const DesktopFeaturePage({
    required this.title,
    required this.body,
    super.key,
  });

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zero.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageTitle(
            title: title,
            leading: BackButton(
              style: IconButton.styleFrom(
                backgroundColor: context.zero.surface,
              ),
            ),
          ),
          Expanded(child: _Readable(child: body)),
        ],
      ),
    );
  }
}

class _Readable extends StatelessWidget {
  const _Readable({required this.child, this.maxWidth = desktopReadableWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: desktopPageInset - 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Search results and browse entry points. The query itself lives in the top
/// bar so it stays reachable from every page.
class DesktopDiscoverPage extends ConsumerWidget {
  const DesktopDiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(searchProvider);
    final showing = search.submitted || search.loading;
    return Material(
      color: context.zero.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageTitle(
            title: showing ? '搜索「${search.keyword}」' : '发现',
            subtitle: showing
                ? '哔哩哔哩、网易云与本机曲库的结果'
                : '在上方输入关键词搜索，或粘贴歌曲、歌单、主页链接直接打开。',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              desktopPageInset,
              0,
              desktopPageInset,
              12,
            ),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: SearchSourceChips(),
            ),
          ),
          if (search.linkMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                desktopPageInset,
                0,
                desktopPageInset,
                12,
              ),
              child: Text(
                search.linkMessage,
                key: const Key('link-message'),
                style: TextStyle(color: context.zero.warning),
              ),
            ),
          Expanded(
            child: showing
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(
                      desktopPageInset - 20,
                      0,
                      desktopPageInset - 12,
                      24,
                    ),
                    children: const [SearchBody()],
                  )
                : const _BrowseEntry(),
          ),
        ],
      ),
    );
  }
}

class _BrowseEntry extends StatelessWidget {
  const _BrowseEntry();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: desktopPageInset),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Material(
            color: context.zero.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () =>
                  openFeature(context, '电台与公开主页', const BrowseRootsBody()),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.zero.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(AppIcons.podcast, color: context.zero.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '电台与公开主页',
                            style: TextStyle(
                              color: context.zero.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '电台、歌手和用户的公开内容（Beta）',
                            style: TextStyle(
                              color: context.zero.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      AppIcons.chevronRight,
                      size: 18,
                      color: context.zero.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
