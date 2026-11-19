// Conformance with the behavioural contract ble_shield was written against: a
// BLE "port" (central, device, service, characteristic, types) consumed
// through a thin glue. The port is described here in text; it is not
// imported. Each test names the port member, the shape the glue needs, and
// checks the matching ble_shield member.
import 'dart:async';

import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';

const id = 'aa:00:00:00:00:01';
const svc = '0000fff0-0000-1000-8000-00805f9b34fb';
const chr = '0000fff1-0000-1000-8000-00805f9b34fb';
const short = Duration(milliseconds: 150);

void main() {
  late FakeBlePlatform fake;
  late BleShield shield;

  // Built per test; a fakeTest builds its own, because the GATT lock's
  // completed future must belong to the fake-time zone.
  BleShield newShield() => BleShield(platform: fake, targetPlatform: android);

  setUp(() {
    fake = FakeBlePlatform()
      ..services[id] = [
        service('FFF0', [
          characteristic('FFF1', [
            CharacteristicProperty.read,
            CharacteristicProperty.write,
            CharacteristicProperty.indicate,
          ]),
        ]),
      ];
    shield = newShield();
  });

  Future<ShieldCharacteristic> characteristicOf() async {
    final d = shield.device(id);
    if (!d.isConnected) await d.connect();
    return (await d.discoverServices()).single.characteristics.single;
  }

  group('central', () {
    test('isSupported: Future<bool>, false only when BLE is unsupported',
        () async {
      final Future<bool> f = shield.isSupported();
      expect(await f, isTrue);
    });

    test('adapterStateNow: synchronous current adapter state', () async {
      final AdapterState now = shield.adapterStateNow;
      expect(now, AdapterState.unknown);
      await settle();
      expect(shield.adapterStateNow, AdapterState.on);
    });

    test('adapterState: delivers the current state to every new subscriber',
        () async {
      shield.adapterStateNow;
      await settle();
      expect(await shield.adapterState.first, AdapterState.on);
      expect(await shield.adapterState.first, AdapterState.on);
    });

    fakeTest(
        'turnOn: unsupported where it cannot work (Apple, no Activity), '
        'never hangs', () async {
      shield = newShield();
      final apple = BleShield(platform: fake, targetPlatform: iOS);
      await expectLater(apple.turnOn().timeout(const Duration(seconds: 1)),
          throwsA(shieldError(ShieldErrorCode.unsupported)));
      final background =
          BleShield(platform: fake, targetPlatform: android, canTurnOn: false);
      await expectLater(background.turnOn(),
          throwsA(shieldError(ShieldErrorCode.unsupported)));
    });

    test('isScanningNow: state kept by the package, reconciled with native',
        () async {
      final bool before = shield.isScanningNow;
      await shield.startScan();
      expect([before, shield.isScanningNow], [false, true]);
      await shield.stopScan();
      expect(shield.isScanningNow, isFalse);
    });

    test('isScanning: delivers the current value to every new subscriber',
        () async {
      await shield.startScan();
      expect(await shield.isScanning.first, isTrue);
      await shield.stopScan();
      expect(await shield.isScanning.first, isFalse);
    });

    test('scanResults: aggregated list, one item per remoteId, per advert',
        () async {
      final lists = <List<ScanResult>>[];
      shield.scanResults.listen(lists.add);
      await shield.startScan();
      fake.advertise(id);
      fake.advertise(id);
      await settle();
      expect(lists.where((l) => l.isNotEmpty).length, 2);
      expect(lists.last.single.remoteId, id);
      await shield.stopScan();
    });

    fakeTest(
        'scanErrors: start failures, native failures and watchdog warnings, '
        'never results', () async {
      shield = newShield();
      final s = BleShield(
          platform: fake, targetPlatform: android, scanWatchdog: short);
      final Stream<ShieldError> errors = s.scanErrors;
      final got = <ShieldError>[];
      errors.listen(got.add);
      await s.startScan();
      await wait(250);
      expect(got, isNotEmpty);
      expect(got.map((e) => e.code).toSet(), {ShieldErrorCode.scanFailed});
      expect(s.isScanningNow, isTrue, reason: 'the watchdog only warns');
      fake.failScan(3);
      await settle();
      expect(s.isScanningNow, isFalse,
          reason: 'a native failure ends the scan');
    });

    fakeTest(
        'startScan({withServices, mode, removeIfGone}): scanAlreadyStarted '
        'when a scan is active', () async {
      shield = newShield();
      await shield.startScan(
          withServices: const [svc],
          mode: ScanMode.balanced,
          removeIfGone: const Duration(seconds: 5));
      await expectLater(shield.startScan(),
          throwsA(shieldError(ShieldErrorCode.scanAlreadyStarted)));
      await shield.stopScan();
    });

    test('stopScan: idempotent and always effective on the native scanner',
        () async {
      await shield.stopScan();
      await shield.stopScan();
      expect(fake.stopScanCount, 2);
    });

    test(
        'systemDevices({required withServices}): devices the system reports '
        'connected, usable as connected, not filtered by owner', () async {
      fake.systemDevices = [BleDevice(deviceId: id, name: null)];
      final List<ShieldDevice> found =
          await shield.systemDevices(withServices: const [svc]);
      expect(found.single.isConnected, isTrue);
    });

    test('device(remoteId): same instance for the same id until dispose',
        () async {
      final d = shield.device(id);
      expect(identical(d, shield.device(id.toUpperCase())), isTrue);
      await d.dispose();
      expect(identical(d, shield.device(id)), isFalse);
    });
  });

  group('device', () {
    test('remoteId: MAC on Android, CoreBluetooth UUID on Apple (lower case)',
        () {
      final String remoteId = shield.device('AA:00:00:00:00:01').remoteId;
      expect(remoteId, id);
    });

    test('isConnected: synchronous and coherent with connectionState',
        () async {
      final d = shield.device(id);
      await d.connect();
      expect(d.isConnected, isTrue);
      expect(await d.connectionState.first, ConnectionState.connected);
    });

    test('connectionState: current state on subscribe, then only changes',
        () async {
      final d = shield.device(id);
      final seen = <ConnectionState>[];
      d.connectionState.listen(seen.add);
      await d.connect();
      await d.connect();
      await settle();
      expect(seen, [ConnectionState.disconnected, ConnectionState.connected]);
    });

    test(
        'connect({timeout = 35 s}): completes connected or throws; timeout, '
        'release on failure, connectInProgress', () async {
      fake.onConnect = (deviceId, _) async {
        fake.states[deviceId] = BleConnectionState.connecting;
      };
      final d = shield.device(id);
      final first = d.connect(timeout: short);
      await expectLater(
          d.connect(), throwsA(shieldError(ShieldErrorCode.connectInProgress)));
      await expectLater(
          first, throwsA(shieldError(ShieldErrorCode.connectTimeout)));
      expect(fake.calls, contains('disconnect:$id'));
    });

    fakeTest(
        'disconnect({timeout = 35 s}): cancels the armed reconnection first; '
        'with autoReconnect still on, the drop it causes re-arms', () async {
      shield = newShield();
      final d = shield.device(id);
      final events = <ReconnectEvent>[];
      d.reconnectEvents.listen(events.add);
      await d.connect();
      d.setAutoReconnect(true, delay: short);
      await d.disconnect();
      await wait(250);
      expect(events.map((e) => e.toString()),
          ['[Reconnect] $id fired origin=drop']);
      expect(d.isConnected, isTrue);
      d.setAutoReconnect(false);
      await d.disconnect();
      await wait(250);
      expect(d.isConnected, isFalse, reason: 'off first = disconnect for good');
    });

    test('autoReconnect: reflects setAutoReconnect', () {
      final d = shield.device(id);
      final bool before = d.autoReconnect;
      d.setAutoReconnect(true);
      expect([before, d.autoReconnect], [false, true]);
      d.setAutoReconnect(false);
    });

    fakeTest(
        'setAutoReconnect(enabled, {delay = 3 s}): arms from the initial '
        'disconnected state (kick) and after every drop', () async {
      shield = newShield();
      final d = shield.device(id);
      d.setAutoReconnect(true, delay: short);
      await wait(250);
      expect(d.isConnected, isTrue);
      fake.emitConnection(id, false);
      await wait(250);
      expect(d.isConnected, isTrue);
      expect(fake.connects.length, 2);
      d.setAutoReconnect(false);
    });

    fakeTest(
        'reconnectEvents: fired | skipped (disposed, disabled, superseded, '
        'adapter-off) | failed (error text)', () async {
      shield = newShield();
      final d = shield.device(id);
      final events = <ReconnectEvent>[];
      d.reconnectEvents.listen(events.add);
      d.setAutoReconnect(true, delay: short);
      d.setAutoReconnect(false);
      fake.connectError = PlatformException(code: '0', message: 'boom');
      d.setAutoReconnect(true, delay: short);
      await wait(200);
      d.setAutoReconnect(false);
      expect(events.map((e) => e.outcome.name).toList(),
          containsAllInOrder(['skipped', 'fired', 'failed']));
      expect(events.first.reason, 'disabled');
      expect(events.last.reason, isNotEmpty);
    });

    test(
        'discoverServices: real discovery on the first call of each '
        'connection; cached until disconnection', () async {
      final d = shield.device(id);
      await d.connect();
      final List<ShieldService> s1 = await d.discoverServices();
      await d.discoverServices();
      fake.emitConnection(id, false);
      await d.connect();
      await d.discoverServices();
      expect(s1.single.uuid, svc);
      expect(fake.calls.where((c) => c.startsWith('discover:')).length, 2);
    });

    test('dispose: Future<void>; skips the armed attempt as "disposed"',
        () async {
      final d = shield.device(id);
      final events = <ReconnectEvent>[];
      d.reconnectEvents.listen(events.add);
      d.setAutoReconnect(true, delay: short);
      final Future<void> f = d.dispose();
      await f;
      expect(events.single.reason, 'disposed');
    });
  });

  group('service', () {
    test('uuid: canonical; characteristics: list', () async {
      final d = shield.device(id);
      await d.connect();
      final s = (await d.discoverServices()).single;
      final String uuid = s.uuid;
      final List<ShieldCharacteristic> chars = s.characteristics;
      expect(uuid, svc);
      expect(chars.single.uuid, chr);
    });
  });

  group('characteristic', () {
    test('uuid and serviceUuid: canonical 128-bit lower case', () async {
      final c = await characteristicOf();
      expect([c.uuid, c.serviceUuid], [chr, svc]);
    });

    test('canRead / canWrite from properties', () async {
      final c = await characteristicOf();
      expect([c.canRead, c.canWrite], [true, true]);
    });

    test('canNotify: notify OR indicate', () async {
      final c = await characteristicOf();
      expect(c.canNotify, isTrue, reason: 'indicate-only counts');
    });

    test('isNotifying: after setNotify(true), reset by disconnection',
        () async {
      final c = await characteristicOf();
      await c.setNotify(true);
      expect(c.isNotifying, isTrue);
      fake.emitConnection(id, false);
      expect(c.isNotifying, isFalse);
    });

    test('read: Future<List<int>>', () async {
      fake.readValues[chr] = Uint8List.fromList([7]);
      final List<int> v = await (await characteristicOf()).read();
      expect(v, [7]);
    });

    test('write(value, {withoutResponse = false}): with response by default',
        () async {
      await (await characteristicOf()).write([1]);
      expect(fake.writes.single.$4, BleOutputProperty.withResponse);
    });

    fakeTest(
        'setNotify(enabled, {timeout = 15 s}): mode chosen from properties; '
        'times out', () async {
      shield = newShield();
      final c = await characteristicOf();
      await c.setNotify(true);
      expect(fake.notifyCalls.single.$3, BleInputProperty.indication);
      fake.gattDelay = const Duration(milliseconds: 200);
      await expectLater(
          c.setNotify(false, timeout: const Duration(milliseconds: 20)),
          throwsA(shieldError(ShieldErrorCode.operationTimeout)));
    });

    test('onValueReceived: only values of this characteristic', () async {
      final c = await characteristicOf();
      final got = <List<int>>[];
      c.onValueReceived.listen(got.add);
      await settle();
      fake.emitValue(id, chr, [1]);
      fake.emitValue(id, '0000fff9-0000-1000-8000-00805f9b34fb', [2]);
      await settle();
      expect(got, [
        [1]
      ]);
    });
  });

  group('types and global rules', () {
    test(
        'adapter states: unknown, unsupported, unauthorized, off, on (+ '
        'resetting, which the glue maps)', () {
      expect(AdapterState.values.map((e) => e.name).toSet(),
          containsAll(['unknown', 'unsupported', 'unauthorized', 'off', 'on']));
    });

    test(
        'scan modes lowPower, balanced, lowLatency; connection states '
        'disconnected, connected', () {
      expect(ScanMode.values.map((e) => e.name),
          ['lowPower', 'balanced', 'lowLatency']);
      expect(ConnectionState.values.map((e) => e.name),
          ['disconnected', 'connected']);
    });

    test(
        'scan result: remoteId, name, rssi, connectable, companyId → payload '
        'map, canonical service UUIDs', () async {
      await shield.startScan();
      fake.advertise(id, name: 'n', services: [
        'FFF0'
      ], manufacturerData: [
        ManufacturerData(1, Uint8List.fromList([2]))
      ]);
      final r =
          (await shield.scanResults.firstWhere((l) => l.isNotEmpty)).single;
      final Map<int, List<int>> m = r.manufacturerData;
      expect([r.remoteId, r.name, r.rssi, r.connectable], [id, 'n', -60, true]);
      expect(m, {
        1: [2]
      });
      expect(r.serviceUuids, [svc]);
      await shield.stopScan();
    });

    test(
        'errors: one type with code, message, platform, nativeCode; the 13 '
        'port codes exist', () {
      const e = ShieldError(ShieldErrorCode.gattFailed, 'm',
          platform: 'android', nativeCode: 133);
      expect([e.code, e.message, e.platform, e.nativeCode],
          [ShieldErrorCode.gattFailed, 'm', 'android', 133]);
      expect(
          ShieldErrorCode.values.map((c) => c.name),
          containsAll([
            'adapterOff', 'notConnected', 'deviceNotFound', //
            'connectInProgress', 'connectTimeout', 'connectFailed',
            'scanAlreadyStarted', 'scanFailed', 'characteristicNotFound',
            'operationTimeout', 'gattFailed', 'unsupported', 'unknown',
          ]));
    });

    fakeTest('no error escapes to the zone during a full session', () async {
      shield = newShield();
      final zone = await zoneErrors(() async {
        final d = shield.device(id);
        d.setAutoReconnect(true, delay: short);
        fake.connectError = PlatformException(code: '0');
        await wait(200);
        fake.connectError = null;
        await shield.startScan();
        fake.setAvailability(AvailabilityState.poweredOff);
        await settle();
        await d.dispose();
      });
      expect(zone, isEmpty);
    });
  });
}
