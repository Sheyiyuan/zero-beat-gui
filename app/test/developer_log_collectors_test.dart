import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_gui/app/developer_log_collectors.dart';
import 'package:zero_beat_gui/app/providers.dart';
import 'package:zero_beat_gui/core/developer_log.dart';
import 'package:zero_beat_gui/shared/playback.dart';

import 'support/fake_core.dart';

Future<DeveloperLog> _pumpCollectors(
  WidgetTester tester,
  FakeCoreApi api,
) async {
  final log = DeveloperLog(capacity: 100);
  addTearDown(api.closeControllers);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coreApiProvider.overrideWithValue(api),
        developerLogProvider.overrideWithValue(log),
      ],
      child: const DeveloperLogCollectors(child: SizedBox.expand()),
    ),
  );
  await tester.pump();
  return log;
}

void main() {
  testWidgets('collects startup, connection, notice and player events', (
    tester,
  ) async {
    final api = FakeCoreApi();
    final log = await _pumpCollectors(tester, api);

    expect(log.snapshot().any((entry) => entry.source == '应用'), isTrue);
    expect(
      log.snapshot().any(
        (entry) => entry.source == '连接' && entry.message.contains('已连接'),
      ),
      isTrue,
    );

    api.disconnect();
    await tester.pump();
    expect(
      log.snapshot().any(
        (entry) => entry.source == '连接' && entry.message.contains('断开'),
      ),
      isTrue,
    );

    api.notify('核心通知');
    await tester.pump();
    expect(
      log.snapshot().any(
        (entry) => entry.source == '核心' && entry.message == '核心通知',
      ),
      isTrue,
    );

    api.emit(playerView(notice: '播放器提示'));
    await tester.pump();
    expect(
      log.snapshot().any(
        (entry) => entry.source == '播放' && entry.message == '播放器提示',
      ),
      isTrue,
    );

    api.emit(playerView(state: PlaybackStatus.valueFailed, notice: '解码失败'));
    await tester.pump();
    expect(
      log.snapshot().any(
        (entry) =>
            entry.level == DeveloperLogLevel.error &&
            entry.message.contains('解码失败'),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('redacts secrets in notices before storing', (tester) async {
    final api = FakeCoreApi();
    final log = await _pumpCollectors(tester, api);

    api.notify('token=secret123456&next=1');
    api.notify('Authorization: Bearer abcdefghijklmnop');
    await tester.pump();

    final text = log.asText();
    expect(text, isNot(contains('secret123456')));
    expect(text, isNot(contains('abcdefghijklmnop')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not store duplicate consecutive notices', (tester) async {
    final api = FakeCoreApi();
    final log = await _pumpCollectors(tester, api);

    api.notify('同一条通知');
    api.notify('同一条通知');
    await tester.pump();
    expect(log.snapshot().where((entry) => entry.message == '同一条通知').length, 1);
  });

  testWidgets('cancels stream subscriptions when unmounted', (tester) async {
    final api = FakeCoreApi();
    final log = await _pumpCollectors(tester, api);
    final before = log.length;

    await tester.pumpWidget(const SizedBox.shrink());
    api.notify('卸载后的通知');
    await tester.pump();
    expect(log.length, before);
  });
}
