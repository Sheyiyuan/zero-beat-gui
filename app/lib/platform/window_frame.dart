import 'dart:io';
import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:window_manager/window_manager.dart';
import 'desktop_window.dart';

/// Drag handles deliberately exclude the window buttons and page controls.
class ZeroWindowFrame extends StatefulWidget {
  const ZeroWindowFrame({required this.child, super.key});
  final Widget child;
  @override
  State<ZeroWindowFrame> createState() => _ZeroWindowFrameState();
}

class _ZeroWindowFrameState extends State<ZeroWindowFrame> with WindowListener {
  bool _maximized = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  Future<void> _toggle() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) return widget.child;
    final colors = Theme.of(context).colorScheme;
    return Overlay.wrap(
      child: VirtualWindowFrame(
        child: Column(
          children: [
            Material(
              color: colors.surface,
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => windowManager.startDragging(),
                        onDoubleTap: _toggle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(
                                AppIcons.waveform,
                                size: 19,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '零拍',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '最小化',
                      onPressed: () => windowManager.minimize(),
                      icon: const Icon(AppIcons.minus, size: 18),
                    ),
                    IconButton(
                      tooltip: _maximized ? '还原' : '最大化',
                      onPressed: _toggle,
                      icon: Icon(
                        _maximized
                            ? AppIcons.restoreWindow
                            : AppIcons.maximizeWindow,
                        size: 17,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭窗口',
                      onPressed: DesktopWindow.closeWindow,
                      icon: const Icon(AppIcons.close, size: 19),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}
