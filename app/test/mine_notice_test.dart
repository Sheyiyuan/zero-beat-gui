import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_gui/app/layout.dart';
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

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('哔哩哔哩：未登录，匿名访问部分内容受限'), findsOneWidget);
    expect(find.text('网易云：未登录，可以匿名使用'), findsOneWidget);
    expect(find.textContaining('核心 0.8.0'), findsOneWidget);
    expect(find.text('本机：未登录，可以匿名使用'), findsNothing);
  });
}
