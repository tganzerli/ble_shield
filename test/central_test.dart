import 'dart:async';

import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';

void main() {
  late FakeBlePlatform fake;

  setUp(() => fake = FakeBlePlatform());

  group('adapter state', () {
    test('every new subscriber receives the current state first', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      final first = <AdapterState>[];
      shield.adapterState.listen(first.add);
      await settle();
      expect(shield.adapterStateNow, AdapterState.on);

      final late = <AdapterState>[];
      shield.adapterState.listen(late.add);
      await settle();

      // No transient `unknown` before the platform's first answer.
      expect(first, [AdapterState.on]);
      expect(late, [AdapterState.on]);
    });

    test('then only changes, deduplicated', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      shield.adapterStateNow;
      await settle();
      final seen = <AdapterState>[];
      shield.adapterState.listen(seen.add);
      await settle();
      fake.setAvailability(AvailabilityState.poweredOn);
      fake.setAvailability(AvailabilityState.poweredOff);
      fake.setAvailability(AvailabilityState.poweredOff);
      await settle();
      expect(seen, [AdapterState.on, AdapterState.off]);
      expect(shield.adapterStateNow, AdapterState.off);
    });

    test('resetting, unauthorized and unsupported are mapped', () async {
      final shield = BleShield(platform: fake, targetPlatform: iOS);
      shield.adapterStateNow;
      await settle();
      final seen = <AdapterState>[];
      shield.adapterState.listen(seen.add);
      await settle();
      fake.setAvailability(AvailabilityState.resetting);
      fake.setAvailability(AvailabilityState.unauthorized);
      fake.setAvailability(AvailabilityState.unsupported);
      await settle();
      expect(seen, [
        AdapterState.on,
        AdapterState.resetting,
        AdapterState.unauthorized,
        AdapterState.unsupported,
      ]);
    });

    test('adapterStateNow is unknown before the platform answers', () {
      final shield = BleShield(platform: fake, targetPlatform: android);
      expect(shield.adapterStateNow, AdapterState.unknown);
    });
  });

  group('adapter state first event', () {
    test('holds the first event until the platform answers', () async {
      final gate = Completer<void>();
      fake.availabilityGate = gate.future;
      final shield = BleShield(platform: fake, targetPlatform: iOS);
      final seen = <AdapterState>[];
      shield.adapterState.listen(seen.add);
      await settle();
      expect(seen, isEmpty);
      expect(shield.adapterStateNow, AdapterState.unknown);

      gate.complete();
      await settle();
      expect(seen, [AdapterState.on]);
    });

    test('a first answer of unknown is delivered once, without hanging',
        () async {
      fake.availability = AvailabilityState.unknown;
      final shield = BleShield(platform: fake, targetPlatform: android);
      final seen = <AdapterState>[];
      shield.adapterState.listen(seen.add);
      await settle();
      expect(seen, [AdapterState.unknown]);

      final late = <AdapterState>[];
      shield.adapterState.listen(late.add);
      await settle();
      expect(late, [AdapterState.unknown]);
    });

    fakeTest('delivers the cached state after adapterStateTimeout', () async {
      fake.availabilityGate = Completer<void>().future; // never answers
      final shield = BleShield(
        platform: fake,
        targetPlatform: android,
        adapterStateTimeout: const Duration(milliseconds: 50),
      );
      final seen = <AdapterState>[];
      shield.adapterState.listen(seen.add);
      await settle();
      expect(seen, isEmpty);

      await wait(80);
      await settle();
      expect(seen, [AdapterState.unknown]);

      // After the timeout, a new subscriber gets the cached state at once.
      final late = <AdapterState>[];
      shield.adapterState.listen(late.add);
      await settle();
      expect(late, [AdapterState.unknown]);

      // A late answer still arrives as a change.
      fake.setAvailability(AvailabilityState.poweredOn);
      await settle();
      expect(seen, [AdapterState.unknown, AdapterState.on]);
      expect(late, [AdapterState.unknown, AdapterState.on]);
    });

    test('cancelling while waiting delivers nothing and throws nothing',
        () async {
      final gate = Completer<void>();
      fake.availabilityGate = gate.future;
      final shield = BleShield(platform: fake, targetPlatform: android);
      final seen = <AdapterState>[];
      final errors = await zoneErrors(() async {
        final sub = shield.adapterState.listen(seen.add);
        await settle();
        await sub.cancel();
        gate.complete();
        await settle();
      });
      expect(seen, isEmpty);
      expect(errors, isEmpty);
      expect(shield.adapterStateNow, AdapterState.on);
    });

    test('one waiting subscriber cancels, another still receives', () async {
      final gate = Completer<void>();
      fake.availabilityGate = gate.future;
      final shield = BleShield(platform: fake, targetPlatform: android);
      final gone = <AdapterState>[];
      final kept = <AdapterState>[];
      final sub = shield.adapterState.listen(gone.add);
      shield.adapterState.listen(kept.add);
      await settle();
      await sub.cancel();
      gate.complete();
      await settle();
      expect(gone, isEmpty);
      expect(kept, [AdapterState.on]);
    });

    test('a subscriber paused while waiting gets the state on resume',
        () async {
      final gate = Completer<void>();
      fake.availabilityGate = gate.future;
      final shield = BleShield(platform: fake, targetPlatform: android);
      final seen = <AdapterState>[];
      final sub = shield.adapterState.listen(seen.add);
      sub.pause();
      gate.complete();
      await settle();
      expect(seen, isEmpty);
      sub.resume();
      await settle();
      expect(seen, [AdapterState.on]);
      await sub.cancel();
    });

    test('dispose while waiting delivers the cached state and closes',
        () async {
      fake.availabilityGate = Completer<void>().future; // never answers
      final shield = BleShield(platform: fake, targetPlatform: android);
      final seen = <AdapterState>[];
      final done = Completer<void>();
      shield.adapterState.listen(seen.add, onDone: done.complete);
      await settle();
      await shield.dispose();
      await done.future.timeout(const Duration(seconds: 1));
      expect(seen, [AdapterState.unknown]);
    });
  });

  group('isSupported', () {
    test('true when the adapter exists', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      expect(await shield.isSupported(), isTrue);
    });

    test('false when the platform reports unsupported', () async {
      fake.availability = AvailabilityState.unsupported;
      final shield = BleShield(platform: fake, targetPlatform: android);
      expect(await shield.isSupported(), isFalse);
    });
  });

  group('turnOn never hangs', () {
    test('Apple: unsupported, no native call', () async {
      final shield = BleShield(platform: fake, targetPlatform: iOS);
      await expectLater(
          shield.turnOn(), throwsA(shieldError(ShieldErrorCode.unsupported)));
      expect(fake.calls, isNot(contains('enableBluetooth')));
    });

    test('engine without Activity (canTurnOn: false): unsupported', () async {
      final shield =
          BleShield(platform: fake, targetPlatform: android, canTurnOn: false);
      await expectLater(
          shield.turnOn(), throwsA(shieldError(ShieldErrorCode.unsupported)));
      expect(fake.calls, isEmpty);
    });

    test('enableBluetooth that never completes times out', () async {
      fake
        ..availability = AvailabilityState.poweredOff
        ..onEnableBluetooth = null;
      final shield = BleShield(
        platform: fake,
        targetPlatform: android,
        turnOnTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(shield.turnOn(),
          throwsA(shieldError(ShieldErrorCode.operationTimeout)));
    });

    test('declined request is adapterOff', () async {
      fake
        ..availability = AvailabilityState.poweredOff
        ..onEnableBluetooth = () async => false;
      final shield = BleShield(platform: fake, targetPlatform: android);
      await settle();
      await expectLater(
          shield.turnOn(), throwsA(shieldError(ShieldErrorCode.adapterOff)));
    });

    test('accepted request completes', () async {
      fake.availability = AvailabilityState.poweredOff;
      final shield = BleShield(platform: fake, targetPlatform: android);
      await shield.turnOn();
      expect(fake.calls, contains('enableBluetooth'));
    });
  });
}
