import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import '../desktop/key_bindings.dart';
import '../platform/desktop_mode.dart';
import '../platform/desktop_window.dart';
import 'navigation.dart';
import 'session.dart';
import 'lyrics_page.dart';

GUISettings defaultGUISettings() => GUISettings(
  theme: 'system',
  palette: 'zero-red',
  accent: '',
  closeAction: 'background',
  shortcuts: {},
  window: '',
);

class GUISettingsController extends Notifier<GUISettings> {
  Future<void> _writes = Future.value();
  bool _alive = true;
  @override
  GUISettings build() {
    final api = ref.watch(coreApiProvider);
    _alive = true;
    ref.onDispose(() => _alive = false);
    if (api is CoreFeatureTransport) {
      _writes = Future<void>(() async {
        try {
          final value = await api.guiSettings();
          if (!_alive) return;
          state = value;
          if (DesktopWindow.installed) {
            DesktopWindow.instance.closeAction = value.closeAction;
            await DesktopWindow.instance.restoreSaved(value.window);
          }
        } catch (_) {}
      });
    }
    if (DesktopWindow.installed) {
      final window = DesktopWindow.instance;
      window.quit = ref.read(quitActionProvider);
      window.toggle = () => ref.read(transportProvider).toggle();
      window.next = () => ref.read(transportProvider).next();
      window.save = (value) => update(window: value);
    }
    return defaultGUISettings();
  }

  Future<void> update({
    String? theme,
    String? palette,
    String? accent,
    String? closeAction,
    Map<String, String>? shortcuts,
    String? window,
  }) {
    // Serialize read-modify-write so a resize cannot undo a theme change.
    final completer = Completer<void>();
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (!_alive) {
        completer.complete();
        return;
      }
      final previous = state;
      final next = GUISettings(
        theme: theme ?? previous.theme,
        palette: palette ?? previous.palette,
        accent: accent ?? previous.accent,
        closeAction: closeAction ?? previous.closeAction,
        shortcuts: shortcuts ?? previous.shortcuts,
        window: window ?? previous.window,
      );
      try {
        await ref.read(coreApiProvider).saveGUISettings(next);
        if (_alive) {
          state = next;
          DesktopWindow.instance.closeAction = next.closeAction;
        }
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

final guiSettingsProvider =
    NotifierProvider<GUISettingsController, GUISettings>(
      GUISettingsController.new,
    );

class SettingsBody extends ConsumerWidget {
  const SettingsBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gui = ref.watch(guiSettingsProvider);
    final controller = ref.read(guiSettingsProvider.notifier);
    final snapshot = ref.watch(playerProvider).snapshot;
    final api = ref.read(coreApiProvider);
    return AsyncFeature<Preferences>(
      load: api.preferences,
      builder: (context, p, reload) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('外观', style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            title: const Text('主题'),
            trailing: DropdownButton<String>(
              value: gui.theme,
              items: const [
                DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                DropdownMenuItem(value: 'light', child: Text('浅色')),
                DropdownMenuItem(value: 'dark', child: Text('深色')),
              ],
              onChanged: (v) =>
                  perform(context, () => controller.update(theme: v)),
            ),
          ),
          ListTile(
            title: const Text('配色'),
            trailing: DropdownButton<String>(
              value: gui.palette,
              items: const [
                DropdownMenuItem(value: 'zero-red', child: Text('零拍红')),
                DropdownMenuItem(value: 'hanpai-blue', child: Text('寒拍蓝')),
              ],
              onChanged: (v) => perform(
                context,
                () => controller.update(palette: v, accent: ''),
              ),
            ),
          ),
          ListTile(
            title: const Text('自定义强调色'),
            subtitle: Text(gui.accent.isEmpty ? '使用品牌配色' : gui.accent),
            trailing: const Icon(Icons.palette_outlined),
            onTap: () => perform(context, () async {
              final value = await askText(
                context,
                '强调色',
                initial: gui.accent,
                hint: '#B02A52；留空恢复品牌配色',
              );
              if (value == null) return;
              if (value.isNotEmpty &&
                  !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
                throw const FormatException('请输入六位十六进制颜色');
              }
              await controller.update(accent: value);
            }),
          ),
          const Divider(),
          Text('播放', style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            title: const Text('音质'),
            trailing: DropdownButton<String>(
              value: p.quality.value,
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('自动')),
                DropdownMenuItem(value: 'high', child: Text('高音质')),
                DropdownMenuItem(value: 'lossless', child: Text('无损')),
              ],
              onChanged: (v) => perform(context, () async {
                await api.playbackSetting(
                  'quality',
                  {'auto': 0.0, 'high': 1.0, 'lossless': 2.0}[v]!,
                );
                reload();
              }),
            ),
          ),
          SwitchListTile(
            title: const Text('静音'),
            value: snapshot.muted,
            onChanged: (v) =>
                perform(context, () => api.playbackSetting('mute', v ? 1 : 0)),
          ),
          SwitchListTile(
            title: const Text('优先使用本地下载'),
            value: p.localFirst,
            onChanged: (v) => perform(context, () async {
              await api.playbackSetting('local_first', v ? 1 : 0);
              reload();
            }),
          ),
          SwitchListTile(
            title: const Text('自动响度均衡'),
            value: p.autoGain,
            onChanged: (v) => perform(context, () async {
              await api.playbackSetting('auto_gain', v ? 1 : 0);
              reload();
            }),
          ),
          _NumberSetting(
            label: '全局音量补偿（dB）',
            value: p.compDb,
            onSave: (v) async {
              await api.playbackSetting('comp', v);
              reload();
            },
          ),
          if (snapshot.current != null)
            _NumberSetting(
              label: '本曲音量补偿（dB）',
              value: snapshot.songCompDb,
              onSave: (v) => api.playbackSetting('song_comp', v),
            ),
          _NumberSetting(
            label: '睡眠定时（分钟，0 取消）',
            value: snapshot.sleepUntil == null
                ? 0
                : (snapshot.sleepUntil!.difference(DateTime.now()).inSeconds /
                          60)
                      .ceil()
                      .clamp(0, 1440)
                      .toDouble(),
            onSave: (v) => api.playbackSetting('sleep', v),
          ),
          if (snapshot.current != null)
            ListTile(
              title: const Text('编辑当前歌曲片段'),
              trailing: const Icon(Icons.tune),
              onTap: () => openFeature(
                context,
                '片段编辑',
                ClipEditor(song: snapshot.current!),
              ),
            ),
          if (ref.read(platformLabelProvider) != 'android') ...[
            const Divider(),
            Text('桌面窗口', style: Theme.of(context).textTheme.titleLarge),
            ListTile(
              title: const Text('关闭窗口时'),
              trailing: DropdownButton<String>(
                value: gui.closeAction,
                items: const [
                  DropdownMenuItem(value: 'background', child: Text('后台播放')),
                  DropdownMenuItem(value: 'mini', child: Text('迷你播放器')),
                  DropdownMenuItem(value: 'quit', child: Text('退出')),
                ],
                onChanged: (v) =>
                    perform(context, () => controller.update(closeAction: v)),
              ),
            ),
            ListTile(
              title: const Text('切换迷你播放器'),
              leading: const Icon(Icons.picture_in_picture_alt),
              onTap: () async {
                Navigator.of(context).popUntil((r) => r.isFirst);
                await DesktopMode.enterMini();
              },
            ),
            Text('常用快捷键', style: Theme.of(context).textTheme.titleLarge),
            const Text('输入框内保留文字输入。留空可禁用；快捷键只用于 GUI。'),
            for (final entry in guiShortcutDefaults.entries)
              ListTile(
                title: Text(guiShortcutLabels[entry.key]!),
                subtitle: Text(gui.shortcuts[entry.key] ?? entry.value),
                trailing: const Icon(Icons.keyboard_outlined),
                onTap: () => perform(context, () async {
                  final value = await askText(
                    context,
                    guiShortcutLabels[entry.key]!,
                    initial: gui.shortcuts[entry.key] ?? entry.value,
                    hint: '例如 Ctrl+P 或 Space；留空禁用',
                  );
                  if (value == null) return;
                  final bindings = {...gui.shortcuts, entry.key: value};
                  validateGUIShortcuts(bindings);
                  await controller.update(shortcuts: bindings);
                }),
              ),
            TextButton(
              onPressed: () =>
                  perform(context, () => controller.update(shortcuts: {})),
              child: const Text('恢复默认快捷键'),
            ),
          ],
          ListTile(
            title: const Text('退出零拍'),
            leading: const Icon(Icons.logout),
            onTap: () => perform(context, ref.read(quitActionProvider)),
          ),
        ],
      ),
    );
  }
}

class _NumberSetting extends StatelessWidget {
  const _NumberSetting({
    required this.label,
    required this.value,
    required this.onSave,
  });
  final String label;
  final double value;
  final Future<void> Function(double) onSave;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    subtitle: Text(value.toStringAsFixed(1)),
    trailing: const Icon(Icons.edit_outlined),
    onTap: () => perform(context, () async {
      final text = await askText(context, label, initial: value.toString());
      if (text == null) return;
      final number = double.tryParse(text);
      if (number == null || !number.isFinite) {
        throw const FormatException('请输入有效数字');
      }
      await onSave(number);
    }),
  );
}
