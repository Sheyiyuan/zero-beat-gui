import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../core/developer_log.dart';
import 'developer_log_export.dart';

OverlayEntry? _activeEntry;

bool get developerLogWindowVisible => _activeEntry != null;

/// Removes the floating log window if it is open. Safe to call repeatedly.
void closeDeveloperLogWindow() {
  final entry = _activeEntry;
  _activeEntry = null;
  if (entry != null && entry.mounted) entry.remove();
}

/// Shows the draggable log overlay above the current route. Returns false when
/// no overlay is available (for example in a bare widget test).
bool showDeveloperLogWindow(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return false;
  closeDeveloperLogWindow();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => DeveloperLogWindow(
      onClose: () {
        if (identical(_activeEntry, entry)) _activeEntry = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _activeEntry = entry;
  overlay.insert(entry);
  return true;
}

class DeveloperLogWindow extends ConsumerStatefulWidget {
  const DeveloperLogWindow({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<DeveloperLogWindow> createState() => _DeveloperLogWindowState();
}

class _DeveloperLogWindowState extends ConsumerState<DeveloperLogWindow> {
  static const _minWidth = 260.0;
  static const _maxWidth = 560.0;
  static const _minHeight = 220.0;
  static const _maxHeight = 420.0;

  final ScrollController _scroll = ScrollController();
  Offset? _position;
  bool _autoScroll = true;
  bool _busy = false;
  int _lastRevision = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Size _panelSize(Size screen) {
    final width = math.min(_maxWidth, math.max(_minWidth, screen.width - 32));
    final height = math.min(
      _maxHeight,
      math.max(_minHeight, screen.height * 0.55),
    );
    return Size(width, height);
  }

  Offset _defaultPosition(Size screen, Size panel) {
    final x = screen.width - panel.width - 16;
    final y = math.min(
      math.max(16.0, screen.height * 0.12),
      math.max(16.0, screen.height - panel.height - 16),
    );
    return _clamp(Offset(x, y), screen, panel);
  }

  Offset _clamp(Offset position, Size screen, Size panel) {
    final maxX = math.max(8.0, screen.width - panel.width - 8);
    final maxY = math.max(8.0, screen.height - panel.height - 8);
    return Offset(
      position.dx.clamp(8.0, maxX).toDouble(),
      position.dy.clamp(8.0, maxY).toDouble(),
    );
  }

  void _dragBy(Offset delta, Size screen, Size panel) {
    final current = _position ?? _defaultPosition(screen, panel);
    setState(() {
      _position = _clamp(current + delta, screen, panel);
    });
  }

  void _scheduleAutoScroll(DeveloperLog log) {
    if (!_autoScroll || log.revision == _lastRevision) return;
    _lastRevision = log.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_autoScroll || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _toggleAutoScroll() {
    setState(() => _autoScroll = !_autoScroll);
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_autoScroll) return false;
    final dragged =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final userScrolled =
        notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    if (dragged || userScrolled) {
      setState(() => _autoScroll = false);
    }
    return false;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copy() async {
    final log = ref.read(developerLogProvider);
    final text = log.asText();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(developerLogClipboardProvider).setText(text);
      _showMessage('日志已复制');
    } catch (error) {
      _showMessage('复制失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final log = ref.read(developerLogProvider);
    final contents = log.asText();
    if (contents.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(developerLogExporterProvider)
          .export(
            fileName: developerLogFileName(DateTime.now()),
            contents: contents,
          );
      if (!result.cancelled) _showMessage('日志已导出到 ${result.path}');
    } catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    ref.read(developerLogProvider).clear();
    _showMessage('日志已清空');
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(developerLogProvider);
    final screen = MediaQuery.sizeOf(context);
    final panel = _panelSize(screen);
    final position = _position ?? _defaultPosition(screen, panel);
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: position.dx,
            top: position.dy,
            width: panel.width,
            height: panel.height,
            child: ListenableBuilder(
              listenable: log,
              builder: (context, _) {
                _scheduleAutoScroll(log);
                return _buildPanel(context, log, screen, panel);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(
    BuildContext context,
    DeveloperLog log,
    Size screen,
    Size panel,
  ) {
    final entries = log.snapshot();
    final empty = entries.isEmpty;
    return Material(
      key: const Key('dev-log-panel'),
      color: context.zero.surface,
      elevation: 16,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            key: const Key('dev-log-header'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => _dragBy(details.delta, screen, panel),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
              child: Row(
                children: [
                  Icon(AppIcons.drag, color: context.zero.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '运行日志',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${log.length} 条',
                    style: TextStyle(color: context.zero.muted, fontSize: 12),
                  ),
                  IconButton(
                    key: const Key('dev-log-close'),
                    tooltip: '关闭',
                    onPressed: widget.onClose,
                    icon: const Icon(AppIcons.close),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  key: const Key('dev-log-autoscroll'),
                  tooltip: _autoScroll ? '暂停自动滚动' : '恢复自动滚动',
                  onPressed: _toggleAutoScroll,
                  icon: Icon(
                    _autoScroll ? AppIcons.pauseCircle : AppIcons.playCircle,
                  ),
                ),
                IconButton(
                  key: const Key('dev-log-copy'),
                  tooltip: '复制全部',
                  onPressed: empty || _busy ? null : _copy,
                  icon: const Icon(AppIcons.copy),
                ),
                IconButton(
                  key: const Key('dev-log-clear'),
                  tooltip: '清空日志',
                  onPressed: empty ? null : _clear,
                  icon: const Icon(AppIcons.delete),
                ),
                IconButton(
                  key: const Key('dev-log-export'),
                  tooltip: '导出日志',
                  onPressed: empty || _busy ? null : _export,
                  icon: const Icon(AppIcons.save),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.zero.line),
          Expanded(
            child: empty
                ? Center(
                    child: Text(
                      '暂无日志',
                      key: const Key('dev-log-empty'),
                      style: TextStyle(color: context.zero.muted),
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ListView.builder(
                      key: const Key('dev-log-list'),
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: entries.length,
                      itemBuilder: (context, index) =>
                          _LogRow(entry: entries[index], index: index),
                    ),
                  ),
          ),
          Divider(height: 1, color: context.zero.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _autoScroll ? '自动滚动已开启' : '自动滚动已暂停',
                    key: const Key('dev-log-autoscroll-status'),
                    style: TextStyle(
                      color: _autoScroll
                          ? context.zero.muted
                          : context.zero.warning,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (!_autoScroll)
                  TextButton(
                    key: const Key('dev-log-jump-latest'),
                    onPressed: _toggleAutoScroll,
                    child: const Text('跳到最新'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.index});

  final DeveloperLogEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      DeveloperLogLevel.error => context.zero.danger,
      DeveloperLogLevel.warning => context.zero.warning,
      DeveloperLogLevel.info => context.zero.text,
      DeveloperLogLevel.debug => context.zero.muted,
    };
    final source = entry.source.isEmpty ? '应用' : entry.source;
    return Padding(
      key: Key('dev-log-entry-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.timeLabel,
            style: TextStyle(
              color: context.zero.muted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              entry.level.label,
              style: TextStyle(color: color, fontSize: 11, height: 1.5),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$source · ${entry.message}',
              style: TextStyle(color: color, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
