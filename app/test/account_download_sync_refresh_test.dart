import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/feature_api.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('account list uses full names, live expiry state, and refresh', (
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
          )
          ..helloResult = HelloResult(
            api: hello.api,
            repo: hello.repo,
            coreVersion: hello.coreVersion,
            guiVersion: hello.guiVersion,
            dataDir: hello.dataDir,
            capabilities: hello.capabilities,
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
    await tester.tap(find.text('账号与登录'));
    await tester.pumpAndSettle();

    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);
    expect(find.text('已登录 · 小明'), findsOneWidget);
    expect(find.text('登录已失效，请重新登录'), findsOneWidget);
    expect(find.text('未登录，仍可播放公开内容'), findsNothing);

    final before = api.accountsCalls;
    final refreshes = api.accountsRefreshCalls;
    await tester.drag(
      find.byKey(const Key('accounts-refresh')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();
    expect(api.accountsCalls, before + 1);
    expect(api.accountsRefreshCalls, refreshes + 1);
    // The retained rows stay on screen after the reload.
    expect(find.text('已登录 · 小明'), findsOneWidget);
    expect(find.text('登录已失效，请重新登录'), findsOneWidget);
  });

  testWidgets('downloads list refreshes without starting new downloads', (
    tester,
  ) async {
    final api = FeatureApi(
      downloadTaskList: [sampleDownloadTask(id: 1)],
      downloadEntryList: [sampleDownloadEntry(songId: 'song-1')],
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
    await tester.tap(find.text('下载管理'));
    await tester.pumpAndSettle();

    expect(find.text('已下载'), findsOneWidget);
    expect(find.text('示例歌曲'), findsWidgets);
    final taskCalls = api.downloadTasksCalls;
    final listCalls = api.downloadsCalls;

    await tester.drag(
      find.byKey(const Key('downloads-refresh')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();

    expect(api.downloadTasksCalls, taskCalls + 1);
    expect(api.downloadsCalls, listCalls + 1);
    expect(api.featureMethods, isNot(contains('download.batch.start')));
  });

  testWidgets('download refresh failure keeps entries and shows a prompt', (
    tester,
  ) async {
    final api = FeatureApi(
      downloadEntryList: [sampleDownloadEntry(songId: 'song-keep')],
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
    await tester.tap(find.text('下载管理'));
    await tester.pumpAndSettle();
    expect(find.text('示例歌曲'), findsWidgets);

    api.failNext.add('download.tasks');
    await tester.drag(
      find.byKey(const Key('downloads-refresh')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();

    expect(find.text('刷新失败：测试失败'), findsOneWidget);
    expect(find.text('示例歌曲'), findsWidgets);
  });

  testWidgets('sync page refreshes status and keeps old content on failure', (
    tester,
  ) async {
    final api = FeatureApi(
      sync: sampleSyncStatus(auto: true),
      workList: [
        Work(id: 'w1', action: 'now', state: 'completed', message: '同步完成'),
      ],
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
    await tester.tap(find.text('曲库同步'));
    await tester.pumpAndSettle();

    expect(find.text('同步位置'), findsOneWidget);
    final statusCalls = api.syncStatusCalls;
    final taskCalls = api.tasksCalls;
    await tester.drag(
      find.byKey(const Key('sync-refresh')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();
    expect(api.syncStatusCalls, statusCalls + 1);
    expect(api.tasksCalls, taskCalls + 1);

    api.failNext.add('sync.status');
    await tester.drag(
      find.byKey(const Key('sync-refresh')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();
    expect(find.text('刷新失败：测试失败'), findsOneWidget);
    expect(find.text('同步位置'), findsOneWidget);
  });
}
