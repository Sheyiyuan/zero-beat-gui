import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_beat_core/zero_beat_core.dart';
import 'package:zero_beat_rpc/zero_beat_rpc.dart';

import '../core/developer_log.dart';
import 'providers.dart';

/// Subscribes to the core streams and mirrors user-visible diagnostics into
/// [DeveloperLog]. Installed once near the app root; stream subscriptions are
/// cancelled together with the widget.
class DeveloperLogCollectors extends ConsumerStatefulWidget {
  const DeveloperLogCollectors({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DeveloperLogCollectors> createState() =>
      _DeveloperLogCollectorsState();
}

class _DeveloperLogCollectorsState
    extends ConsumerState<DeveloperLogCollectors> {
  StreamSubscription<bool>? _connections;
  StreamSubscription<String>? _notices;
  StreamSubscription<PlayerView>? _states;
  String _lastNotice = '';
  String _lastPlayerNotice = '';
  PlaybackStatus? _lastPlaybackState;

  @override
  void initState() {
    super.initState();
    final api = ref.read(coreApiProvider);
    final log = ref.read(developerLogProvider);
    final platform = ref.read(platformLabelProvider);
    final hello = api.helloResult;
    log.info(
      '应用',
      '平台 $platform'
          '${hello == null ? '' : '，核心 ${hello.coreVersion}，GUI ${hello.guiVersion}'}',
    );
    if (api.connected) log.info('连接', '已连接核心');
    _connections = api.connections.listen((connected) {
      if (!mounted) return;
      log.info('连接', connected ? '已连接核心' : '与核心的连接已断开');
    });
    _notices = api.notices.listen((text) {
      if (!mounted || text.isEmpty || text == _lastNotice) return;
      _lastNotice = text;
      log.warning('核心', text);
    });
    _states = api.states.listen(_onPlayerState);
    final initial = hello?.player;
    if (initial != null) _onPlayerState(initial);
  }

  void _onPlayerState(PlayerView view) {
    if (!mounted) return;
    final log = ref.read(developerLogProvider);
    final notice = view.notice;
    if (notice.isNotEmpty && notice != _lastPlayerNotice) {
      log.add(
        view.noticeLevel == 'error'
            ? DeveloperLogLevel.error
            : DeveloperLogLevel.warning,
        '播放',
        notice,
      );
    }
    _lastPlayerNotice = notice;
    final state = view.snapshot.state;
    if (state == PlaybackStatus.valueFailed &&
        _lastPlaybackState != PlaybackStatus.valueFailed) {
      log.error('播放', notice.isEmpty ? '播放失败' : '播放失败：$notice');
    }
    _lastPlaybackState = state;
  }

  @override
  void dispose() {
    unawaited(_connections?.cancel());
    unawaited(_notices?.cancel());
    unawaited(_states?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
