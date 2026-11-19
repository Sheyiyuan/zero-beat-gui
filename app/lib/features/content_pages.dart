import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import '../shared/playback.dart';
import 'navigation.dart';
import 'song_selection.dart';

TrackRef songRef(Song song) => TrackRef(
  source: song.source,
  externalId: song.remoteId,
  page: song.page < 1 ? 1 : song.page,
  cid: song.cid,
);
Future<void> openAuthors(
  BuildContext context,
  CoreApi api,
  Song song, {
  bool authorsOnly = true,
}) async {
  await perform(context, () async {
    final profiles = await api.profiles(
      songRef(song),
      authorsOnly: authorsOnly,
    );
    if (!context.mounted) return;
    if (profiles.entries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可用的作者主页')));
      return;
    }
    BrowseEntry? chosen;
    if (profiles.entries.length == 1) {
      chosen = profiles.entries.first;
    } else {
      chosen = await showModalBottomSheet<BrowseEntry>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in profiles.entries)
                ListTile(
                  title: Text(e.title),
                  subtitle: Text(e.subtitle),
                  trailing: const Icon(AppIcons.chevronRight, size: 18),
                  onTap: () => Navigator.pop(context, e),
                ),
            ],
          ),
        ),
      );
    }
    if (context.mounted && chosen?.ref != null) {
      await openFeature(context, chosen!.title, BrowseBody(ref: chosen.ref!));
    }
  });
}

class ContentBody extends ConsumerStatefulWidget {
  const ContentBody({required this.song, this.related = false, super.key});
  final Song song;
  final bool related;
  @override
  ConsumerState<ContentBody> createState() => _ContentBodyState();
}

class _ContentBodyState extends ConsumerState<ContentBody> {
  int page = 1;
  @override
  Widget build(BuildContext context) {
    final api = ref.watch(coreApiProvider);
    if (widget.related) {
      return SongSelectionScope(
        target: widget.song.id,
        child: AsyncFeature<RelatedPage>(
          target: widget.song.id,
          load: () => api.related(songRef(widget.song)),
          builder: (context, data, reload) => data.candidates.isEmpty
              ? const Center(child: Text('暂无相关推荐'))
              : ListView(
                  children: [
                    const SongSelectionBar(),
                    for (final c in data.candidates)
                      FeatureSong(song: songFromTrack(c.track)),
                  ],
                ),
        ),
      );
    }
    return AsyncFeature<CommentPage>(
      target: '${widget.song.id}:$page',
      load: () => api.comments(songRef(widget.song), page),
      builder: (context, data, reload) => Column(
        children: [
          if (data.notice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(data.notice),
            ),
          Expanded(
            child: data.comments.isEmpty
                ? const Center(child: Text('暂无评论'))
                : ListView.builder(
                    itemCount: data.comments.length,
                    itemBuilder: (context, index) {
                      final c = data.comments[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: c.authorRef == null
                                  ? null
                                  : () => openFeature(
                                      context,
                                      c.author,
                                      BrowseBody(ref: c.authorRef!),
                                    ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  c.author,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            SelectableText(c.content),
                            const SizedBox(height: 8),
                            Text(
                              '${c.likes} 赞 · ${c.createdAt?.toLocal().toString().split('.').first ?? ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const Divider(),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          PageControls(
            page: data.page,
            hasNext: data.hasMore,
            onPage: (p) => setState(() => page = p),
          ),
        ],
      ),
    );
  }
}

class BrowseBody extends ConsumerStatefulWidget {
  const BrowseBody({required this.ref, super.key});
  final BrowseRef ref;
  @override
  ConsumerState<BrowseBody> createState() => _BrowseBodyState();
}

class _BrowseBodyState extends ConsumerState<BrowseBody> {
  int page = 1;
  @override
  Widget build(BuildContext context) => SongSelectionScope(
    target: (widget.ref.source, widget.ref.kind, widget.ref.id),
    child: AsyncFeature<BrowsePage>(
      target: '${widget.ref.source}:${widget.ref.kind}:${widget.ref.id}:$page',
      load: () => ref.read(coreApiProvider).browse(widget.ref, page),
      builder: (context, data, reload) => Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (data.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(data.description),
                        ),
                      if (data.notice.isNotEmpty) Text(data.notice),
                    ],
                  ),
                ),
                if (data.entries.any((e) => e.track != null))
                  const SongSelectionBar(),
                for (final e in data.entries)
                  if (e.track != null)
                    FeatureSong(song: songFromTrack(e.track!))
                  else if (e.ref != null)
                    ListTile(
                      title: Text(e.title),
                      subtitle: Text(e.subtitle),
                      trailing: const Icon(AppIcons.chevronRight, size: 18),
                      onTap: () => openFeature(
                        context,
                        e.title,
                        BrowseBody(ref: e.ref!),
                      ),
                    ),
                if (data.entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无公开内容'),
                  ),
              ],
            ),
          ),
          PageControls(
            page: data.page,
            hasNext: data.hasMore,
            onPage: (p) => setState(() => page = p),
          ),
        ],
      ),
    ),
  );
}

class BrowseRootsBody extends ConsumerWidget {
  const BrowseRootsBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncFeature<ProfileList>(
        load: () => ref.read(coreApiProvider).browseRoots(),
        builder: (context, data, reload) => ListView(
          children: [
            for (final e in data.entries)
              ListTile(
                leading: const Icon(AppIcons.podcast),
                title: Text(e.title),
                subtitle: Text(e.subtitle),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: e.ref == null
                    ? null
                    : () => openFeature(
                        context,
                        e.title,
                        BrowseBody(ref: e.ref!),
                      ),
              ),
          ],
        ),
      );
}

class PageControls extends StatelessWidget {
  const PageControls({
    required this.page,
    required this.hasNext,
    required this.onPage,
    super.key,
  });
  final int page;
  final bool hasNext;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: page > 1 ? () => onPage(page - 1) : null,
          child: const Text('上一页'),
        ),
        Text('第 $page 页'),
        TextButton(
          onPressed: hasNext ? () => onPage(page + 1) : null,
          child: const Text('下一页'),
        ),
      ],
    ),
  );
}

class FeatureSong extends StatelessWidget {
  const FeatureSong({required this.song, super.key});
  final Song song;
  @override
  Widget build(BuildContext context) => SelectableSong(song: song);
}
