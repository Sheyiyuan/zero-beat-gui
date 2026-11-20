import 'dart:io';
import '../platform/storage.dart';
import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'audio_filters.dart';
import 'engine_player.dart';

class MediaKitEnginePlayer implements EnginePlayer {
  MediaKitEnginePlayer()
    : _player = Player(configuration: const PlayerConfiguration(title: '零拍'));

  static EnginePlayer create() {
    MediaKit.ensureInitialized();
    return MediaKitEnginePlayer();
  }

  final Player _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  EnginePlayerListener? _listener;
  int? _descriptor;

  @override
  Future<void> open({
    required String url,
    required Map<String, String> headers,
    Duration? start,
    Duration? end,
    required bool play,
  }) async {
    if (Platform.isAndroid && url.startsWith('content://')) {
      _descriptor = await AndroidStorage.openDescriptor(url);
      url = 'fd://${_descriptor!}';
    }
    return _player.open(
      Media(
        url,
        httpHeaders: headers.isEmpty ? null : Map<String, String>.from(headers),
        start: start,
        end: end,
      ),
      play: play,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double percent) async {
    await _player.setVolume(percent);
    // mpv marks the stream media.role=Music. WirePlumber restores that role's
    // saved volume on top of the cubic softvol above. TUI sets its stream to
    // unity and applies the slider in PCM, so leave the mixer at 100% too.
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('ao-volume', '100');
    } catch (_) {}
  }

  @override
  Future<bool> trySetFilter(String filter) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return false;
    if (await _writeAndCheck(platform, filter, property: true)) return true;
    if (await _writeAndCheck(platform, filter, property: false)) return true;
    await _clearFilter(platform);
    return false;
  }

  Future<void> _clearFilter(NativePlayer platform) async {
    try {
      await platform.setProperty('af', '');
    } catch (_) {}
  }

  Future<bool> _writeAndCheck(
    NativePlayer platform,
    String filter, {
    required bool property,
  }) async {
    try {
      if (property) {
        await platform.setProperty('af', filter);
      } else {
        await platform.command(['af', 'set', filter]);
      }
      final current = await platform.getProperty('af');
      return _filterStuck(current, filter);
    } catch (_) {
      return false;
    }
  }

  bool _filterStuck(String current, String filter) {
    if (current.isEmpty) return false;
    if (filter.contains('loudnorm') && !current.contains('loudnorm')) {
      return false;
    }
    if (filter.contains('I=-16') && !current.contains('I=-16')) return false;
    if (filter.contains('alimiter') && !current.contains('alimiter')) {
      return false;
    }
    if (filter.contains('volume=') && !current.contains('volume')) return false;
    return true;
  }

  @override
  void listen(EnginePlayerListener listener) {
    _listener = listener;
    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (!identical(_listener, listener)) return;
        listener.onPosition(position, _player.state.duration);
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((duration) {
        if (!identical(_listener, listener)) return;
        listener.onPosition(_player.state.position, duration);
      }),
    );
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (!identical(_listener, listener)) return;
        listener.onPlaying(playing);
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (!identical(_listener, listener)) return;
        listener.onBuffering(buffering);
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (!completed || !identical(_listener, listener)) return;
        listener.onCompleted();
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((message) {
        if (message.isEmpty || !identical(_listener, listener)) return;
        if (isUnsupportedAudioFilterError(message)) return;
        listener.onError(message);
      }),
    );
  }

  @override
  Future<void> dispose() async {
    _listener = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await _player.dispose();
    } finally {
      final fd = _descriptor;
      _descriptor = null;
      if (fd != null) await AndroidStorage.closeDescriptor(fd);
    }
  }
}
