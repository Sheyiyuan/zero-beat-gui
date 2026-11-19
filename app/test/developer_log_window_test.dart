import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/app/theme.dart';
import 'package:zero_beat_gui/core/developer_log.dart';
import 'package:zero_beat_gui/features/developer_log_export.dart';
import 'package:zero_beat_gui/features/developer_log_window.dart';

class _FakeClipboard implements DeveloperLogClipboard {
  String? text;

  @override
  Future<void> setText(String value) async {
    text = value;
  }
}

class _FakeExporter implements DeveloperLogExporter {
  String? fileName;
  String? contents;
  DeveloperLogExportResult result = const DeveloperLogExportResult.exported(
    '/tmp/zero-beat-log.txt',
  );

  @override
  Future<DeveloperLogExportResult> export({
    required String fileName,
    required String contents,
  }) async {
    this.fileName = fileName;
    this.contents = contents;
    return result;
  }
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required DeveloperLog log,
  required _FakeClipboard clipboard,
  required _FakeExporter exporter,
  Size size = const Size(1000, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(closeDeveloperLogWindow);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        developerLogProvider.overrideWithValue(log),
        developerLogClipboardProvider.overrideWithValue(clipboard),
        developerLogExporterProvider.overrideWithValue(exporter),
      ],
      child: MaterialApp(
        theme: buildZeroTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('版本页内容'),
                  FilledButton(
                    key: const Key('open-log'),
                    onPressed: () => showDeveloperLogWindow(context),
                    child: const Text('打开日志'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openLog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-log')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('log window opens as a draggable overlay, not a page', (
    tester,
  ) async {
    final log = DeveloperLog(capacity: 100)..info('测试', '第一条');
    await _pumpHost(
      tester,
      log: log,
      clipboard: _FakeClipboard(),
      exporter: _FakeExporter(),
    );
    await _openLog(tester);

    expect(find.byKey(const Key('dev-log-panel')), findsOneWidget);
    expect(find.text('版本页内容'), findsOneWidget);
    expect(find.text('运行日志'), findsOneWidget);
    expect(find.text('测试 · 第一条'), findsOneWidget);

    final before = tester.getTopLeft(find.byKey(const Key('dev-log-panel')));
    await tester.drag(
      find.byKey(const Key('dev-log-header')),
      const Offset(-40, 20),
    );
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byKey(const Key('dev-log-panel')));
    expect(after.dx, closeTo(before.dx - 40, 1));
    expect(after.dy, closeTo(before.dy + 20, 1));

    await tester.tap(find.byKey(const Key('dev-log-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dev-log-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy, clear and export use the injected helpers', (
    tester,
  ) async {
    final log = DeveloperLog(capacity: 100)
      ..info('测试', '第一条')
      ..warning('测试', '第二条');
    final clipboard = _FakeClipboard();
    final exporter = _FakeExporter();
    await _pumpHost(tester, log: log, clipboard: clipboard, exporter: exporter);
    await _openLog(tester);

    await tester.tap(find.byKey(const Key('dev-log-copy')));
    await tester.pumpAndSettle();
    expect(clipboard.text, log.asText());
    expect(find.text('日志已复制'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dev-log-export')));
    await tester.pumpAndSettle();
    expect(exporter.contents, log.asText());
    expect(exporter.fileName, startsWith('zero-beat-log-'));
    expect(exporter.fileName, endsWith('.txt'));
    expect(find.text('日志已导出到 /tmp/zero-beat-log.txt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dev-log-clear')));
    await tester.pumpAndSettle();
    expect(log.isEmpty, isTrue);
    expect(find.byKey(const Key('dev-log-empty')), findsOneWidget);
    expect(find.text('暂无日志'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty log disables copy, clear and export', (tester) async {
    final log = DeveloperLog(capacity: 100);
    await _pumpHost(
      tester,
      log: log,
      clipboard: _FakeClipboard(),
      exporter: _FakeExporter(),
    );
    await _openLog(tester);

    expect(find.byKey(const Key('dev-log-empty')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('dev-log-copy')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('dev-log-clear')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('dev-log-export')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-scroll can be paused and resumed', (tester) async {
    final log = DeveloperLog(capacity: 100)..info('测试', '第一条');
    await _pumpHost(
      tester,
      log: log,
      clipboard: _FakeClipboard(),
      exporter: _FakeExporter(),
    );
    await _openLog(tester);

    expect(find.byTooltip('暂停自动滚动'), findsOneWidget);
    expect(find.text('自动滚动已开启'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dev-log-autoscroll')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('恢复自动滚动'), findsOneWidget);
    expect(find.text('自动滚动已暂停'), findsOneWidget);
    expect(find.byKey(const Key('dev-log-jump-latest')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dev-log-jump-latest')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('暂停自动滚动'), findsOneWidget);
    expect(find.text('自动滚动已开启'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manually scrolling the list pauses auto-scroll', (tester) async {
    final log = DeveloperLog(capacity: 200);
    for (var i = 0; i < 60; i++) {
      log.info('测试', '第 $i 条消息，用于让列表产生足够的高度');
    }
    await _pumpHost(
      tester,
      log: log,
      clipboard: _FakeClipboard(),
      exporter: _FakeExporter(),
    );
    await _openLog(tester);
    expect(find.text('自动滚动已开启'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('dev-log-list')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    expect(find.text('自动滚动已暂停'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
