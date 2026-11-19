import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../features/navigation.dart';
import '../features/session.dart';
import '../features/song_actions.dart';
import 'song_tile.dart';

class QueuePanel extends ConsumerStatefulWidget {
  const QueuePanel({super.key});

  @override
  ConsumerState<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<QueuePanel> {
  /// Rough row height; used only for the initial scroll offset, the post-frame
  /// pass then snaps the exact current row into view.
  static const double _estimatedItemExtent = 68;

  late final ScrollController _scroll;
  final GlobalKey _currentTileKey = GlobalKey();
  bool _scheduledReveal = false;

  @override
  void initState() {
    super.initState();
    final snapshot = ref.read(playerProvider).snapshot;
    _scroll = ScrollController(
      initialScrollOffset: _offsetFor(snapshot.index, snapshot.queue.length),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _offsetFor(int index, int length) {
    if (index <= 0 || length <= 0) return 0;
    return (index * _estimatedItemExtent - 96).clamp(0.0, double.infinity);
  }

  /// Opens the queue with the playing row already in view instead of at the
  /// top of the list. Runs once, after the first frame has laid the rows out.
  void _scheduleReveal(int index, int length) {
    if (_scheduledReveal) return;
    _scheduledReveal = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _currentTileKey.currentContext;
      if (current != null) {
        Scrollable.ensureVisible(
          current,
          alignment: 0.35,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
        return;
      }
      if (_scroll.hasClients) {
        final target = _offsetFor(index, length);
        _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(playerProvider);
    final queue = view.snapshot.queue;
    final index = view.snapshot.index;
    if (queue.isNotEmpty) _scheduleReveal(index, queue.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '播放队列',
            style: TextStyle(fontSize: 18, color: context.zero.text),
          ),
        ),
        TextButton(
          onPressed: queue.isEmpty
              ? null
              : () => perform(
                  context,
                  () => ref.read(coreApiProvider).clearQueue(),
                ),
          child: const Text('清空队列'),
        ),
        Expanded(
          child: queue.isEmpty
              ? Center(
                  child: Text(
                    '队列是空的',
                    style: TextStyle(color: context.zero.muted),
                  ),
                )
              : ReorderableListView.builder(
                  key: const Key('queue-list'),
                  scrollController: _scroll,
                  buildDefaultDragHandles: false,
                  autoScrollerVelocityScalar: 36,
                  proxyDecorator: (child, itemIndex, animation) =>
                      _QueueDragProxy(animation: animation, child: child),
                  onReorder: (from, to) => perform(
                    context,
                    () => ref
                        .read(coreApiProvider)
                        .moveQueue(from, (to > from ? to - 1 : to) - from),
                  ),
                  itemCount: queue.length,
                  itemBuilder: (context, itemIndex) {
                    final song = queue[itemIndex];
                    final mobile = ref.read(platformLabelProvider) == 'android';
                    Future<void> remove() => perform(
                      context,
                      () => ref.read(coreApiProvider).removeQueueAt(itemIndex),
                    );
                    final tile = SongTile(
                      key: ValueKey('$itemIndex:${song.id}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReorderableDragStartListener(
                            key: Key('queue-drag-handle-$itemIndex'),
                            index: itemIndex,
                            child: Semantics(
                              label: '拖动排序',
                              child: SizedBox(
                                width: 40,
                                height: 48,
                                child: Icon(
                                  AppIcons.drag,
                                  size: 20,
                                  color: context.zero.muted,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '从队列移除',
                            onPressed: remove,
                            icon: const Icon(AppIcons.close),
                          ),
                          SongActions(
                            song: song,
                            extra: const [
                              SongAction(
                                id: 'remove',
                                label: '从队列移除',
                                icon: AppIcons.removeFromList,
                              ),
                            ],
                            onExtra: (_) => remove(),
                          ),
                        ],
                      ),
                      song: song,
                      current: itemIndex == index,
                      onTap: () =>
                          ref.read(transportProvider).playIndex(itemIndex),
                      onLongPress: mobile
                          ? null
                          : () => showSongMenu(
                              context,
                              ref,
                              song,
                              extra: const [
                                SongAction(
                                  id: 'remove',
                                  label: '从队列移除',
                                  icon: AppIcons.removeFromList,
                                ),
                              ],
                              onExtra: (_) => remove(),
                            ),
                      onSecondaryTap: (position) => showSongMenu(
                        context,
                        ref,
                        song,
                        position: position,
                        extra: const [
                          SongAction(
                            id: 'remove',
                            label: '从队列移除',
                            icon: AppIcons.removeFromList,
                          ),
                        ],
                        onExtra: (_) => remove(),
                      ),
                    );
                    if (itemIndex != index) return tile;
                    return KeyedSubtree(key: _currentTileKey, child: tile);
                  },
                ),
        ),
      ],
    );
  }
}

class _QueueDragProxy extends StatelessWidget {
  const _QueueDragProxy({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
        return Transform.scale(
          scale: 1 + 0.02 * t,
          child: Material(
            elevation: 10 * t,
            color: context.zero.surface,
            shadowColor: context.zero.text.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
        );
      },
    );
  }
}

Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: context.zero.surface,
    builder: (context) {
      return SizedBox(height: 420, child: QueuePanel());
    },
  );
}
