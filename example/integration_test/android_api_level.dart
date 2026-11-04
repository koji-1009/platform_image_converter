// The device's API level decides which Android expectations apply. The JNI
// bindings need dart:ffi, so Web builds get a stub that is never called there.
export 'android_api_level_stub.dart'
    if (dart.library.ffi) 'android_api_level_native.dart';
