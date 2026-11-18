import '../app/providers.dart';
import '../features/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../features/session.dart';
import 'song_tile.dart';

class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playerProvider).snapshot.queue;
    final index = ref.watch(playerProvider).snapshot.index;
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
                  onReorder: (from, to) => perform(
                    context,
                    () => ref
                        .read(coreApiProvider)
                        .moveQueue(from, (to > from ? to - 1 : to) - from),
                  ),
                  itemCount: queue.length,
                  itemBuilder: (context, itemIndex) {
                    final song = queue[itemIndex];
                    return SongTile(
                      key: ValueKey('$itemIndex:${song.id}'),
                      trailing: IconButton(
                        tooltip: '从队列移除',
                        onPressed: () => perform(
                          context,
                          () => ref
                              .read(coreApiProvider)
                              .removeQueueAt(itemIndex),
                        ),
                        icon: const Icon(Icons.close),
                      ),
                      song: song,
                      current: itemIndex == index,
                      onTap: () =>
                          ref.read(transportProvider).playIndex(itemIndex),
                    );
                  },
                ),
        ),
      ],
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
