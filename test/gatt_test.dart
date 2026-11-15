import 'dart:math';

import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';

const a = 'aa:00:00:00:00:01';
const b = 'aa:00:00:00:00:02';
const svc = '0000fff0-0000-1000-8000-00805f9b34fb';
const notifyChr = '0000fff1-0000-1000-8000-00805f9b34fb';
const indicateChr = '0000fff2-0000-1000-8000-00805f9b34fb';
const plainChr = '0000fff3-0000-1000-8000-00805f9b34fb';

void main() {
  late FakeBlePlatform fake;
  late BleShield shield;

  setUp(() {
    fake = FakeBlePlatform();
    for (final id in [a, b]) {
      fake.services[id] = [
        service('FFF0', [
          characteristic('FFF1', [
            CharacteristicProperty.read,
            CharacteristicProperty.write,
            CharacteristicProperty.notify,
          ]),
          characteristic('FFF2', [CharacteristicProperty.indicate]),
          characteristic('FFF3', [CharacteristicProperty.writeWithoutResponse]),
        ]),
      ];
    }
    shield = BleShield(platform: fake, targetPlatform: android);
  });

  Future<ShieldCharacteristic> chr(String id, String uuid) async {
    final d = shield.device(id);
    if (!d.isConnected) await d.connect();
    final services = await d.discoverServices();
    return services.single.characteristics.firstWhere((c) => c.uuid == uuid);
  }

  int discovers(String id) =>
      fake.calls.where((c) => c == 'discover:$id').length;

  group('discovery', () {
    test('canonical UUIDs and property flags; canNotify = notify OR indicate',
        () async {
      final d = shield.device(a);
      await d.connect();
      final s = (await d.discoverServices()).single;
      expect(s.uuid, svc);
      final byUuid = {for (final c in s.characteristics) c.uuid: c};
      expect(byUuid[notifyChr]!.canRead, isTrue);
      expect(byUuid[notifyChr]!.canNotify, isTrue);
      expect(byUuid[indicateChr]!.canNotify, isTrue);
      expect(byUuid[indicateChr]!.canRead, isFalse);
      expect(byUuid[plainChr]!.canWrite, isTrue);
      expect(byUuid[plainChr]!.canNotify, isFalse);
      expect(byUuid[notifyChr]!.serviceUuid, svc);
    });

    test('cached within one connection; concurrent calls share one discovery',
        () async {
      final d = shield.device(a);
      await d.connect();
      await Future.wait([d.discoverServices(), d.discoverServices()]);
      await d.discoverServices();
      expect(discovers(a), 1);
    });

    test('no cache across connections: every reconnection rediscovers',
        () async {
      final d = shield.device(a);
      await d.connect();
      final first = await d.discoverServices();
      fake.emitConnection(a, false); // drop
      fake.services[a] = [service('FFE0', [])]; // firmware changed meanwhile
      await d.connect();
      final second = await d.discoverServices();
      expect(discovers(a), 2);
      expect(first.single.uuid, svc);
      expect(second.single.uuid, '0000ffe0-0000-1000-8000-00805f9b34fb');
    });

    test('a result that lands after a drop is not cached', () async {
      fake.gattDelay = const Duration(milliseconds: 50);
      final d = shield.device(a);
      await d.connect();
      final pending = d.discoverServices();
      await wait(10);
      fake.emitConnection(a, false);
      await pending;
      await d.connect();
      await d.discoverServices();
      expect(discovers(a), 2);
    });

    test('discoverServices on a disconnected device is notConnected', () {
      expect(shield.device(a).discoverServices(),
          throwsA(shieldError(ShieldErrorCode.notConnected)));
    });
  });

  group('read / write / notify', () {
    test('read returns the value', () async {
      fake.readValues[notifyChr] = Uint8List.fromList([1, 2, 3]);
      expect(await (await chr(a, notifyChr)).read(), [1, 2, 3]);
    });

    test('write is with response by default', () async {
      final c = await chr(a, notifyChr);
      await c.write([9]);
      await c.write([8], withoutResponse: true);
      expect(fake.writes.map((w) => w.$4), [
        BleOutputProperty.withResponse,
        BleOutputProperty.withoutResponse,
      ]);
      expect(fake.writes.first.$3, [9]);
    });

    test('setNotify picks notification or indication from properties',
        () async {
      final n = await chr(a, notifyChr);
      final i = await chr(a, indicateChr);
      await n.setNotify(true);
      await i.setNotify(true);
      expect(fake.notifyCalls.map((c) => c.$3), [
        BleInputProperty.notification,
        BleInputProperty.indication,
      ]);
      expect(n.isNotifying && i.isNotifying, isTrue);
      await n.setNotify(false);
      expect(fake.notifyCalls.last.$3, BleInputProperty.disabled);
      expect(n.isNotifying, isFalse);
    });

    test('setNotify on a characteristic without notify/indicate', () async {
      final p = await chr(a, plainChr);
      await expectLater(
          p.setNotify(true), throwsA(shieldError(ShieldErrorCode.unsupported)));
    });

    test('setNotify times out', () async {
      final n = await chr(a, notifyChr);
      fake.gattDelay = const Duration(milliseconds: 200);
      await expectLater(
          n.setNotify(true, timeout: const Duration(milliseconds: 50)),
          throwsA(shieldError(ShieldErrorCode.operationTimeout)));
    });

    test('isNotifying is reset by a disconnection', () async {
      final n = await chr(a, notifyChr);
      await n.setNotify(true);
      fake.emitConnection(a, false);
      expect(n.isNotifying, isFalse);
    });

    test('onValueReceived only delivers this characteristic of this device',
        () async {
      final n = await chr(a, notifyChr);
      final got = <List<int>>[];
      n.onValueReceived.listen(got.add);
      await settle();
      fake.emitValue(a, notifyChr, [1]);
      fake.emitValue(a, indicateChr, [2]);
      fake.emitValue(b, notifyChr, [3]);
      await settle();
      expect(got, [
        [1]
      ]);
    });

    test('native errors are typed', () async {
      final c = await chr(a, notifyChr);
      fake.gattError = PlatformException(
          code: '${BleShieldNativeErrorCode.writeFailed.index}',
          message: 'busy');
      await expectLater(
          c.write([1]), throwsA(shieldError(ShieldErrorCode.gattFailed)));
    });

    test('operations on a disconnected device are notConnected', () async {
      final c = await chr(a, notifyChr);
      fake.emitConnection(a, false);
      await expectLater(
          c.read(), throwsA(shieldError(ShieldErrorCode.notConnected)));
    });
  });

  test('GATT operations of different devices never overlap', () async {
    final ca = await chr(a, notifyChr);
    final cb = await chr(b, notifyChr);
    var active = 0, maxActive = 0;
    fake
      ..gattDelay = const Duration(milliseconds: 30)
      ..onGattStart = ((_) => maxActive = max(maxActive, ++active))
      ..onGattEnd = ((_) => active--);
    await Future.wait([
      ca.read(),
      cb.write([1]),
      ca.write([2]),
      cb.read(),
      ca.setNotify(true),
    ]);
    expect(maxActive, 1);
  });
}
