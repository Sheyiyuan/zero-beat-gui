import 'package:flutter/material.dart';

import 'playback.dart' show errorText;

/// A list that can always be pulled to refresh, even when its rows are shorter
/// than the viewport.
class RefreshableListView extends StatelessWidget {
  const RefreshableListView({
    required this.onRefresh,
    required this.children,
    this.padding,
    super.key,
  });

  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: children,
      ),
    );
  }
}

typedef RefreshableBuilder<T> =
    Widget Function(
      BuildContext context,
      T data,
      Future<void> Function() reload,
    );

/// A small async feature loader that keeps the last successful payload while a
/// refresh is in flight. A failed refresh leaves the old content in place and
/// shows an inline error instead of replacing the page.
class RefreshableFeature<T> extends StatefulWidget {
  const RefreshableFeature({
    required this.load,
    required this.builder,
    this.target = '',
    this.retain = false,
    this.empty,
    super.key,
  });

  final Future<T> Function() load;
  final RefreshableBuilder<T> builder;
  final Object target;
  final bool retain;
  final Widget? empty;

  @override
  State<RefreshableFeature<T>> createState() => _RefreshableFeatureState<T>();
}

class _RefreshableFeatureState<T> extends State<RefreshableFeature<T>> {
  T? _data;
  Object? _error;
  Object? _refreshError;
  bool _busy = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(covariant RefreshableFeature<T> old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      if (!widget.retain) {
        _data = null;
        _error = null;
      }
      _run();
    }
  }

  Future<void> reload() => _run();

  Future<void> _run() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _refreshError = null;
      if (_data == null) _error = null;
    });
    try {
      final data = await widget.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_data == null) {
          _error = error;
        } else {
          _refreshError = error;
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Column(
      children: [
        if (_busy && data != null) const LinearProgressIndicator(minHeight: 2),
        if (_refreshError != null)
          _RefreshError(error: _refreshError!, onRetry: reload),
        if (data != null)
          Expanded(child: widget.builder(context, data, reload))
        else if (_busy)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(
            child: _InitialError(error: _error!, onRetry: reload),
          )
        else
          Expanded(child: widget.empty ?? const Center(child: Text('暂无内容'))),
      ],
    );
  }
}

class _RefreshError extends StatelessWidget {
  const _RefreshError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '刷新失败：${errorText(error)}',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _InitialError extends StatelessWidget {
  const _InitialError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：${errorText(error)}', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
