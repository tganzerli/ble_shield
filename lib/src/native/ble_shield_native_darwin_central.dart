import 'package:flutter/foundation.dart';
import 'package:ble_shield/src/native/ble_shield_native.g.dart';

/// Apple-only control of the central's CoreBluetooth state restoration.
///
/// ble_shield: restoration is opt-in only. No manager is created at plugin
/// registration and there is no default identifier; the engine that should own
/// restoration calls [configureRestoration] with an identifier of its own. Every
/// other engine gets a central without restoration.
class BleShieldNativeDarwinCentral {
  BleShieldNativeDarwinCentral._();

  /// Opts this engine's central into state restoration with
  /// [restorationIdentifier].
  ///
  /// Call it after installing connection listeners and before any other
  /// central API on this engine: the manager is created here. Returns `false`
  /// when restoration was not granted (another live engine owns the
  /// identifier, the manager already exists with a different setting, the app
  /// lacks the `bluetooth-central` background mode) and on every platform
  /// other than iOS.
  static Future<bool> configureRestoration(String restorationIdentifier) async {
    if (restorationIdentifier.trim().isEmpty) {
      throw ArgumentError.value(restorationIdentifier, 'restorationIdentifier');
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    return BleShieldNativeDarwinCentralChannel()
        .configureRestoration(restorationIdentifier);
  }
}
