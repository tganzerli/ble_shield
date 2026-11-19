import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/src/errors.dart'
    show ShieldOperation, mapShieldError;
import 'package:ble_shield/src/native/ble_shield_native_pigeon/ble_shield_native_pigeon_channel.dart';
import 'package:ble_shield/src/native/native.dart'
    show BleShieldNative, BleShieldNativeErrorCode;
import 'package:ble_shield/src/web/ble_shield_native_web.dart';
import 'package:ble_shield/src/web/web_bluetooth_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';
import 'web/fake_web_bluetooth_backend.dart';

const _svc = '0000180d-0000-1000-8000-00805f9b34fb';
const _chr = '00002a37-0000-1000-8000-00805f9b34fb';

/// A Chrome-style opaque id: case matters.
const _id = 'aB3+xY9/Qw==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('on the web', () {
    late FakeWebBluetoothBackend backend;
    late FakeWebCharacteristic chr;
    late FakeWebDevice picked;
    late BleShieldNativeWeb web;
    late BleShield shield;

    setUp(() {
      backend = FakeWebBluetoothBackend();
      chr = FakeWebCharacteristic(_chr)..value = Uint8List.fromList([42]);
      picked = FakeWebDevice(_id, name: 'HRM', services: [
        FakeWebService(_svc, [chr]),
      ]);
      web = BleShieldNativeWeb(backend);
      shield = BleShield(platform: web);
    });

    tearDown(() async {
      await shield.dispose();
      await web.dispose();
    });

    test('returns the picked device, connectable by its verbatim id', () async {
      backend.nextPick = picked;
      final result = await shield.requestDevice(
        withServices: ['180d'],
        optionalServices: ['180f'],
        optionalManufacturerData: [76],
      );
      expect(result.remoteId, _id);
      expect(result.name, 'HRM');
      expect(result.rssi, -127);

      final options = backend.requests.single;
      expect(options.filters.single.services, [_svc]);
      expect(
          options.optionalServices, ['0000180f-0000-1000-8000-00805f9b34fb']);
      expect(options.optionalManufacturerData, [76]);

      final device = shield.device(result.remoteId);
      expect(device.remoteId, _id);
      await device.connect();
      expect(device.isConnected, isTrue);
      final services = await device.discoverServices();
      expect(await services.single.characteristics.single.read(), [42]);
    });

    test('does not touch the scan session', () async {
      backend.nextPick = picked;
      await shield.requestDevice();
      expect(shield.isScanningNow, isFalse);
      expect(await shield.scanResults.first, isEmpty);
    });

    test('a dismissed chooser throws cancelled', () async {
      backend.nextPick = const WebBluetoothError(
          'NotFoundError', 'User cancelled the requestDevice() chooser.');
      await expectLater(shield.requestDevice(),
          throwsA(shieldError(ShieldErrorCode.cancelled)));
    });

    test('no user gesture throws unauthorized', () async {
      backend.nextPick = const WebBluetoothError('SecurityError',
          'Must be handling a user gesture to show a permission request.');
      await expectLater(shield.requestDevice(),
          throwsA(shieldError(ShieldErrorCode.unauthorized)));
    });

    test('no device found throws deviceNotFound', () async {
      backend.nextPick =
          const WebBluetoothError('NotFoundError', 'No devices found.');
      await expectLater(shield.requestDevice(),
          throwsA(shieldError(ShieldErrorCode.deviceNotFound)));
    });

    test('a browser without Web Bluetooth throws unsupported', () async {
      backend.isSupported = false;
      await expectLater(shield.requestDevice(),
          throwsA(shieldError(ShieldErrorCode.unsupported)));
    });

    test('startScan throws unsupported and opens no chooser', () async {
      await expectLater(shield.startScan(),
          throwsA(shieldError(ShieldErrorCode.unsupported)));
      expect(backend.requests, isEmpty);
      expect(shield.isScanningNow, isFalse);
    });

    test('a browser drop reaches the device', () async {
      backend.nextPick = picked;
      final device = shield.device((await shield.requestDevice()).remoteId);
      await device.connect();
      picked.drop();
      await settle();
      expect(device.isConnected, isFalse);
    });
  });

  group('off the web', () {
    test('a platform without a picker throws unsupported', () async {
      final platform = FakeBlePlatform();
      final shield = BleShield(platform: platform);
      await expectLater(shield.requestDevice(),
          throwsA(shieldError(ShieldErrorCode.unsupported)));
      await shield.dispose();
    });

    test('the Android/Darwin channel throws unsupported without a call',
        () async {
      final messages = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        'dev.flutter.pigeon.ble_shield.BleShieldNativePlatformChannel.requestDevice',
        (message) async {
          messages.add('requestDevice');
          return null;
        },
      );
      BleShieldNative.setInstance(BleShieldNativePigeonChannel.instance);
      final shield = BleShield();
      await expectLater(shield.requestDevice(),
          throwsA(shieldError(ShieldErrorCode.unsupported)));
      expect(messages, isEmpty);
      await shield.dispose();
    });
  });

  test('a picker cancellation off the picker keeps its old code', () {
    final error = mapShieldError(
      PlatformException(
          code: '${BleShieldNativeErrorCode.operationCancelled.index}'),
      op: ShieldOperation.read,
    );
    expect(error.code, ShieldErrorCode.gattFailed);
  });
}
