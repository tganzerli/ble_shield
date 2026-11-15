/// Types for writing a fake native platform in tests, passed to
/// `BleShield(platform: ...)`. Not part of the runtime API: it follows the
/// vendored native layer and may change in any release.
library;

export 'src/native/native.dart'
    hide BleShieldNative, BleShieldNativeDarwinCentral;
export 'src/platform.dart';
