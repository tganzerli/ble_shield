import 'package:flutter_test/flutter_test.dart';
import 'package:ble_shield/src/native/native.dart';

import 'ble_shield_native_test_mock.dart';

class _DevicePickerPlatform extends BleShieldNativePlatformMock {
  PickerPlatformConfig? receivedConfig;
  ScanFilter? receivedFilter;

  @override
  Future<BleDevice> requestDevice({
    ScanFilter? scanFilter,
    PickerPlatformConfig? platformConfig,
  }) async {
    receivedFilter = scanFilter;
    receivedConfig = platformConfig;
    return BleDevice(deviceId: 'picked-device', name: 'Picked device');
  }
}

void main() {
  test('requestDevice returns the device selected by the native picker',
      () async {
    final platform = _DevicePickerPlatform();
    final options = AppleAccessorySetupOptions(
      items: [
        AppleAccessoryPickerItem(
          displayName: 'My device',
          imageAsset: 'my_device',
          serviceUuid: '180D',
        ),
      ],
    );
    BleShieldNative.setInstance(platform);

    final device = await BleShieldNative.requestDevice(
      scanFilter: ScanFilter(withServices: ['180D']),
      platformConfig: PickerPlatformConfig(apple: options),
    );

    expect(device.deviceId, 'picked-device');
    expect(device.name, 'Picked device');
    expect(platform.receivedConfig?.apple, same(options));
    expect(platform.receivedFilter?.withServices, ['180D']);
  });

  test('requestDevice without platformConfig forwards null', () async {
    final platform = _DevicePickerPlatform();
    BleShieldNative.setInstance(platform);

    await BleShieldNative.requestDevice();

    expect(platform.receivedConfig, isNull);
    expect(platform.receivedFilter, isNull);
  });
}
