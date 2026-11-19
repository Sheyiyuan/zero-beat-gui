import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/layout.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import 'support/fake_core.dart';
import 'support/pump_app.dart';
import 'support/samples.dart';

void main() {
  testWidgets('mine page replaces a stale logged-in hello with expired state', (
    tester,
  ) async {
    final hello = sampleHello();
    final api = LiveMineApi()
      ..helloResult = HelloResult(
        api: hello.api,
        repo: hello.repo,
        coreVersion: hello.coreVersion,
        guiVersion: hello.guiVersion,
        dataDir: hello.dataDir,
        capabilities: hello.capabilities,
        accounts: {'netease': AccountBrief(loggedIn: true, name: '旧账号')},
        player: hello.player,
      )
      ..sources = [
        SourceInfo(
          id: SourceID.valueNetease,
          name: '网易云',
          mark: '云',
          capabilities: SourceCapabilities(
            names: const ['account'],
            unknownBits: BigInt.zero,
          ),
          user: User(id: '', name: '', avatar: '', loggedIn: false),
        ),
      ];
    addTearDown(api.closeControllers);
    await pumpApp(
      tester,
      api: api,
      layout: AppLayout.mobile,
      size: const Size(800, 900),
    );

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(api.refreshCalls, greaterThanOrEqualTo(1));
    expect(find.text('网易云 登录已失效'), findsOneWidget);
    expect(find.textContaining('旧账号'), findsNothing);
  });
}

class LiveMineApi extends FakeCoreApi implements CoreFeatureTransport {
  final _changes = StreamController<String>.broadcast();
  List<SourceInfo> sources = const [];
  int refreshCalls = 0;

  @override
  Stream<String> get changes => _changes.stream;

  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) async {
    if (method != 'auth.accounts') {
      throw UnsupportedError(method);
    }
    if (params['refresh'] == true) refreshCalls++;
    return {'sources': sources.map((source) => source.toJson()).toList()};
  }

  @override
  Future<void> closeControllers() async {
    await _changes.close();
    await super.closeControllers();
  }
}
