import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';

void main() {
  late FakeBlePlatform fake;
  const id = 'aa:bb:cc:dd:ee:ff';

  setUp(() => fake = FakeBlePlatform());

  Future<ShieldDevice> connected(BleShield shield) async {
    final device = shield.device(id);
    await device.connect();
    await settle();
    expect(device.isConnected, isTrue);
    return device;
  }

  group('native log level', () {
    test('reaches the platform without starting the engine', () async {
      final shield = BleShield(platform: fake, targetPlatform: iOS);
      await shield.setNativeLogLevel(ShieldLogLevel.debug);
      expect(fake.logLevel, BleLogLevel.debug);
      // No adapter read: on iOS that would create the central.
      expect(fake.calls, ['setLogLevel:debug']);
    });

    test('maps every level and can be turned off again', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      for (final level in ShieldLogLevel.values) {
        await shield.setNativeLogLevel(level);
        expect(fake.logLevel!.name, level.name);
      }
      await shield.setNativeLogLevel(ShieldLogLevel.none);
      expect(fake.logLevel, BleLogLevel.none);
    });
  });

  group('mtu', () {
    test('is null until the platform reports one, then current and changes',
        () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      final device = await connected(shield);
      expect(device.mtuNow, isNull);
      final seen = <int?>[];
      device.mtu.listen(seen.add);
      await settle();

      fake.emitMtu(id, 517);
      fake.emitMtu(id, 517);
      fake.emitMtu(id, 247);
      await settle();
      expect(device.mtuNow, 247);
      expect(seen, [null, 517, 247]);

      final late = <int?>[];
      device.mtu.listen(late.add);
      await settle();
      expect(late, [247]);
    });

    test('an upper-case id from the platform reaches the device', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      final device = await connected(shield);
      fake.emitMtu(id.toUpperCase(), 185);
      await settle();
      expect(device.mtuNow, 185);
    });

    test('kept when reported before the connection reaches Dart', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      final device = shield.device(id);
      fake.emitMtu(id, 517);
      fake.emitConnection(id, true);
      await settle();
      expect(device.mtuNow, 517);
    });

    test('back to null after a disconnection', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      final device = await connected(shield);
      fake.emitMtu(id, 517);
      await settle();
      fake.emitConnection(id, false);
      await settle();
      expect(device.mtuNow, isNull);
    });

    test('an id with no ShieldDevice is dropped', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      await connected(shield);
      fake.emitMtu('11:22:33:44:55:66', 517);
      await settle();
      expect(shield.device('11:22:33:44:55:66').mtuNow, isNull);
    });
  });

  group('connection parameters', () {
    test('converted from BLE units', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      final device = await connected(shield);
      expect(device.connectionParametersNow, isNull);

      fake.emitConnectionParameters(id,
          interval: 36, latency: 2, supervisionTimeout: 500);
      await settle();
      expect(
        device.connectionParametersNow,
        const ShieldConnectionParameters(
          interval: Duration(microseconds: 45000),
          latency: 2,
          supervisionTimeout: Duration(seconds: 5),
        ),
      );
    });

    test('a failed update is ignored; a repeated one emits once', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      final device = await connected(shield);
      final seen = <ShieldConnectionParameters?>[];
      device.connectionParameters.listen(seen.add);
      await settle();

      fake.emitConnectionParameters(id, interval: 6);
      fake.emitConnectionParameters(id, interval: 6);
      fake.emitConnectionParameters(id, interval: 80, status: 59);
      await settle();
      expect(seen.length, 2);
      expect(seen.last!.interval, const Duration(microseconds: 7500));
    });

    test('back to null after a disconnection', () async {
      final shield = BleShield(platform: fake, targetPlatform: android);
      final device = await connected(shield);
      fake.emitConnectionParameters(id, interval: 6);
      await settle();
      fake.emitConnection(id, false);
      await settle();
      expect(device.connectionParametersNow, isNull);
    });
  });

  test('dispose closes the diagnostic streams', () async {
    final shield = BleShield(platform: fake, targetPlatform: android);
    final device = await connected(shield);
    var mtuDone = false;
    var paramsDone = false;
    device.mtu.listen(null, onDone: () => mtuDone = true);
    device.connectionParameters.listen(null, onDone: () => paramsDone = true);
    await settle();
    await device.dispose();
    await settle();
    expect(mtuDone, isTrue);
    expect(paramsDone, isTrue);
    // A late report after dispose is harmless.
    fake.emitMtu(id, 247);
    await settle();
  });
}
