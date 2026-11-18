import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';
import 'package:zero_beat_gui/platform/storage.dart';
import 'support/fake_core.dart';
import 'support/samples.dart';

class StorageApi extends FakeCoreApi implements CoreFeatureTransport {
  final calls = <String>[];
  @override
  Stream<String> get changes => const Stream.empty();
  @override
  Future<Map<String, Object?>> featureCall(
    String method,
    Map<String, Object?> params,
  ) async {
    calls.add(method);
    switch (method) {
      case 'library.resource.begin':
        return {'token': 'scan'};
      case 'library.resource.lyrics':
        throw StateError('bad sidecar');
      case 'library.resource.commit':
        return {
          'playlist': samplePlaylist().toJson(),
          'subdirs': 0,
          'scanned': 1,
          'added': 1,
          'reused': 0,
          'missing': 0,
          'warning_count': 1,
        };
      default:
        return {};
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const uri = 'content://provider/tree/music';
  test(
    'cancel enumeration interrupts provider and releases only the new grant',
    () async {
      final api = StorageApi();
      addTearDown(api.closeControllers);
      final entered = Completer<void>(), enumeration = Completer<Object?>();
      final native = <String>[];
      messenger.setMockMethodCallHandler(AndroidStorage.channel, (call) async {
        native.add(call.method);
        switch (call.method) {
          case 'grants':
            return <String>[];
          case 'pickDirectory':
            return uri;
          case 'enumerate':
            entered.complete();
            return enumeration.future;
          case 'cancelScan':
            enumeration.completeError(PlatformException(code: 'cancelled'));
            return null;
          default:
            return null;
        }
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(AndroidStorage.channel, null),
      );
      final cancel = AndroidScanCancellation();
      final running = AndroidStorage.scan(api, cancellation: cancel);
      await entered.future;
      cancel.cancel();
      expect(await running, isNull);
      expect(native, contains('cancelScan'));
      expect(native, contains('release'));
      expect(api.calls, isEmpty);
    },
  );
  test(
    'bad sidecar preserves audio scan and closes every borrowed descriptor',
    () async {
      final api = StorageApi();
      addTearDown(api.closeControllers);
      final native = <String>[];
      messenger.setMockMethodCallHandler(AndroidStorage.channel, (call) async {
        native.add(call.method);
        switch (call.method) {
          case 'grants':
            return [uri];
          case 'pickDirectory':
            return uri;
          case 'enumerate':
            return {
              'title': 'music',
              'files': [
                {'name': 'track.flac', 'uri': '$uri/track.flac'},
              ],
              'lyrics': {'lyrics/track.lrc': '$uri/lyrics/track.lrc'},
            };
          case 'open':
            return 17;
          case 'duration':
            return 20;
          default:
            return null;
        }
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(AndroidStorage.channel, null),
      );
      expect(await AndroidStorage.scan(api), isNotNull);
      expect(
        api.calls,
        containsAllInOrder([
          'library.resource.lyrics',
          'library.resource.skip',
          'library.resource.inspect',
          'library.resource.commit',
        ]),
      );
      expect(native.where((m) => m == 'close'), hasLength(2));
      expect(native, isNot(contains('release')));
    },
  );
}
