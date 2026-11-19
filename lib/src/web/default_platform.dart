import 'package:ble_shield/src/native/ble_shield_native_pigeon/ble_shield_native_pigeon_channel.dart';
import 'package:ble_shield/src/native/interfaces/ble_shield_native_platform_interface.dart';

/// The platform the native layer starts with off the web: the Pigeon channel
/// to the Android/Darwin plugin. The web build swaps this file for
/// `default_platform_web.dart` through a conditional import.
BleShieldNativePlatform defaultNativePlatform() =>
    BleShieldNativePigeonChannel.instance;
