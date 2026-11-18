/// Loopback JSON-RPC client and the libzero loader.
///
/// Import this from the worker isolate. The presentation library stays free of
/// sockets and FFI.
library;

export 'src/client.dart' show RpcClient, NativeCore, openCore;
export 'src/ffi_loader.dart' show openLibzero, startZeroNative, stopZeroNative;
