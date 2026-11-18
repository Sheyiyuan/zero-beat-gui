import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../shared/playback.dart';
import 'session.dart';
import 'navigation.dart';

class LyricsBody extends ConsumerStatefulWidget {
  const LyricsBody({required this.song, super.key});
  final Song song;
  @override
  ConsumerState<LyricsBody> createState() => _LyricsBodyState();
}

class _LyricsBodyState extends ConsumerState<LyricsBody> {
  final scroll = ScrollController();
  final lineKeys = <int, GlobalKey>{};
  bool following = true;
  int version = 0;
  int lastLine = -1;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(coreApiProvider);
    final view = ref.watch(playerProvider).snapshot;
    return AsyncFeature<LyricsResult>(
      target: '${widget.song.id}:$version',
      load: () => api.lyrics(widget.song),
      builder: (context, data, reload) {
        final position = view.current?.id == widget.song.id
            ? view.positionMs
            : 0;
        int current = -1;
        for (var i = 0; i < data.lines.length; i++) {
          if (data.lines[i].startMs + data.offsetMs <= position) current = i;
        }
        if (following && current != lastLine) {
          lastLine = current;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scroll.hasClients && current >= 0) {
              final target = lineKeys[current]?.currentContext;
              if (target != null) {
                Scrollable.ensureVisible(
                  target,
                  alignment: 0.35,
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              }
            }
          });
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${data.source} · ${(data.offsetMs / 1000).toStringAsFixed(1)} 秒',
                  ),
                  IconButton(
                    tooltip: '歌词提前 0.5 秒',
                    onPressed: () => perform(context, () async {
                      await api.lyricOffset(
                        widget.song.id,
                        data.offsetKey,
                        data.offsetMs - 500,
                      );
                      reload();
                    }),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: '歌词延后 0.5 秒',
                    onPressed: () => perform(context, () async {
                      await api.lyricOffset(
                        widget.song.id,
                        data.offsetKey,
                        data.offsetMs + 500,
                      );
                      reload();
                    }),
                    icon: const Icon(Icons.add),
                  ),
                  TextButton(
                    onPressed: () => perform(context, () async {
                      await api.lyricOffset(widget.song.id, data.offsetKey, 0);
                      reload();
                    }),
                    child: const Text('归零'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await openFeature(
                        context,
                        '歌词来源',
                        LyricBindingBody(song: widget.song),
                      );
                      if (mounted) reload();
                    },
                    child: const Text('更换来源'),
                  ),
                ],
              ),
            ),
            if (data.degraded)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('绑定失效，已回退到自动来源；原绑定仍保留'),
              ),
            Expanded(
              child: data.lines.isEmpty
                  ? const Center(child: Text('暂未找到带时间轴的歌词，可尝试更换来源'))
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollStartNotification &&
                            n.dragDetails != null) {
                          setState(() => following = false);
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: scroll,
                        child: Column(
                          children: [
                            for (var i = 0; i < data.lines.length; i++)
                              ListTile(
                                key: lineKeys.putIfAbsent(i, () => GlobalKey()),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                selected: i == current,
                                title: Text(
                                  data.lines[i].text,
                                  style: TextStyle(
                                    fontSize: i == current ? 22 : 18,
                                    color: i == current
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                                subtitle: data.lines[i].translation.isEmpty
                                    ? null
                                    : Text(data.lines[i].translation),
                                onTap: view.current?.id != widget.song.id
                                    ? null
                                    : () => ref
                                          .read(transportProvider)
                                          .seek(
                                            (data.lines[i].startMs +
                                                    data.offsetMs)
                                                .clamp(0, view.durationMs),
                                          ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (!following)
              TextButton(
                onPressed: () => setState(() {
                  following = true;
                  lastLine = -1;
                }),
                child: const Text('回到当前行'),
              ),
          ],
        );
      },
    );
  }
}

class LyricBindingBody extends ConsumerStatefulWidget {
  const LyricBindingBody({required this.song, super.key});
  final Song song;
  @override
  ConsumerState<LyricBindingBody> createState() => _LyricBindingBodyState();
}

class _LyricBindingBodyState extends ConsumerState<LyricBindingBody> {
  late final input = TextEditingController(text: widget.song.title);
  late String query = widget.song.title;
  String filter = '';
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _bind(LyricCandidate candidate) async {
    await perform(context, () async {
      final api = ref.read(coreApiProvider);
      final preview = await api.previewLyrics(widget.song, candidate);
      if (!mounted) return;
      if (await confirmAction(
        context,
        '使用「${preview.label}」',
        '${preview.count} 行\n${preview.lines.take(5).map((l) => l.text).join('\n')}',
      )) {
        await api.bindLyrics(widget.song, candidate);
        if (mounted) Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: input,
          onSubmitted: (v) => setState(() => query = v),
          decoration: InputDecoration(
            labelText: '搜索歌词',
            suffixIcon: IconButton(
              onPressed: () => setState(() => query = input.text),
              icon: const Icon(Icons.search),
            ),
          ),
        ),
      ),
      Wrap(
        children: [
          for (final entry in {
            '': '全部',
            'netease': '网易云',
            'lrclib': 'LRCLIB',
          }.entries)
            Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: filter == entry.key,
                onSelected: (_) => setState(() => filter = entry.key),
              ),
            ),
          TextButton(
            onPressed: () => perform(context, () async {
              final file = await openFile(
                acceptedTypeGroups: [
                  const XTypeGroup(label: 'LRC 歌词', extensions: ['lrc']),
                ],
              );
              if (file == null) return;
              var bindingPath = file.path;
              if (Platform.isAndroid) {
                final dir = Directory(
                  '${(await getApplicationSupportDirectory()).path}/lyrics-imports',
                );
                await dir.create(recursive: true);
                bindingPath =
                    '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.lrc';
                await file.saveTo(bindingPath);
              }
              await _bind(
                LyricCandidate(
                  kind: BindingKind.valueLocalFile,
                  source: SourceID.valueLocal,
                  externalId: '',
                  page: 1,
                  cid: BigInt.zero,
                  lrclibId: BigInt.zero,
                  path: bindingPath,
                  songId: '',
                  title: file.name,
                  artist: '',
                  durationMs: 0,
                  hasSynced: false,
                  known: false,
                  mark: '本地',
                ),
              );
            }),
            child: const Text('选择 LRC 文件'),
          ),
          TextButton(
            onPressed: () => perform(context, () async {
              final songs = (await ref.read(coreApiProvider).localSearch(''))
                  .where((song) => song.source.value == 'local')
                  .toList();
              if (!context.mounted) return;
              final selected = await showModalBottomSheet<Song>(
                context: context,
                showDragHandle: true,
                builder: (context) => ListView(
                  children: [
                    for (final song in songs)
                      ListTile(
                        title: Text(song.title),
                        subtitle: Text(song.artist),
                        onTap: () => Navigator.pop(context, song),
                      ),
                  ],
                ),
              );
              if (selected != null) {
                await _bind(
                  LyricCandidate(
                    kind: BindingKind.valueLocalSong,
                    source: SourceID.valueLocal,
                    externalId: '',
                    page: 1,
                    cid: BigInt.zero,
                    lrclibId: BigInt.zero,
                    path: '',
                    songId: selected.id,
                    title: selected.title,
                    artist: selected.artist,
                    durationMs: selected.durationMs,
                    hasSynced: false,
                    known: false,
                    mark: '本机曲目',
                  ),
                );
              }
            }),
            child: const Text('绑定本机曲目'),
          ),
          TextButton(
            onPressed: () => perform(context, () async {
              final value = await askText(
                context,
                '指定歌词来源',
                hint: '歌曲链接或 LRCLIB:数字 ID',
              );
              if (value == null) return;
              LyricCandidate candidate;
              if (value.toLowerCase().startsWith('lrclib:')) {
                final id = BigInt.tryParse(value.split(':').last);
                if (id == null || id <= BigInt.zero) {
                  throw const FormatException('LRCLIB ID 无效');
                }
                candidate = LyricCandidate(
                  kind: BindingKind.valueLrclib,
                  source: SourceID(''),
                  externalId: '',
                  page: 1,
                  cid: BigInt.zero,
                  lrclibId: id,
                  path: '',
                  songId: '',
                  title: value,
                  artist: '',
                  durationMs: 0,
                  hasSynced: false,
                  known: false,
                  mark: 'LRCLIB',
                );
              } else {
                final link = await ref.read(coreApiProvider).openLink(value);
                final song = link.song;
                if (song == null || link.kind != 'track') {
                  throw const FormatException('请输入歌曲或分 P 链接');
                }
                candidate = LyricCandidate(
                  kind: BindingKind.valueSource,
                  source: song.source,
                  externalId: song.remoteId,
                  page: song.page,
                  cid: song.cid,
                  lrclibId: BigInt.zero,
                  path: '',
                  songId: '',
                  title: song.title,
                  artist: song.artist,
                  durationMs: song.durationMs,
                  hasSynced: false,
                  known: false,
                  mark: '平台',
                );
              }
              await _bind(candidate);
            }),
            child: const Text('指定链接／ID'),
          ),
          TextButton(
            onPressed: () => perform(context, () async {
              await ref.read(coreApiProvider).unbindLyrics(widget.song.id);
              if (context.mounted) Navigator.pop(context);
            }),
            child: const Text('恢复自动来源'),
          ),
        ],
      ),
      Expanded(
        child: AsyncFeature<List<LyricCandidate>>(
          target: '$query:$filter',
          load: () => ref
              .read(coreApiProvider)
              .lyricCandidates(widget.song, query, filter: filter),
          builder: (context, data, reload) => ListView(
            children: [
              for (final c in data)
                ListTile(
                  title: Text(c.title),
                  subtitle: Text('${c.artist} · ${c.mark}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _bind(c),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class ClipEditor extends ConsumerStatefulWidget {
  const ClipEditor({required this.song, super.key});
  final Song song;
  @override
  ConsumerState<ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends ConsumerState<ClipEditor> {
  final start = TextEditingController();
  final end = TextEditingController();
  late final CoreApi api;
  String token = '';
  bool invalidated = false;
  StreamSubscription<PlayerView>? subscription;
  bool initialized = false;
  bool settled = false;
  bool busy = false;
  bool previewed = false;
  @override
  void initState() {
    super.initState();
    api = ref.read(coreApiProvider);
    subscription = api.states.listen((view) {
      if (view.snapshot.current?.id != widget.song.id &&
          !invalidated &&
          mounted) {
        setState(() => invalidated = true);
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    if (previewed && !settled && !invalidated) {
      unawaited(
        api
            .editClip(widget.song.id, 'cancel', token: token)
            .catchError((Object _) {}),
      );
    }
    start.dispose();
    end.dispose();
    super.dispose();
  }

  Future<void> _act(String action) async {
    if (busy || invalidated || token.isEmpty) return;
    final issue = _validationIssue(_durationSeconds(ref));
    if (issue != null && (action == 'save' || action == 'preview')) {
      return;
    }
    setState(() => busy = true);
    await perform(context, () async {
      final a = double.tryParse(start.text);
      if (a == null || !a.isFinite) {
        throw const FormatException('请输入有效秒数');
      }
      final endText = end.text.trim();
      final parsedEnd = endText.isEmpty ? null : double.tryParse(endText);
      if (endText.isNotEmpty && (parsedEnd == null || !parsedEnd.isFinite)) {
        throw const FormatException('请输入有效秒数');
      }
      final endMs = endText.isEmpty ? 0 : (parsedEnd! * 1000).round();
      if (action == 'preview') previewed = true;
      ref.read(interruptionPolicyProvider).noteUserTransport();
      await api.editClip(
        widget.song.id,
        action,
        token: token,
        positionMs: (a * 1000).round(),
        clip: Clip(startMs: (a * 1000).round(), endMs: endMs),
      );
      if (action != 'preview') {
        settled = true;
        if (mounted) Navigator.pop(context);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  double _durationSeconds(WidgetRef ref) {
    final view = ref.read(playerProvider).snapshot;
    final active = !invalidated && view.current?.id == widget.song.id;
    final ms = active && view.durationMs > 0
        ? view.durationMs
        : widget.song.durationMs;
    return ms / 1000.0;
  }

  String? _validationIssue(double duration) {
    final a = double.tryParse(start.text);
    if (a == null || !a.isFinite || a < 0) {
      return '请输入有效的起点秒数。';
    }
    final endText = end.text.trim();
    if (endText.isEmpty) return null;
    final b = double.tryParse(endText);
    if (b == null || !b.isFinite) {
      return '请输入有效的终点秒数。';
    }
    if (b <= a) {
      return '终点必须大于起点。';
    }
    if (duration > 0 && b > duration) {
      return '终点不能超过全长 ${duration.toStringAsFixed(1)} 秒。';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(playerProvider).snapshot;
    final active = !invalidated && view.current?.id == widget.song.id;
    final durationMs = active && view.durationMs > 0
        ? view.durationMs
        : widget.song.durationMs;
    final duration = durationMs / 1000.0;
    final unknownDuration = durationMs <= 0;
    final insets = MediaQuery.viewInsetsOf(context);
    return PopScope(
      canPop: !busy,
      child: AsyncFeature<(String, Clip)>(
        load: () => api.beginClip(widget.song.id),
        builder: (context, result, reload) {
          final data = result.$2;
          if (!initialized) {
            token = result.$1;
            start.text = (data.startMs / 1000).toString();
            end.text = data.endMs == 0 ? '' : (data.endMs / 1000).toString();
            initialized = true;
          }
          final issue = _validationIssue(duration);
          final max = duration > 0 ? duration : 600.0;
          final a = (double.tryParse(start.text) ?? 0).clamp(0.0, max);
          final parsedEnd = end.text.trim().isEmpty
              ? null
              : double.tryParse(end.text);
          final b = (parsedEnd ?? (duration > 0 ? duration : a + 1)).clamp(
            a,
            max,
          );
          final canEdit = !busy && active;
          final canSave = canEdit && issue == null && !unknownDuration;
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + insets.bottom),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Text(
                widget.song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${sourceShortLabel(widget.song.source)}'
                '${unknownDuration ? ' · 全长尚未就绪' : ' · 全长 ${formatClock(durationMs)}'}',
                style: TextStyle(color: context.zero.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                '片段按曲目 ID 保存，不修改原文件，也不导出音频。',
                style: TextStyle(color: context.zero.muted, fontSize: 13),
              ),
              if (!active) ...[
                const SizedBox(height: 12),
                Text(
                  '当前歌曲已切换，此编辑已停止。请返回后重新打开。',
                  style: TextStyle(color: context.zero.danger),
                ),
              ],
              if (issue != null) ...[
                const SizedBox(height: 12),
                Text(issue, style: TextStyle(color: context.zero.danger)),
              ],
              if (!unknownDuration) ...[
                const SizedBox(height: 20),
                RangeSlider(
                  min: 0,
                  max: duration,
                  values: RangeValues(a, b.clamp(0, duration)),
                  labels: RangeLabels(
                    '${a.toStringAsFixed(1)} 秒',
                    end.text.trim().isEmpty
                        ? '原曲结尾'
                        : '${b.toStringAsFixed(1)} 秒',
                  ),
                  onChanged: !canEdit
                      ? null
                      : (v) => setState(() {
                          start.text = v.start.toStringAsFixed(1);
                          end.text = v.end >= duration - 0.05
                              ? ''
                              : v.end.toStringAsFixed(1);
                        }),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: start,
                enabled: canEdit,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '起点（秒）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: end,
                enabled: canEdit,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '终点（秒）',
                  helperText: '留空表示播到原曲结尾。',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 24),
              if (busy) const LinearProgressIndicator(),
              OutlinedButton(
                onPressed: canSave ? () => _act('preview') : null,
                child: const Text('从起点试听整首'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: canSave ? () => _act('save') : null,
                child: const Text('保存片段'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: canEdit ? () => _act('clear') : null,
                child: const Text('清除片段'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: busy ? null : () => Navigator.maybePop(context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );
  }
}
