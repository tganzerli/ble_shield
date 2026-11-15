import 'native/native.dart';

/// The native platform ble_shield runs on: the Pigeon channel in apps, a fake
/// in tests (see `package:ble_shield/testing.dart`).
typedef BleShieldPlatform = BleShieldNativePlatform;
