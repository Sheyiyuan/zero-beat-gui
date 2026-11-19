import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/app/theme.dart';
import 'package:zero_beat_gui/core/developer_log.dart';
import 'package:zero_beat_gui/features/developer_log_window.dart';
import 'package:zero_beat_gui/features/developer_mode.dart';
import 'package:zero_beat_gui/features/session.dart';
import 'package:zero_beat_gui/features/version_page.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/fake_core.dart';
import 'support/memory_developer_mode_store.dart';
import 'support/samples.dart';

class _VersionHello extends HelloController {
  _VersionHello(this.initial);
  final HelloState initial;

  @override
  HelloState build() => initial;
}

Future<void> _pumpVersion(
  WidgetTester tester,
  HelloState hello, {
  MemoryDeveloperModeStore? store,
  DeveloperLog? log,
}) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final core = FakeCoreApi();
  addTearDown(core.closeControllers);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        helloProvider.overrideWith(() => _VersionHello(hello)),
        coreApiProvider.overrideWithValue(core),
        developerModeStoreProvider.overrideWithValue(
          store ?? MemoryDeveloperModeStore(),
        ),
        developerLogProvider.overrideWithValue(
          log ?? DeveloperLog(capacity: 100),
        ),
      ],
      child: MaterialApp(
        theme: buildZeroTheme(),
        home: const Scaffold(body: VersionBody()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapCore(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    final target = find.byKey(const Key('version-core'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }
}

void main() {
  testWidgets('missing version data keeps app identity and a useful message', (
    tester,
  ) async {
    await _pumpVersion(tester, const HelloState());
    expect(find.text('零拍'), findsOneWidget);
    expect(find.text('版本信息暂不可用'), findsOneWidget);
    expect(find.text('连接恢复后，请重新打开此页。'), findsOneWidget);
    expect(find.byTooltip('复制数据目录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('version error preserves its reason', (tester) async {
    await _pumpVersion(tester, const HelloState(error: '连接已断开'));
    expect(find.text('读取版本信息失败'), findsOneWidget);
    expect(find.text('连接已断开'), findsOneWidget);
    expect(find.byTooltip('复制数据目录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreported values do not offer an empty directory copy', (
    tester,
  ) async {
    await _pumpVersion(
      tester,
      HelloState(
        result: HelloResult(
          api: 1,
          repo: 1,
          coreVersion: '',
          guiVersion: '',
          dataDir: '',
          capabilities: const [],
          accounts: const {},
          player: sampleHello().player,
        ),
      ),
    );
    expect(find.text('暂未获取版本号'), findsNWidgets(2));
    expect(find.text('暂未获取数据目录'), findsOneWidget);
    expect(find.byTooltip('复制数据目录'), findsNothing);
    expect(find.text('核心未报告能力'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long version and directory fit a narrow screen', (tester) async {
    final directory =
        '/home/user/${List.filled(16, 'long-directory').join('/')}/';
    await _pumpVersion(
      tester,
      HelloState(
        result: HelloResult(
          api: 1,
          repo: 1,
          coreVersion: '0.8.0-development-build',
          guiVersion: '1.2.3-development-build',
          dataDir: directory,
          capabilities: const ['internal-feature'],
          accounts: {
            'account': AccountBrief(loggedIn: true, name: 'private-account'),
          },
          player: sampleHello().player,
        ),
      ),
    );
    expect(find.text('private-account'), findsNothing);
    expect(find.text('internal-feature'), findsNothing);
    expect(find.text(directory), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal mode hides developer diagnostics and entries', (
    tester,
  ) async {
    await _pumpVersion(tester, HelloState(result: sampleHello()));
    expect(find.text('API 版本'), findsNothing);
    expect(find.text('仓库版本'), findsNothing);
    expect(find.text('能力列表'), findsNothing);
    expect(find.text('平台 / 目标'), findsNothing);
    expect(find.text('连接状态'), findsNothing);
    expect(find.byKey(const Key('version-runtime-log')), findsNothing);
    expect(find.byKey(const Key('version-exit-developer')), findsNothing);
  });

  testWidgets('five quick taps on the core version enable developer mode', (
    tester,
  ) async {
    final store = MemoryDeveloperModeStore();
    final log = DeveloperLog(capacity: 100);
    await _pumpVersion(
      tester,
      HelloState(result: sampleHello()),
      store: store,
      log: log,
    );

    await _tapCore(tester, times: 4);
    expect(find.text('API 版本'), findsNothing);
    await _tapCore(tester);
    await tester.pumpAndSettle();

    expect(find.text('API 版本'), findsOneWidget);
    expect(find.text('仓库版本'), findsOneWidget);
    expect(find.text('能力列表'), findsOneWidget);
    expect(find.text('平台 / 目标'), findsOneWidget);
    expect(find.text('连接状态'), findsOneWidget);
    expect(find.byKey(const Key('version-runtime-log')), findsOneWidget);
    expect(store.value, isTrue);
    expect(log.snapshot().any((entry) => entry.source == '版本'), isTrue);
    expect(find.text('已进入开发者模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an overlong pause resets the tap sequence', (tester) async {
    final store = MemoryDeveloperModeStore();
    await _pumpVersion(tester, HelloState(result: sampleHello()), store: store);

    await _tapCore(tester, times: 4);
    await tester.pump(const Duration(seconds: 3));
    await _tapCore(tester);
    expect(find.text('API 版本'), findsNothing);
    expect(store.value, isFalse);

    // Let the new one-tap sequence expire too, then a full sequence works.
    await tester.pump(const Duration(seconds: 3));
    await _tapCore(tester, times: 5);
    await tester.pumpAndSettle();
    expect(find.text('API 版本'), findsOneWidget);
    expect(store.value, isTrue);
  });

  testWidgets('a persisted developer flag restores the expanded page', (
    tester,
  ) async {
    await _pumpVersion(
      tester,
      HelloState(result: sampleHello()),
      store: MemoryDeveloperModeStore(true),
    );
    expect(find.byKey(const Key('version-dev-api')), findsOneWidget);
    expect(find.byKey(const Key('version-dev-repo')), findsOneWidget);
    expect(find.byKey(const Key('version-dev-platform')), findsOneWidget);
    expect(find.byKey(const Key('version-dev-connection')), findsOneWidget);
    expect(find.byKey(const Key('version-dev-capabilities')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('version-dev-api')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('version-dev-connection')),
        matching: find.text('已连接'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('version-dev-platform')),
        matching: find.text('linux'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('developer diagnostics never include account credentials', (
    tester,
  ) async {
    await _pumpVersion(
      tester,
      HelloState(
        result: HelloResult(
          api: 1,
          repo: 3,
          coreVersion: '0.8.0',
          guiVersion: '0.1.0-dev',
          dataDir: '/tmp/zero-beat',
          capabilities: const ['library', 'player'],
          accounts: {
            'bilibili': AccountBrief(
              loggedIn: true,
              name: 'private-account',
              notice: 'private-notice',
            ),
          },
          player: sampleHello().player,
        ),
      ),
      store: MemoryDeveloperModeStore(true),
    );
    expect(find.text('private-account'), findsNothing);
    expect(find.text('private-notice'), findsNothing);
    expect(find.text('library、player'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the runtime log entry opens and closes the floating window', (
    tester,
  ) async {
    addTearDown(closeDeveloperLogWindow);
    await _pumpVersion(
      tester,
      HelloState(result: sampleHello()),
      store: MemoryDeveloperModeStore(true),
    );
    final entry = find.byKey(const Key('version-runtime-log'));
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dev-log-panel')), findsOneWidget);
    expect(find.text('核心版本'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('dev-log-panel')),
        matching: find.text('运行日志'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('dev-log-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dev-log-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exit developer mode hides diagnostics and persists the choice', (
    tester,
  ) async {
    final store = MemoryDeveloperModeStore(true);
    await _pumpVersion(tester, HelloState(result: sampleHello()), store: store);
    final exit = find.byKey(const Key('version-exit-developer'));
    await tester.ensureVisible(exit);
    await tester.pumpAndSettle();
    await tester.tap(exit);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('version-dev-api')), findsNothing);
    expect(find.text('运行日志'), findsNothing);
    expect(store.value, isFalse);
    expect(find.text('已退出开发者模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
