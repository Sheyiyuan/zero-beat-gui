import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/feature_api.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('mine entries summarize live accounts, sync, and downloads', (
    tester,
  ) async {
    final hello = sampleHello();
    final api =
        FeatureApi(
            sources: [
              sampleSource(
                id: 'bilibili',
                name: 'B站',
                loggedIn: true,
                userName: '小明',
              ),
              sampleSource(id: 'netease', name: '网易云'),
            ],
            sync: sampleSyncStatus(auto: true, hasError: true),
            downloadTaskList: [sampleDownloadTask(id: 1)],
            downloadEntryList: [
              sampleDownloadEntry(songId: 'song-1'),
              sampleDownloadEntry(songId: 'song-2'),
            ],
          )
          ..helloResult = HelloResult(
            api: hello.api,
            repo: hello.repo,
            coreVersion: hello.coreVersion,
            guiVersion: hello.guiVersion,
            dataDir: '/tmp/zero-beat-test',
            capabilities: hello.capabilities,
            // The handshake snapshot is stale: netease says logged in but the live
            // source list says the session expired.
            accounts: {
              'bilibili': AccountBrief(loggedIn: false, name: ''),
              'netease': AccountBrief(loggedIn: true, name: '旧账号'),
            },
            player: hello.player,
          );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(800, 1100),
    );
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.text('哔哩哔哩 已登录 · 网易云 登录已失效'), findsOneWidget);
    expect(find.text('自动同步已开启 · 最近同步失败'), findsOneWidget);
    expect(find.text('已下载 2 首 · 1 首下载失败'), findsOneWidget);
    expect(find.text('版本信息'), findsOneWidget);
    // Version details live on their own page now.
    expect(find.textContaining('核心 0.8.0'), findsNothing);
    expect(find.textContaining('能力 library'), findsNothing);
  });

  testWidgets(
    'version page shows app version, diagnostics, and a copyable data dir',
    (tester) async {
      final hello = sampleHello();
      final api = FeatureApi()
        ..helloResult = HelloResult(
          api: 7,
          repo: 9,
          coreVersion: '9.9.9',
          guiVersion: '1.2.3',
          dataDir: '/home/user/.zero-beat',
          capabilities: const ['library', 'search'],
          accounts: const {},
          player: hello.player,
        );
      addTearDown(api.closeControllers);
      await pumpApp(
        tester,
        api: api,
        layout: AppLayout.mobile,
        size: const Size(800, 1100),
      );
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('版本信息'));
      await tester.pumpAndSettle();

      expect(find.text('核心版本'), findsOneWidget);
      expect(find.text('零拍'), findsOneWidget);
      expect(find.text('诊断信息'), findsOneWidget);
      expect(find.text('界面版本'), findsNothing);
      expect(find.text('9.9.9'), findsOneWidget);
      expect(find.text('版本 1.2.3'), findsOneWidget);
      expect(find.text('API 版本'), findsNothing);
      expect(find.text('7'), findsNothing);
      expect(find.text('仓库版本'), findsNothing);
      expect(find.text('9'), findsNothing);
      expect(find.text('library'), findsNothing);
      expect(find.text('search'), findsNothing);
      final dir = tester.widget<SelectableText>(
        find.byKey(const Key('version-data-dir')),
      );
      expect(dir.data, '/home/user/.zero-beat');
      expect(find.text('能力'), findsNothing);
      expect(find.textContaining('token'), findsNothing);
      expect(find.textContaining('cookie'), findsNothing);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byTooltip('复制数据目录'));
      await tester.pumpAndSettle();
      expect(copied, '/home/user/.zero-beat');
      expect(find.text('数据目录已复制'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mine page pull-to-refresh reloads all summaries and keeps rows',
    (tester) async {
      final api = FeatureApi(
        sources: [sampleSource(id: 'bilibili', loggedIn: true, userName: '小明')],
        sync: sampleSyncStatus(auto: true),
        downloadTaskList: const [],
        downloadEntryList: [sampleDownloadEntry()],
      );
      addTearDown(api.closeControllers);
      await pumpApp(
        tester,
        api: api,
        layout: AppLayout.mobile,
        size: const Size(800, 1100),
      );
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();

      expect(api.accountsCalls, 1);
      expect(api.syncStatusCalls, 1);
      expect(api.downloadTasksCalls, 1);
      await tester.drag(
        find.byKey(const Key('mine-refresh')),
        const Offset(0, 320),
      );
      await tester.pumpAndSettle();

      expect(api.accountsCalls, greaterThanOrEqualTo(2));
      expect(api.accountsRefreshCalls, greaterThanOrEqualTo(2));
      expect(api.syncStatusCalls, greaterThanOrEqualTo(2));
      expect(api.downloadTasksCalls, greaterThanOrEqualTo(2));
      expect(find.text('哔哩哔哩 已登录'), findsOneWidget);
    },
  );

  testWidgets('mine refresh failure keeps old summaries and prompts', (
    tester,
  ) async {
    final api = FeatureApi(
      sources: [sampleSource(id: 'bilibili', loggedIn: true, userName: '小明')],
      sync: sampleSyncStatus(auto: true),
      downloadTaskList: const [],
      downloadEntryList: const [],
    );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(800, 1100),
    );
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    final before = find.text('自动同步已开启 · 状态正常');
    expect(before, findsOneWidget);

    api.failNext.add('sync.status');
    await tester.drag(
      find.byKey(const Key('mine-refresh')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();

    expect(before, findsOneWidget);
    expect(find.text('刷新失败：测试失败'), findsOneWidget);
  });
}
