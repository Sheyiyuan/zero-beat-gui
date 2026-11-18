/// Strict primitives shared by generated codecs. Not part of the public API.
const int maxSafeInteger = 9007199254740991;
final BigInt _minInt64 = -(BigInt.one << 63);
final BigInt _maxInt64 = (BigInt.one << 63) - BigInt.one;

Never _invalid(String path, String expected) =>
    throw FormatException('$path: expected $expected');

String readString(Object? value, String path) =>
    value is String ? value : _invalid(path, 'string');
bool readBool(Object? value, String path) =>
    value is bool ? value : _invalid(path, 'boolean');
int readInt(Object? value, String path) =>
    value is int && value >= -maxSafeInteger && value <= maxSafeInteger
    ? value
    : _invalid(path, 'JSON safe integer');
int writeInt(int value) => readInt(value, 'integer');
double readDouble(Object? value, String path) => value is num && value.isFinite
    ? value.toDouble()
    : _invalid(path, 'finite number');
double writeDouble(double value) => readDouble(value, 'number');

BigInt readDecimal(Object? value, String path) {
  if (value is! String || !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) {
    return _invalid(path, 'decimal int64 string');
  }
  final parsed = BigInt.tryParse(value);
  if (parsed == null ||
      parsed < _minInt64 ||
      parsed > _maxInt64 ||
      parsed.toString() != value) {
    return _invalid(path, 'decimal int64 string');
  }
  return parsed;
}

String writeDecimal(BigInt value) {
  if (value < _minInt64 || value > _maxInt64) {
    return _invalid('integer', 'signed int64');
  }
  return value.toString();
}

DateTime readTimestamp(Object? value, String path) {
  // Reject impossible dates instead of DateTime.parse's overflow normalization.
  if (value is! String) return _invalid(path, 'UTC RFC3339 timestamp');
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?Z$',
  ).firstMatch(value);
  final parsed = DateTime.tryParse(value);
  if (match == null || parsed == null) {
    return _invalid(path, 'UTC RFC3339 timestamp');
  }
  final actual = [
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
  ];
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != int.parse(match.group(i + 1)!)) {
      return _invalid(path, 'valid UTC timestamp');
    }
  }
  return parsed.toUtc();
}

String writeTimestamp(DateTime value) {
  final canonical = DateTime.fromMillisecondsSinceEpoch(
    value.millisecondsSinceEpoch,
    isUtc: true,
  );
  final text = canonical.toIso8601String();
  readTimestamp(text, 'timestamp');
  return text;
}

Map<String, Object?> readObject(Object? value, String path) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    return _invalid(path, 'object with string keys');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> readList(Object? value, String path) =>
    value is List ? List<Object?>.from(value) : _invalid(path, 'array');

Map<String, String> readStringMap(Object? value, String path) => readObject(
  value,
  path,
).map((key, item) => MapEntry(key, readString(item, '$path.$key')));
