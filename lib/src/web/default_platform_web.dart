import 'package:ble_shield/src/native/interfaces/ble_shield_native_platform_interface.dart';
import 'package:ble_shield/src/web/ble_shield_native_web.dart';
import 'package:ble_shield/src/web/js_web_bluetooth_backend.dart';

/// The platform the native layer starts with on the web: Web Bluetooth.
BleShieldNativePlatform defaultNativePlatform() =>
    BleShieldNativeWeb(JsWebBluetoothBackend());
