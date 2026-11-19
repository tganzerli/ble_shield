import 'dart:async';
import 'dart:typed_data';

import 'package:ble_shield/src/native/native.dart';
import 'package:ble_shield/src/web/ble_shield_native_web.dart';
import 'package:ble_shield/src/web/web_bluetooth_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_web_bluetooth_backend.dart';

const _svc = '0000180d-0000-1000-8000-00805f9b34fb';
const _chr = '00002a37-0000-1000-8000-00805f9b34fb';
const _dsc = '00002902-0000-1000-8000-00805f9b34fb';

/// A Chrome-style opaque id: case matters.
const _id = 'aB3+xY9/Qw==';

Matcher _code(BleShieldNativeErrorCode code) =>
    isA<BleShieldNativeException>().having((e) => e.code, 'code', code);

void main() {
  late FakeWebBluetoothBackend backend;
  late BleShieldNativeWeb web;
  late FakeWebCharacteristic chr;
  late FakeWebDevice device;

  setUp(() {
    backend = FakeWebBluetoothBackend();
    web = BleShieldNativeWeb(backend);
    chr = FakeWebCharacteristic(_chr, descriptors: [FakeWebDescriptor(_dsc)]);
    device = FakeWebDevice(_id, name: 'HRM', services: [
      FakeWebService(_svc, [chr]),
    ]);
  });

  tearDown(() => web.dispose());

  Future<void> pick() async {
    backend.nextPick = device;
    await web.requestDevice();
  }

  group('availability', () {
    test('no navigator.bluetooth: unsupported', () async {
      final w = BleShieldNativeWeb(FakeWebBluetoothBackend(isSupported: false));
      expect(await w.getBluetoothAvailabilityState(),
          AvailabilityState.unsupported);
    });

    test('getAvailability maps to poweredOn / poweredOff', () async {
      expect(await web.getBluetoothAvailabilityState(),
          AvailabilityState.poweredOn);
      backend.available = false;
      expect(await web.getBluetoothAvailabilityState(),
          AvailabilityState.poweredOff);
    });

    test('availabilitychanged reaches the availability stream', () async {
      final states = <AvailabilityState>[];
      final sub = web.availabilityStream.listen(states.add);
      await pumpEventQueue();
      backend.availability.add(false);
      await pumpEventQueue();
      expect(states.last, AvailabilityState.poweredOff);
      await sub.cancel();
    });
  });

  group('requestDevice', () {
    test('returns the picked device with its id verbatim', () async {
      backend.nextPick = device;
      final d = await web.requestDevice();
      expect(d.deviceId, _id);
      expect(d.name, 'HRM');
      expect(d.rssi, isNull);
    });

    test('without navigator.bluetooth: notSupported', () async {
      backend.isSupported = false;
      await expectLater(web.requestDevice(),
          throwsA(_code(BleShieldNativeErrorCode.notSupported)));
    });

    test('dismissed chooser: operationCancelled', () async {
      backend.nextPick = const WebBluetoothError(
          'NotFoundError', 'User cancelled the requestDevice() chooser.');
      await expectLater(web.requestDevice(),
          throwsA(_code(BleShieldNativeErrorCode.operationCancelled)));
    });

    test('no matching device: deviceNotFound', () async {
      backend.nextPick =
          const WebBluetoothError('NotFoundError', 'No devices found.');
      await expectLater(web.requestDevice(),
          throwsA(_code(BleShieldNativeErrorCode.deviceNotFound)));
    });

    test('no user gesture: bluetoothNotAllowed', () async {
      backend.nextPick = const WebBluetoothError(
          'SecurityError', 'Must be handling a user gesture.');
      await expectLater(web.requestDevice(),
          throwsA(_code(BleShieldNativeErrorCode.bluetoothNotAllowed)));
    });

    test('globally disabled: notSupported', () async {
      backend.nextPick = const WebBluetoothError(
          'NotFoundError', 'Web Bluetooth API globally disabled.');
      await expectLater(web.requestDevice(),
          throwsA(_code(BleShieldNativeErrorCode.notSupported)));
      backend.nextPick = const WebBluetoothError(
          'UnknownError', 'Web Bluetooth API globally disabled.');
      await expectLater(web.requestDevice(),
          throwsA(_code(BleShieldNativeErrorCode.notSupported)));
    });
  });

  group('requestOptionsFor', () {
    test('no filter: accept all devices', () {
      final o = BleShieldNativeWeb.requestOptionsFor(null, null);
      expect(o.acceptAllDevices, isTrue);
      expect(o.optionalServices, isEmpty);
    });

    test('filter services are also optional services', () {
      final o = BleShieldNativeWeb.requestOptionsFor(
          ScanFilter(withServices: ['180d']), null);
      expect(o.acceptAllDevices, isFalse);
      expect(o.filters.single.services, [_svc]);
      expect(o.optionalServices, [_svc]);
    });

    test('WebOptions.optionalServices replace the filter ones', () {
      final o = BleShieldNativeWeb.requestOptionsFor(
        ScanFilter(withServices: ['180d']),
        WebOptions(optionalServices: ['180f']),
      );
      expect(o.optionalServices, ['0000180f-0000-1000-8000-00805f9b34fb']);
    });

    test('manufacturer data and name prefix become filters', () {
      final o = BleShieldNativeWeb.requestOptionsFor(
        ScanFilter(
          withManufacturerData: [ManufacturerDataFilter(companyIdentifier: 76)],
          withNamePrefix: ['HR'],
        ),
        null,
      );
      expect(o.filters, hasLength(2));
      expect(o.filters.first.manufacturerData!.single.companyIdentifier, 76);
      expect(o.filters.last.namePrefix, 'HR');
      expect(o.optionalManufacturerData, [76]);
    });

    test('service data filter is rejected', () {
      expect(
        () => BleShieldNativeWeb.requestOptionsFor(
            ScanFilter(withServiceData: ['180d']), null),
        throwsA(_code(BleShieldNativeErrorCode.illegalArgument)),
      );
    });

    test('exclusions without an inclusion filter are rejected', () {
      expect(
        () => BleShieldNativeWeb.requestOptionsFor(
          ScanFilter(exclusionFilters: [ExclusionFilter(namePrefix: 'X')]),
          null,
        ),
        throwsA(_code(BleShieldNativeErrorCode.illegalArgument)),
      );
    });
  });

  group('scan', () {
    test('startScan is notSupported and never opens the chooser', () async {
      await expectLater(web.startScan(),
          throwsA(_code(BleShieldNativeErrorCode.notSupported)));
      expect(backend.requests, isEmpty);
      expect(await web.isScanning(), isFalse);
      await web.stopScan();
    });
  });

  group('connect', () {
    test('a device the chooser did not return: deviceNotFound', () async {
      await expectLater(web.connect('other'),
          throwsA(_code(BleShieldNativeErrorCode.deviceNotFound)));
    });

    test('ids are case-sensitive', () async {
      await pick();
      await expectLater(web.connect(_id.toLowerCase()),
          throwsA(_code(BleShieldNativeErrorCode.deviceNotFound)));
    });

    test('reports connected, then a drop as disconnected', () async {
      await pick();
      final changes = <BleConnectionChange>[];
      final sub =
          web.bleConnectionChangeStreamController.stream.listen(changes.add);
      await web.connect(_id);
      expect(await web.getConnectionState(_id), BleConnectionState.connected);
      device.drop();
      await pumpEventQueue();
      expect(changes.map((c) => (c.deviceId, c.isConnected)),
          [(_id, true), (_id, false)]);
      await sub.cancel();
    });

    test('a second connect while one is pending: connectionInProgress',
        () async {
      await pick();
      device.connectGate = Completer<void>();
      final first = web.connect(_id);
      await expectLater(web.connect(_id),
          throwsA(_code(BleShieldNativeErrorCode.connectionInProgress)));
      device.connectGate!.complete();
      await first;
    });

    test('timeout: connectionTimeout, and the link is torn down', () async {
      await pick();
      device.connectGate = Completer<void>();
      await expectLater(
        web.connect(_id, connectionTimeout: const Duration(milliseconds: 10)),
        throwsA(_code(BleShieldNativeErrorCode.connectionTimeout)),
      );
      expect(device.disconnectCalls, 1);
    });

    test('NetworkError on connect: connectionFailed', () async {
      await pick();
      device.connectError =
          const WebBluetoothError('NetworkError', 'Connection failed.');
      await expectLater(web.connect(_id),
          throwsA(_code(BleShieldNativeErrorCode.connectionFailed)));
    });

    test('disconnect during connect fails the attempt', () async {
      await pick();
      device.connectGate = Completer<void>();
      final attempt = expectLater(
        web.connect(_id),
        throwsA(_code(BleShieldNativeErrorCode.deviceDisconnected)),
      );
      await pumpEventQueue();
      await web.disconnect(_id);
      await attempt;
      device.connectGate!.complete();
      await pumpEventQueue();
      // The late native success of the cancelled attempt is dropped.
      expect(device.isConnected, isFalse);
    });

    test('a drop after a reconnect is still reported', () async {
      await pick();
      await web.connect(_id);
      await web.disconnect(_id);
      await web.connect(_id);
      final changes = <bool>[];
      final sub = web.bleConnectionChangeStreamController.stream
          .listen((c) => changes.add(c.isConnected));
      device.drop();
      await pumpEventQueue();
      expect(changes, [false]);
      await sub.cancel();
    });
  });

  group('GATT', () {
    setUp(() async {
      await pick();
      await web.connect(_id);
    });

    test('discoverServices maps properties and descriptors, cached', () async {
      final services = await web.discoverServices(_id, true);
      final c = services.single.characteristics.single;
      expect(services.single.uuid, _svc);
      expect(c.uuid, _chr);
      expect(c.properties, [
        CharacteristicProperty.read,
        CharacteristicProperty.write,
        CharacteristicProperty.notify,
      ]);
      expect(c.descriptors.single.uuid, _dsc);
      await web.discoverServices(_id, false);
      expect(device.discoverCalls, 1);
    });

    test('the service cache is dropped on disconnect', () async {
      await web.discoverServices(_id, false);
      await web.disconnect(_id);
      await web.connect(_id);
      await web.discoverServices(_id, false);
      expect(device.discoverCalls, 2);
    });

    test('read and write', () async {
      chr.value = Uint8List.fromList([1, 2]);
      expect(await web.readValue(_id, '180d', '2a37'), [1, 2]);
      await web.writeValue(_id, _svc, _chr, Uint8List.fromList([3]),
          BleOutputProperty.withResponse);
      await web.writeValue(_id, _svc, _chr, Uint8List.fromList([4]),
          BleOutputProperty.withoutResponse);
      expect(chr.writes.map((w) => w.$1.toList()), [
        [3],
        [4],
      ]);
      expect(chr.writes.map((w) => w.$2), [true, false]);
    });

    test('unknown characteristic: characteristicNotFound', () async {
      await expectLater(web.readValue(_id, _svc, '2a38'),
          throwsA(_code(BleShieldNativeErrorCode.characteristicNotFound)));
    });

    test('a GATT failure after a drop: deviceDisconnected', () async {
      chr.nextError = const WebBluetoothError(
          'NetworkError', 'GATT Server is disconnected.');
      await expectLater(web.readValue(_id, _svc, _chr),
          throwsA(_code(BleShieldNativeErrorCode.deviceDisconnected)));
    });

    test('notify delivers values, and disable stops them', () async {
      final values = <List<int>>[];
      final sub = web.characteristicValueStream(_id, _chr).listen(values.add);
      await web.setNotifiable(_id, _svc, _chr, BleInputProperty.notification);
      expect(chr.notifying, isTrue);
      chr.notify([7]);
      await pumpEventQueue();
      await web.setNotifiable(_id, _svc, _chr, BleInputProperty.disabled);
      chr.notify([8]);
      await pumpEventQueue();
      expect(values, [
        [7]
      ]);
      expect(chr.notifying, isFalse);
      await sub.cancel();
    });

    test('a drop cancels this device notifications only', () async {
      final other = FakeWebCharacteristic(_chr);
      final otherDevice = FakeWebDevice('$_id-2', services: [
        FakeWebService(_svc, [other])
      ]);
      backend.nextPick = otherDevice;
      await web.requestDevice();
      await web.connect(otherDevice.id);
      await web.setNotifiable(_id, _svc, _chr, BleInputProperty.notification);
      await web.setNotifiable(
          otherDevice.id, _svc, _chr, BleInputProperty.notification);
      final values = <String>[];
      final sub = web.bleConnectionChangeStreamController.stream.listen((_) {});
      final a = web
          .characteristicValueStream(_id, _chr)
          .listen((_) => values.add('a'));
      final b = web
          .characteristicValueStream(otherDevice.id, _chr)
          .listen((_) => values.add('b'));
      device.drop();
      await pumpEventQueue();
      chr.notify([1]);
      other.notify([1]);
      await pumpEventQueue();
      expect(values, ['b']);
      await Future.wait([a.cancel(), b.cancel(), sub.cancel()]);
    });

    test('a notification stream error stays out of the zone', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        await web.setNotifiable(_id, _svc, _chr, BleInputProperty.notification);
        chr.notifyError(StateError('broken event'));
        await pumpEventQueue();
      }, (e, _) => errors.add(e));
      expect(errors, isEmpty);
    });

    test('descriptor read and write', () async {
      await web.writeDescriptorValue(
          _id, _svc, _chr, _dsc, Uint8List.fromList([1, 0]));
      expect(await web.readDescriptorValue(_id, _svc, _chr, _dsc), [1, 0]);
    });
  });

  group('unsupported on web', () {
    final calls = <String, Future<Object?> Function(BleShieldNativeWeb)>{
      'requestMtu': (w) => w.requestMtu(_id, 247),
      'readRssi': (w) => w.readRssi(_id),
      'requestConnectionPriority': (w) =>
          w.requestConnectionPriority(_id, BleConnectionPriority.balanced),
      'isPaired': (w) => w.isPaired(_id),
      'pair': (w) => w.pair(_id),
      'unpair': (w) => w.unpair(_id),
      'getSystemDevices': (w) => w.getSystemDevices(null),
      'enableBluetooth': (w) => w.enableBluetooth(),
      'disableBluetooth': (w) => w.disableBluetooth(),
    };
    for (final entry in calls.entries) {
      test(entry.key, () async {
        await expectLater(entry.value(web),
            throwsA(_code(BleShieldNativeErrorCode.notSupported)));
      });
    }
  });

  test('device ids are opaque', () {
    expect(web.hasAddressDeviceIds, isFalse);
  });
}
