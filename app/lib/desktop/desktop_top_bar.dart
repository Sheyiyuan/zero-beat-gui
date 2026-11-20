import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/icons.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../features/session.dart';
import '../shared/search_box.dart';
import 'desktop_pages.dart';

final _linkPattern = RegExp(
  r'^(https?://|www\.|b23\.tv/|(m\.)?bilibili\.com/|music\.163\.com/|BV[0-9A-Za-z]{10}$)',
  caseSensitive: false,
);

/// Desktop header above the main column. One field covers keyword search and
/// pasted links, so there is no separate link box to discover.
class DesktopTopBar extends ConsumerStatefulWidget {
  const DesktopTopBar({required this.onSearch, this.leading, super.key});

  /// Called after a keyword search is submitted so the shell can show results.
  final VoidCallback onSearch;
  final Widget? leading;

  @override
  ConsumerState<DesktopTopBar> createState() => _DesktopTopBarState();
}

class _DesktopTopBarState extends ConsumerState<DesktopTopBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    if (_linkPattern.hasMatch(text)) {
      widget.onSearch();
      await openSearchLink(context, ref, text);
      return;
    }
    widget.onSearch();
    await ref.read(searchProvider.notifier).submit();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    if (_controller.text != search.keyword) {
      _controller.value = TextEditingValue(
        text: search.keyword,
        selection: TextSelection.collapsed(offset: search.keyword.length),
      );
    }
    final focus = ref.watch(searchFocusProvider);
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: desktopPageInset),
          ?widget.leading,
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    key: const Key('search-field'),
                    focusNode: focus,
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onChanged: notifier.setKeyword,
                    onSubmitted: _submit,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '搜索歌曲、视频，或粘贴链接',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      fillColor: context.zero.surface,
                      prefixIcon: const Icon(AppIcons.search, size: 18),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      suffixIcon: search.keyword.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除',
                              iconSize: 16,
                              onPressed: () {
                                notifier.setKeyword('');
                                notifier.clearResults();
                              },
                              icon: const Icon(AppIcons.close),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.zero.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: context.zero.line.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (search.loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }
}
