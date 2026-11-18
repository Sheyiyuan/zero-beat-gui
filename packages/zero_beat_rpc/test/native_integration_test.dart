import 'dart:io';
import 'package:test/test.dart';
import 'package:zero_beat_rpc/client.dart';
import 'client_test.dart' show FakeHost;

void main() {
  for (final platform in ['linux', 'android']) {
    test(
      'real $platform native core reconnects without starting twice and can restart after shutdown',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'zero-native-regression-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final native = await NativeCore.start(
          platform: platform,
          dataDir: dir.path,
        );
        addTearDown(native.close);
        expect(native.socketPath.isNotEmpty, platform == 'android');
        if (platform == 'android') expect(native.port, 0);
        final first = await native.connect(host: FakeHost());
        expect(first.helloResult!.coreVersion, '0.8.0');
        await first.stop();
        expect((await first.playerState()).playWhenReady, isFalse);
        await first.close();
        final second = await native.connect(host: FakeHost());
        expect(second.connected, isTrue);
        expect((await second.playerState()).playWhenReady, isFalse);
        await second.close();
        await native.close();
        final restarted = await NativeCore.start(
          platform: platform,
          dataDir: dir.path,
        );
        await restarted.close();
      },
      skip: Platform.environment['ZERO_BEAT_NATIVE_TEST'] != '1',
    );
  }
}
