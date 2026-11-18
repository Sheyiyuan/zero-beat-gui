import 'package:zero_beat_core/engine_contract.dart';

class EngineLoad {
  EngineLoad({
    required this.playbackId,
    required this.stream,
    required this.startAtMs,
    required this.playWhenReady,
    required this.volume,
    required this.compDb,
    required this.autoGain,
  });

  final String playbackId;
  final EngineStream stream;
  final int startAtMs;
  final bool playWhenReady;
  final double volume;
  final double compDb;
  final bool autoGain;

  static EngineLoad fromJson(Map<String, Object?> json) => EngineLoad(
    playbackId: json['playback_id']?.toString() ?? '',
    stream: EngineStream.fromJson(json),
    startAtMs: (json['start_at_ms'] as num?)?.toInt() ?? 0,
    playWhenReady: json['play_when_ready'] == true,
    volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
    compDb: (json['comp_db'] as num?)?.toDouble() ?? 0,
    autoGain: json['auto_gain'] == true,
  );
}

class EngineReport {
  EngineReport({
    required this.playbackId,
    required this.seq,
    required this.state,
    required this.positionMs,
    required this.durationMs,
    this.error = '',
  });

  final String? playbackId;
  final int seq;
  final String state;
  final int positionMs;
  final int durationMs;
  final String error;

  Map<String, Object?> toJson() => {
    'playback_id': playbackId,
    'seq': seq,
    'state': state,
    'position_ms': positionMs,
    'duration_ms': durationMs,
    if (error.isNotEmpty) 'error': error,
  };
}

/// Dart 侧唯一的播放器所有者实现这个接口。
/// load 只表示参数已校验并进入串行队列，不表示已经出声。
abstract interface class EngineHost {
  Future<void> load(EngineLoad request);
  Future<void> pause(String playbackId);
  Future<void> resume(String playbackId);
  Future<void> stop(String playbackId);
  Future<void> seek(String playbackId, int positionMs);
  Future<void> volume(String playbackId, double volume);
  Future<void> compensation(String playbackId, double compDb);
  Future<void> autoGain(String playbackId, bool enabled);
  EngineReport reportState();
  List<String> get capabilities;
}
