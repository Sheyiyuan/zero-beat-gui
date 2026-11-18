import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../core/interruption_policy.dart';
import '../engine/playback_host.dart';

final coreApiProvider = Provider<CoreApi>((ref) {
  throw StateError('CoreApi 未注入');
});

final interruptionPolicyProvider = Provider<InterruptionPolicy>((ref) {
  return InterruptionPolicy();
});

final playbackHostProvider = Provider<PlaybackHost?>((ref) => null);

final platformLabelProvider = Provider<String>((ref) => 'linux');

final engineCapabilitiesProvider = Provider<List<String>>((ref) {
  return ref.watch(playbackHostProvider)?.capabilities ?? const ['clip'];
});

final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'search');
  ref.onDispose(node.dispose);
  return node;
});

final quitActionProvider = Provider<Future<void> Function()>((ref) {
  final api = ref.watch(coreApiProvider);
  return () async {
    await api.quit();
    exit(0);
  };
});

final reconnectActionProvider = Provider<VoidCallback>((ref) => () {});
