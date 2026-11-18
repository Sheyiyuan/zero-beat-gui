import 'dart:isolate';

import 'package:zero_beat_rpc/client.dart';

/// Runs ZeroStart off the UI isolate. [openCore] and the player stay here.
Future<String> startZeroOffUiIsolate(String configJson) {
  return Isolate.run(() => startZeroNative(configJson));
}

Future<void> stopZeroOffUiIsolate() => Isolate.run(stopZeroNative);
