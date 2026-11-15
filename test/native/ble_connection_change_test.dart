import 'package:flutter_test/flutter_test.dart';
import 'package:ble_shield/src/native/native.dart';

import 'ble_shield_native_test_mock.dart';

class _MockPlatform extends BleShieldNativePlatformMock {}

void main() {
  const deviceId = 'AA:BB:CC:DD:EE:FF';

  test('connectionChangeStream carries message, unified code and native code',
      () async {
    final platform = _MockPlatform();
    final event = platform.connectionChangeStream(deviceId).first;
    platform.updateConnection(deviceId, false, 'Connection Timeout',
        BleShieldNativeErrorCode.connectionTimeout, 8);
    final update = await event;
    expect(update.deviceId, deviceId.toLowerCase());
    expect(update.isConnected, isFalse);
    expect(update.error, 'Connection Timeout');
    expect(update.errorCode, BleShieldNativeErrorCode.connectionTimeout);
    expect(update.nativeErrorCode, 8);
  });

  test('connectionChangeStream has null error fields for app-requested changes',
      () async {
    final platform = _MockPlatform();
    final event = platform.connectionChangeStream(deviceId).first;
    platform.updateConnection(deviceId, false);
    final update = await event;
    expect(update.error, isNull);
    expect(update.errorCode, isNull);
    expect(update.nativeErrorCode, isNull);
  });

  test('connectionStream still emits only the bool', () async {
    final platform = _MockPlatform();
    final events = platform.connectionStream(deviceId).take(2).toList();
    platform.updateConnection(deviceId, true);
    platform.updateConnection(
        deviceId,
        false,
        'The connection has timed out unexpectedly.',
        BleShieldNativeErrorCode.connectionTimeout,
        6);
    expect(await events, [true, false]);
  });

  test('onConnectionChange receives the same change as the stream', () async {
    final platform = _MockPlatform();
    final received = <BleConnectionChange>[];
    platform.onConnectionChange = received.add;
    platform.updateConnection(deviceId, false, 'Unknown Error 257',
        BleShieldNativeErrorCode.deviceDisconnected, 257);
    expect(received.single.deviceId, deviceId.toLowerCase());
    expect(received.single.isConnected, isFalse);
    expect(received.single.error, 'Unknown Error 257');
    expect(
        received.single.errorCode, BleShieldNativeErrorCode.deviceDisconnected);
    expect(received.single.nativeErrorCode, 257);
  });

  test(
      'connectionChangeStream matches a device id reported in a different case',
      () async {
    final platform = _MockPlatform();
    final event = platform.connectionChangeStream(deviceId).first;
    platform.updateConnection(deviceId.toLowerCase(), false, 'x',
        BleShieldNativeErrorCode.connectionTimeout, 147);
    expect((await event).nativeErrorCode, 147);
  });
}
