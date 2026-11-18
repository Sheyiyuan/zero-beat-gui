import 'dart:convert';

import 'methods.dart';

class RpcException implements Exception {
  RpcException(this.code, this.message, {this.data = const {}});

  final int code;
  final String message;
  final Map<String, Object?> data;

  bool get cancelled => code == RpcCode.cancelled;

  @override
  String toString() => message.isEmpty ? 'RpcException($code)' : message;
}

class RpcMessage {
  RpcMessage({this.id, this.method, this.params, this.result, this.error});

  final int? id;
  final String? method;
  final Object? params;
  final Object? result;
  final RpcException? error;

  bool get isNotification => id == null && method != null && error == null;
  bool get isResponse => id != null && method == null;

  Map<String, Object?> toJson() {
    final out = <String, Object?>{'jsonrpc': '2.0'};
    if (id != null) out['id'] = id;
    if (method != null) out['method'] = method;
    if (params != null) out['params'] = params;
    if (result != null) out['result'] = result;
    if (error != null) {
      out['error'] = {
        'code': error!.code,
        'message': error!.message,
        'data': error!.data,
      };
    }
    return out;
  }

  static RpcMessage parseLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw RpcException(RpcCode.parse, '无法解析响应');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    RpcException? error;
    final rawError = json['error'];
    if (rawError is Map) {
      final map = rawError.map((key, value) => MapEntry(key.toString(), value));
      final data = map['data'];
      error = RpcException(
        (map['code'] as num?)?.toInt() ?? RpcCode.internal,
        map['message']?.toString() ?? '请求失败',
        data: data is Map
            ? data.map((key, value) => MapEntry(key.toString(), value))
            : const {},
      );
    }
    final rawId = json['id'];
    return RpcMessage(
      id: rawId is num ? rawId.toInt() : null,
      method: json['method']?.toString(),
      params: json['params'],
      result: json['result'],
      error: error,
    );
  }
}

Map<String, Object?> objectOf(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw RpcException(RpcCode.internal, '$name 不是对象');
}
