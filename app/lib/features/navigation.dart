import 'package:flutter/material.dart';
import '../shared/player_bar.dart';
import '../shared/queue_panel.dart';
import '../mobile/full_player_page.dart';

class FeatureNavigation extends InheritedWidget {
  const FeatureNavigation({
    required this.navigatorKey,
    required super.child,
    super.key,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  @override
  bool updateShouldNotify(FeatureNavigation oldWidget) =>
      navigatorKey != oldWidget.navigatorKey;
}

Future<T?> openFeature<T>(BuildContext context, String title, Widget body) {
  final host = context.dependOnInheritedWidgetOfExactType<FeatureNavigation>();
  final navigator = host?.navigatorKey.currentState ?? Navigator.of(context);
  final hostContext = host?.navigatorKey.currentContext;
  if (hostContext != null) {
    final scaffold = Scaffold.maybeOf(hostContext);
    if (scaffold?.isDrawerOpen == true) scaffold!.closeDrawer();
    if (scaffold?.isEndDrawerOpen == true) scaffold!.closeEndDrawer();
  }
  return navigator.push<T>(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: body),
        bottomNavigationBar: host != null
            ? null
            : SafeArea(
                top: false,
                child: PlayerBar(
                  compact: true,
                  onQueue: () => showQueueSheet(context),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FullPlayerPage()),
                  ),
                ),
              ),
      ),
    ),
  );
}

Future<void> perform(
  BuildContext context,
  Future<void> Function() operation, {
  String? success,
}) async {
  try {
    await operation();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String hint = '',
  bool secret = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: secret,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  // The dialog route may still animate after the future resolves.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String details,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(details),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ??
    false;

class AsyncFeature<T> extends StatefulWidget {
  const AsyncFeature({
    required this.load,
    required this.builder,
    this.target = '',
    this.retain = false,
    super.key,
  });
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, VoidCallback) builder;
  final Object target;
  final bool retain;
  @override
  State<AsyncFeature<T>> createState() => _AsyncFeatureState<T>();
}

class _AsyncFeatureState<T> extends State<AsyncFeature<T>> {
  T? _data;
  Object? _error;
  bool _busy = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AsyncFeature<T> old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      if (!widget.retain) _data = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.load();
      if (mounted && generation == _generation) setState(() => _data = data);
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text('$_error')),
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      if (_data != null)
        Expanded(child: widget.builder(context, _data as T, _load))
      else if (!_busy && _error == null)
        const Expanded(child: Center(child: Text('暂无内容'))),
    ],
  );
}
