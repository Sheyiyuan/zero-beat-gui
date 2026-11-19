import 'package:flutter/material.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../platform/storage.dart';
import '../shared/playback.dart';

Future<LibraryScan?> scanAndroidFolder(
  BuildContext context,
  CoreApi api, {
  Playlist? playlist,
  bool replace = false,
}) => showDialog<LibraryScan>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ScanDialog(api: api, playlist: playlist, replace: replace),
);

class _ScanDialog extends StatefulWidget {
  const _ScanDialog({required this.api, this.playlist, this.replace = false});
  final CoreApi api;
  final Playlist? playlist;
  final bool replace;
  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  final cancellation = AndroidScanCancellation();
  bool finished = false;
  bool get cancelled => cancellation.cancelled;
  int done = 0, total = 0;
  String name = '请选择文件夹', error = '';
  @override
  void initState() {
    super.initState();
    cancellation.whenCancelled.then((_) {
      if (mounted) Navigator.pop(context);
    });
    _run();
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final result = await AndroidStorage.scan(
        widget.api,
        playlist: widget.playlist,
        replace: widget.replace,
        cancellation: cancellation,
        progress: (index, count, title) {
          if (mounted) {
            setState(() {
              done = index;
              total = count;
              name = title;
            });
          }
        },
      );
      if (mounted && !cancelled) Navigator.pop(context, result);
    } catch (e) {
      if (mounted && !cancelled) {
        setState(() {
          error = '扫描失败：${errorText(e)}';
          finished = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: finished || cancelled,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) setState(cancellation.cancel);
    },
    child: AlertDialog(
      title: const Text('扫描本地音乐'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!finished)
            LinearProgressIndicator(value: total == 0 ? null : done / total),
          const SizedBox(height: 16),
          Text(
            error.isNotEmpty
                ? error
                : cancelled
                ? '正在取消'
                : name,
          ),
          if (total > 0) Text('$done / $total'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (finished) {
              Navigator.pop(context);
            } else {
              setState(cancellation.cancel);
            }
          },
          child: Text(finished ? '关闭' : '取消'),
        ),
      ],
    ),
  );
}
