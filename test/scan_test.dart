import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';

void main() {
  late FakeBlePlatform fake;

  setUp(() => fake = FakeBlePlatform());

  BleShield build({Duration? watchdog}) => BleShield(
      platform: fake, targetPlatform: android, scanWatchdog: watchdog);

  // Scenario family "a scan failure is absorbed and the scanner resynced"
  // (re-expressed for ble_shield).
  group('scan failure is absorbed and the native scanner left stopped', () {
    test(
        'a start failure never reaches the zone, is reported once on '
        'scanErrors and stops the native scanner', () async {
      fake.startScanError = PlatformException(
          code: '${BleShieldNativeErrorCode.scanFailed.index}',
          message: 'SCAN_FAILED_ALREADY_STARTED');
      final shield = build();
      final scanErrors = <ShieldError>[];
      shield.scanErrors.listen(scanErrors.add);
      ShieldError? thrown;

      final zone = await zoneErrors(() async {
        // A subscriber without onError, like real consumers.
        shield.scanResults.listen((_) {});
        try {
          await shield.startScan();
        } on ShieldError catch (e) {
          thrown = e;
        }
      });

      expect(zone, isEmpty, reason: 'nothing may escape to the zone');
      expect(thrown?.code, ShieldErrorCode.scanFailed);
      expect(scanErrors.map((e) => e.code), [ShieldErrorCode.scanFailed]);
      expect(fake.stopScanCount, 1,
          reason: 'without the native stop the next start repeats the error');
      expect(shield.isScanningNow, isFalse);
    });

    test(
        'a native scanner failure ends the session once, reports scanFailed '
        'with the platform code, stops native, and a restart keeps delivering',
        () async {
      final shield = build();
      final scanErrors = <ShieldError>[];
      final lists = <List<ScanResult>>[];

      final zone = await zoneErrors(() async {
        shield.scanErrors.listen(scanErrors.add);
        shield.scanResults.listen(lists.add);
        await shield.startScan();
        fake.failScan(3); // SCAN_FAILED_INTERNAL_ERROR
        await settle();
        fake.failScan(
            3); // a second report after the end is not a second failure
        await settle();
      });

      expect(zone, isEmpty);
      expect(scanErrors.map((e) => e.code), [ShieldErrorCode.scanFailed]);
      expect(scanErrors.single.nativeCode, 3);
      expect(fake.stopScanCount, 1);
      expect(shield.isScanningNow, isFalse);

      await shield.startScan();
      fake.advertise('AA:00:00:00:00:01', name: 'dev');
      await settle();
      expect(lists.last.single.remoteId, 'aa:00:00:00:00:01',
          reason: 'the same subscription keeps delivering after the failure');
      await shield.stopScan();
    });

    test(
        'a native failure reported while startScan runs still ends the session',
        () async {
      fake.startScanDelay = const Duration(milliseconds: 50);
      final shield = build();
      final scanErrors = <ShieldError>[];
      shield.scanErrors.listen(scanErrors.add);

      final start = shield.startScan();
      await wait(10);
      fake.failScan(2);
      await start;
      await settle();

      expect(scanErrors.map((e) => e.code), [ShieldErrorCode.scanFailed]);
      expect(shield.isScanningNow, isFalse);
      expect(fake.stopScanCount, 1);
    });

    test('without scanWatchdog (the default) a silent scan keeps running',
        () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      expect(shield.scanWatchdog, isNull);
      final scanErrors = <ShieldError>[];
      shield.scanErrors.listen(scanErrors.add);
      await shield.startScan(withServices: const ['180d']);
      await wait(250);
      expect(scanErrors, isEmpty);
      expect(shield.isScanningNow, isTrue);
      expect(fake.stopScanCount, 0);
      await shield.stopScan();
    });

    test(
        'watchdog only warns: one scanFailed per silent window, the session '
        'and the native scan keep running', () async {
      final shield = build(watchdog: const Duration(milliseconds: 100));
      final scanErrors = <ShieldError>[];
      final lists = <List<ScanResult>>[];

      final zone = await zoneErrors(() async {
        shield.scanErrors.listen(scanErrors.add);
        shield.scanResults.listen(lists.add);
        await shield.startScan();
        await wait(350); // three windows
      });

      expect(zone, isEmpty);
      expect(scanErrors.length, 3);
      expect(
          scanErrors.map((e) => e.code).toSet(), {ShieldErrorCode.scanFailed});
      expect(shield.isScanningNow, isTrue);
      expect(fake.stopScanCount, 0);

      // The device was connected (not advertising); once it advertises the
      // same session delivers it.
      fake.advertise('AA:00:00:00:00:01', name: 'dev');
      await settle();
      expect(lists.last.single.remoteId, 'aa:00:00:00:00:01');
      await shield.stopScan();
      final after = scanErrors.length;
      await wait(250);
      expect(scanErrors.length, after, reason: 'stopScan disarms the watchdog');
    });

    test('advertisements keep the watchdog from firing', () async {
      final shield = build(watchdog: const Duration(milliseconds: 100));
      final scanErrors = <ShieldError>[];
      shield.scanErrors.listen(scanErrors.add);
      await shield.startScan();
      for (var i = 0; i < 6; i++) {
        await wait(50);
        fake.advertise('AA:00:00:00:00:01');
      }
      expect(scanErrors, isEmpty);
      expect(shield.isScanningNow, isTrue);
      await shield.stopScan();
    });

    test('stopScan while ble_shield believes it is stopped still stops native',
        () async {
      final shield = build();
      expect(shield.isScanningNow, isFalse);
      await shield.stopScan();
      await shield.stopScan();
      expect(fake.stopScanCount, 2);
    });

    test('adapter turning off mid-scan ends the session and stops native',
        () async {
      final shield = build();
      final scanErrors = <ShieldError>[];
      shield.scanErrors.listen(scanErrors.add);
      await shield.startScan();
      await settle();
      fake.setAvailability(AvailabilityState.poweredOff);
      await settle();
      expect(shield.isScanningNow, isFalse);
      expect(scanErrors.map((e) => e.code), [ShieldErrorCode.adapterOff]);
      expect(fake.stopScanCount, 1);
    });
  });

  group('aggregated results', () {
    test('one entry per device, re-emitted on every advertisement', () async {
      final shield = build();
      final lists = <List<ScanResult>>[];
      shield.scanResults.listen(lists.add);
      await shield.startScan();
      fake.advertise('AA:00:00:00:00:01', rssi: -70);
      fake.advertise('AA:00:00:00:00:02');
      fake.advertise('AA:00:00:00:00:01', rssi: -40);
      await settle();
      // initial [], cleared [] by startScan, then one emission per advert
      expect(lists.where((l) => l.isNotEmpty), hasLength(3));
      final last = lists.last;
      expect(last, hasLength(2));
      expect(last.firstWhere((r) => r.remoteId.endsWith('01')).rssi, -40);
      await shield.stopScan();
    });

    test('maps name, manufacturer data and canonical service UUIDs', () async {
      final shield = build();
      await shield.startScan();
      fake.advertise('AA:00:00:00:00:01', name: 'actlumusp', services: [
        '180d'
      ], manufacturerData: [
        ManufacturerData(0x0059, Uint8List.fromList([1, 2]))
      ]);
      final r =
          (await shield.scanResults.firstWhere((l) => l.isNotEmpty)).single;
      expect(r.name, 'actlumusp');
      expect(r.serviceUuids, ['0000180d-0000-1000-8000-00805f9b34fb']);
      expect(r.manufacturerData, {
        0x0059: [1, 2]
      });
      expect(r.connectable, isTrue);
      await shield.stopScan();
    });

    test('removeIfGone drops devices that stopped advertising', () async {
      final shield = build();
      await shield.startScan(removeIfGone: const Duration(milliseconds: 200));
      fake.advertise('AA:00:00:00:00:01');
      for (var i = 0; i < 8; i++) {
        fake.advertise('AA:00:00:00:00:02');
        await wait(50);
      }
      final now = await shield.scanResults.first;
      expect(now.map((r) => r.remoteId), ['aa:00:00:00:00:02']);
      await shield.stopScan();
    });

    test('advertisements outside a scan session are ignored', () async {
      final shield = build();
      await shield.startScan();
      await shield.stopScan();
      fake.advertise('AA:00:00:00:00:09');
      await settle();
      expect(await shield.scanResults.first, isEmpty);
    });
  });

  group('start/stop', () {
    test('startScan during a scan fails with scanAlreadyStarted', () async {
      final shield = build();
      await shield.startScan();
      await expectLater(shield.startScan(),
          throwsA(shieldError(ShieldErrorCode.scanAlreadyStarted)));
      await shield.stopScan();
    });

    test('isScanning replays and follows the reconciled state', () async {
      final shield = build();
      final seen = <bool>[];
      shield.isScanning.listen(seen.add);
      await shield.startScan();
      await shield.stopScan();
      await settle();
      expect(seen, [false, true, false]);
    });

    test('services are canonicalised into the native filter; mode is mapped',
        () async {
      final shield = build();
      await shield.startScan(withServices: ['180D'], mode: ScanMode.lowLatency);
      expect(fake.lastScanFilter!.withServices,
          ['0000180d-0000-1000-8000-00805f9b34fb']);
      expect(
          fake.lastScanConfig!.android!.scanMode, AndroidScanMode.lowLatency);
      await shield.stopScan();
    });

    test('an invalid service UUID is rejected before any native call',
        () async {
      final shield = build();
      await expectLater(shield.startScan(withServices: ['nope']),
          throwsA(shieldError(ShieldErrorCode.invalidArgument)));
      expect(fake.calls, isEmpty);
    });
  });
}
