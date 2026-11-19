import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_gui/shared/playback.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('mine page shows the source restriction from hello', (
    tester,
  ) async {
    final hello = sampleHello();
    final api = FakeCoreApi()
      ..helloResult = HelloResult(
        api: hello.api,
        repo: hello.repo,
        coreVersion: hello.coreVersion,
        guiVersion: hello.guiVersion,
        dataDir: hello.dataDir,
        capabilities: hello.capabilities,
        accounts: {
          'bilibili': AccountBrief(
            loggedIn: false,
            name: '',
            notice: '未登录，匿名访问部分内容受限',
          ),
          'netease': AccountBrief(loggedIn: false, name: ''),
        },
        player: hello.player,
      );
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(800, 900),
    );

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('与核心的连接已断开，正在自动重连'), findsNothing);
    expect(find.text('哔哩哔哩 未登录 · 网易云 未登录'), findsOneWidget);
    expect(find.text('版本信息'), findsOneWidget);
    expect(find.textContaining('核心 0.8.0'), findsNothing);
    expect(find.text('本机：未登录，仍可播放公开内容'), findsNothing);
  });

  testWidgets(
    'refreshing mine dismisses stale errors and keeps the player bar',
    (tester) async {
      const stale = '播放失败：无法打开音频';
      final api = FakeCoreApi();
      addTearDown(api.closeControllers);
      await pumpApp(
        tester,
        api: api,
        layout: AppLayout.mobile,
        size: const Size(800, 900),
      );
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();

      api.notify(stale);
      api.emit(playerView(notice: stale));
      await tester.pumpAndSettle();

      expect(_onMine(stale), findsWidgets);
      expect(find.text(stale), findsWidgets);

      await tester.fling(
        find.descendant(
          of: find.byKey(const Key('mine-refresh')),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(_onMine(stale), findsNothing);
      expect(find.text(stale), findsOneWidget);

      api.notify('同步已恢复');
      api.emit(playerView(notice: '正在重试…'));
      await tester.pumpAndSettle();

      expect(_onMine('同步已恢复'), findsOneWidget);
      expect(_onMine('正在重试…'), findsOneWidget);
    },
  );
}

Finder _onMine(String text) => find.descendant(
  of: find.byKey(const Key('mine-refresh')),
  matching: find.text(text),
);
