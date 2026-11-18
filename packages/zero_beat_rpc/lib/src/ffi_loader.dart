import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'methods.dart';

/// Loads libzero and calls ZeroStart on the current isolate.
///
/// Copy the returned JSON into a Dart string and ZeroFree the pointer before
/// returning. Do not send a Pointer to another isolate. The Flutter app calls
/// [startZeroNative] from a worker isolate via Isolate.run so the UI isolate
/// never enters ZeroStart.
Future<String> startZeroNative(String configJson) async {
  final lib = openLibzero();
  final start = lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>),
        Pointer<Uint8> Function(Pointer<Uint8>)
      >('ZeroStart');
  final zeroFree = lib
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('ZeroFree');
  final malloc = _libc
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('malloc');
  final free = _libc
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final bytes = utf8.encode(configJson);
  final arg = malloc(bytes.length + 1);
  final native = arg.asTypedList(bytes.length + 1);
  native.setAll(0, bytes);
  native[bytes.length] = 0;
  try {
    final result = start(arg);
    try {
      if (result == nullptr) {
        return '{"ok":false,"code":"start_failed","message":"核心没有返回结果"}';
      }
      return _copyCString(result);
    } finally {
      if (result != nullptr) zeroFree(result);
    }
  } finally {
    free(arg.cast());
  }
}

DynamicLibrary openLibzero() {
  final candidates = <String>[];
  final executable = File(Platform.resolvedExecutable);
  if (Platform.isLinux) {
    candidates.add('${executable.parent.path}/lib/libzero.so');
    candidates.add('${executable.parent.path}/libzero.so');
  }
  if (Platform.isMacOS) {
    candidates.add('${executable.parent.parent.path}/Frameworks/libzero.dylib');
    candidates.add('${executable.parent.path}/libzero.dylib');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    candidates.add('libzero.so');
  }
  if (Platform.isMacOS) candidates.add('libzero.dylib');
  for (final path in candidates) {
    try {
      if (path.contains('/') && !File(path).existsSync()) continue;
      return DynamicLibrary.open(path);
    } catch (_) {}
  }
  return DynamicLibrary.process();
}

DynamicLibrary get _libc {
  if (Platform.isAndroid) return DynamicLibrary.open('libc.so');
  if (Platform.isMacOS) return DynamicLibrary.process();
  return DynamicLibrary.process();
}

String _copyCString(Pointer<Uint8> ptr) {
  final units = <int>[];
  var i = 0;
  while (true) {
    final byte = (ptr + i).value;
    if (byte == 0) break;
    units.add(byte);
    i++;
    if (i > rpcMaxFrameBytes) break;
  }
  return utf8.decode(units);
}

/// Stops the native runtime owned by this process. Call off the UI isolate.
Future<void> stopZeroNative() async {
  openLibzero().lookupFunction<Void Function(), void Function()>('ZeroStop')();
}
