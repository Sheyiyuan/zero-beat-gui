import 'package:flutter/foundation.dart';

/// Severity used by the in-app developer log. The labels stay short so a log
/// row remains readable on a phone.
enum DeveloperLogLevel {
  debug('调试'),
  info('信息'),
  warning('警告'),
  error('错误');

  const DeveloperLogLevel(this.label);

  final String label;
}

/// Immutable log record. The message has already been passed through
/// [redactSensitive] when this object is created.
class DeveloperLogEntry {
  const DeveloperLogEntry({
    required this.time,
    required this.level,
    required this.source,
    required this.message,
  });

  final DateTime time;
  final DeveloperLogLevel level;
  final String source;
  final String message;

  String get timeLabel => formatDeveloperLogTime(time);

  String get exportLine =>
      '${formatDeveloperLogTime(time, withDate: true)} '
      '[${level.label}] ${source.isEmpty ? '应用' : source}: $message';
}

String formatDeveloperLogTime(DateTime time, {bool withDate = false}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final clock =
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
      '${time.millisecond.toString().padLeft(3, '0')}';
  if (!withDate) return clock;
  return '${time.year}-${two(time.month)}-${two(time.day)} $clock';
}

final _headerSecrets = RegExp(
  r'\b(cookie|set-cookie|authorization|proxy-authorization)\b\s*:\s*[^\r\n]+',
  caseSensitive: false,
  multiLine: true,
);

final _keyValueSecrets = RegExp(
  r'''\b(?:cookie|set-cookie|authorization|proxy-authorization|token|access[_-]?token|refresh[_-]?token|id[_-]?token|password|passwd|passphrase|secret|client[_-]?secret|api[_-]?key|session[_-]?id|sessionid|session[_-]?key|sessdata|bili_jct|bili_ticket|dedeuserid|buvid3|music_u|__csrf|nmtid|access[_-]?key|refresh[_-]?key|mfa)\b["']?\s*[:=：]\s*("[^"]*"|'[^']*'|[^\s,;&}\]]+)''',
  caseSensitive: false,
);

final _bearerSecrets = RegExp(
  r'\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}',
  caseSensitive: false,
);

final _jwtSecrets = RegExp(
  r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
);

final _wordSecrets = RegExp(
  r'\b(token|password|passphrase|secret|authorization|cookie)\b\s+'
  r'(?=[A-Za-z0-9._~+/=-]*\d)[A-Za-z0-9._~+/=-]{6,}',
  caseSensitive: false,
);

final _chineseSecrets = RegExp(r'(密码|口令|令牌)\s*[:：=]\s*[^\s，。；;]+');

final _longTokens = RegExp(r'\b[A-Za-z0-9_-]{24,}\b');

/// Best-effort redaction for log messages that might contain a credential.
///
/// This is a safety net, never a reason to log secrets deliberately. It covers
/// Authorization/Cookie headers, common key/value names (JSON and query-string
/// forms), bearer/basic credentials, JWTs, Chinese password labels, and long
/// opaque token-shaped strings.
String redactSensitive(String message) {
  var clean = message;
  clean = clean.replaceAll(_headerSecrets, '<redacted>');
  clean = clean.replaceAll(_keyValueSecrets, '<redacted>');
  clean = clean.replaceAllMapped(
    _bearerSecrets,
    (match) => '${match.group(1)} <redacted>',
  );
  clean = clean.replaceAll(_jwtSecrets, '<redacted>');
  clean = clean.replaceAllMapped(
    _wordSecrets,
    (match) => '${match.group(1)} <redacted>',
  );
  clean = clean.replaceAll(_chineseSecrets, '<redacted>');
  clean = clean.replaceAll(_longTokens, '<redacted>');
  return clean;
}

/// A small synchronous ring buffer for developer diagnostics.
///
/// Dart isolates run one event-loop turn at a time and every mutation below is
/// synchronous, so appends and snapshots cannot interleave inside an isolate.
/// The log is process-local; a second isolate gets no shared state and should
/// not be expected to feed this buffer.
class DeveloperLog extends ChangeNotifier {
  DeveloperLog({this.capacity = defaultCapacity, DateTime Function()? clock})
    : assert(capacity > 0),
      _clock = clock ?? DateTime.now,
      _entries = List<DeveloperLogEntry?>.filled(capacity, null);

  static const defaultCapacity = 2000;
  static const maxMessageLength = 8000;

  static final DeveloperLog instance = DeveloperLog();

  final int capacity;
  final DateTime Function() _clock;
  final List<DeveloperLogEntry?> _entries;

  int _start = 0;
  int _length = 0;
  int _revision = 0;

  /// Monotonically increasing counter. Widgets use it to decide whether a
  /// rebuild actually brought new rows.
  int get revision => _revision;

  int get length => _length;

  bool get isEmpty => _length == 0;

  void add(
    DeveloperLogLevel level,
    String source,
    String message, {
    DateTime? time,
  }) {
    var clean = redactSensitive(message);
    if (clean.length > maxMessageLength) {
      clean = '${clean.substring(0, maxMessageLength)}…';
    }
    final entry = DeveloperLogEntry(
      time: time ?? _clock(),
      level: level,
      source: source,
      message: clean,
    );
    if (_length < capacity) {
      _entries[(_start + _length) % capacity] = entry;
      _length++;
    } else {
      _entries[_start] = entry;
      _start = (_start + 1) % capacity;
    }
    _revision++;
    notifyListeners();
  }

  void debug(String source, String message) =>
      add(DeveloperLogLevel.debug, source, message);

  void info(String source, String message) =>
      add(DeveloperLogLevel.info, source, message);

  void warning(String source, String message) =>
      add(DeveloperLogLevel.warning, source, message);

  void error(String source, String message) =>
      add(DeveloperLogLevel.error, source, message);

  /// Oldest-to-newest copy. Callers cannot mutate the buffer through it.
  List<DeveloperLogEntry> snapshot() {
    return List<DeveloperLogEntry>.generate(
      _length,
      (index) => _entries[(_start + index) % capacity]!,
      growable: false,
    );
  }

  String asText() {
    final buffer = StringBuffer()..writeln('# 零拍运行日志');
    for (final entry in snapshot()) {
      buffer.writeln(entry.exportLine);
    }
    return buffer.toString().trimRight();
  }

  void clear() {
    _entries.fillRange(0, capacity, null);
    _start = 0;
    _length = 0;
    _revision++;
    notifyListeners();
  }
}

bool _errorHandlersInstalled = false;

/// Installs process-wide Flutter error capture exactly once.
///
/// Existing handlers are chained rather than replaced so the default red
/// screen/test failure behaviour is preserved.
void installDeveloperLogErrorHandlers({DeveloperLog? log}) {
  if (_errorHandlersInstalled) return;
  _errorHandlersInstalled = true;
  final target = log ?? DeveloperLog.instance;
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    target.error('Flutter', details.exceptionAsString());
    if (previousFlutter != null) {
      previousFlutter(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    target.error('Flutter', error.toString());
    return previousPlatform?.call(error, stack) ?? false;
  };
}
