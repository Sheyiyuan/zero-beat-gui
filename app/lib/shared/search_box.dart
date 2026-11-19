import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../features/navigation.dart';
import '../features/content_pages.dart';
import '../features/song_selection.dart';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';

import '../app/providers.dart';
import 'brand_mark.dart';
import '../app/theme.dart';
import '../features/session.dart';
import 'playback.dart';

class SearchBox extends ConsumerStatefulWidget {
  const SearchBox({super.key});

  @override
  ConsumerState<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends ConsumerState<SearchBox> {
  bool _showLink = false;
  late final TextEditingController _keyword = TextEditingController();
  late final TextEditingController _link = TextEditingController();

  @override
  void dispose() {
    _keyword.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _openLink(String value) async {
    final api = ref.read(coreApiProvider);
    await perform(context, () async {
      final link = await api.openLink(value.trim());
      if (!mounted) return;
      if (link.matched && link.kind == 'browse') {
        final target = await api.parseBrowse(value);
        if (mounted) await openFeature(context, '浏览', BrowseBody(ref: target));
      } else {
        await ref.read(searchProvider.notifier).openLink(value, resolved: link);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    if (_keyword.text != search.keyword) {
      _keyword.value = TextEditingValue(
        text: search.keyword,
        selection: TextSelection.collapsed(offset: search.keyword.length),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: Key('search-field'),
                focusNode: ref.watch(searchFocusProvider),
                controller: _keyword,
                decoration: InputDecoration(
                  hintText: '搜索歌曲',
                  prefixIcon: const Icon(AppIcons.search, size: 20),
                ),
                textInputAction: TextInputAction.search,
                onChanged: notifier.setKeyword,
                onSubmitted: (_) => notifier.submit(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: search.loading ? null : notifier.submit,
              child: Text('搜索'),
            ),
          ],
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 8,
                  children: [
                    _SourceChip(
                      label: '全部',
                      value: '',
                      selected: search.source,
                      onSelected: notifier.setSource,
                    ),
                    _SourceChip(
                      label: '哔哩哔哩',
                      value: 'bilibili',
                      selected: search.source,
                      onSelected: notifier.setSource,
                    ),
                    _SourceChip(
                      label: '网易云',
                      value: 'netease',
                      selected: search.source,
                      onSelected: notifier.setSource,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: const Key('link-toggle'),
              tooltip: _showLink ? '收起链接' : '打开链接',
              isSelected: _showLink,
              onPressed: () => setState(() => _showLink = !_showLink),
              icon: const Icon(AppIcons.link, size: 20),
            ),
          ],
        ),
        if (_showLink) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('link-field'),
                  controller: _link,
                  decoration: const InputDecoration(
                    hintText: '粘贴歌曲、歌单或主页链接',
                    prefixIcon: Icon(AppIcons.link, size: 20),
                  ),
                  onSubmitted: _openLink,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _openLink(_link.text),
                child: const Text('打开'),
              ),
            ],
          ),
        ],
        if (search.linkMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              search.linkMessage,
              key: Key('link-message'),
              style: TextStyle(color: context.zero.warning),
            ),
          ),
      ],
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 48),
      child: ChoiceChip(
        avatar: BrandMark.supports(value)
            ? BrandMark(source: value, size: 16)
            : null,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        showCheckmark: false,
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
      ),
    );
  }
}

class SearchBody extends ConsumerWidget {
  const SearchBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(searchProvider);
    if (!search.submitted && !search.loading) return const SizedBox.shrink();
    return SongSelectionScope(
      target: (search.keyword, search.source),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (search.pages > 1)
            Row(
              children: [
                TextButton(
                  key: Key('search-prev'),
                  onPressed: search.loading || search.page <= 1
                      ? null
                      : () => ref
                            .read(searchProvider.notifier)
                            .goToPage(search.page - 1),
                  child: Text('上一页'),
                ),
                Text('${search.page} / ${search.pages}'),
                TextButton(
                  key: Key('search-next'),
                  onPressed: search.loading || search.page >= search.pages
                      ? null
                      : () => ref
                            .read(searchProvider.notifier)
                            .goToPage(search.page + 1),
                  child: Text('下一页'),
                ),
              ],
            ),
          if (search.loading)
            Padding(padding: EdgeInsets.only(bottom: 8), child: Text('正在搜索')),
          if (search.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      search.error,
                      key: Key('search-error'),
                      style: TextStyle(color: context.zero.danger),
                    ),
                  ),
                  TextButton(
                    key: Key('search-retry'),
                    onPressed: ref.read(searchProvider.notifier).retry,
                    child: Text('重试'),
                  ),
                ],
              ),
            ),
          if (search.warning.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                search.warning,
                key: Key('search-warning'),
                style: TextStyle(color: context.zero.warning),
              ),
            ),
          if (search.results.isNotEmpty) const SongSelectionBar(),
          for (var index = 0; index < search.results.length; index++)
            _ResultRow(
              candidate: search.results[index],
              selected: index == search.selectedIndex,
              index: index,
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends ConsumerWidget {
  const _ResultRow({
    required this.candidate,
    required this.selected,
    required this.index,
  });

  final Candidate candidate;
  final bool selected;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = songFromTrack(candidate.track);
    return SelectableSong(
      song: song,
      selected: selected,
      onSelect: () => ref.read(searchProvider.notifier).select(index),
      queue: [
        for (final item in ref.watch(searchProvider).results)
          songFromTrack(item.track),
      ],
    );
  }
}
