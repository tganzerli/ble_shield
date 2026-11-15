import 'dart:math';

import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';

const a = 'aa:00:00:00:00:01';
const b = 'aa:00:00:00:00:02';

void main() {
  late FakeBlePlatform fake;
  late BleShield shield;

  setUp(() {
    fake = FakeBlePlatform();
    shield = BleShield(platform: fake, targetPlatform: android);
  });

  test('device() returns the same instance per id (any case) until dispose',
      () async {
    final d = shield.device('AA:00:00:00:00:01');
    expect(identical(d, shield.device(a)), isTrue);
    expect(d.remoteId, a);
    await d.dispose();
    expect(identical(d, shield.device(a)), isFalse);
    expect(() => d.connect(), throwsA(isA<ShieldError>()));
  });

  test('connect completes connected; state is synchronous and replayed',
      () async {
    final d = shield.device(a);
    final seen = <ConnectionState>[];
    d.connectionState.listen(seen.add);
    await d.connect();
    expect(d.isConnected, isTrue);
    await settle();
    expect(seen, [ConnectionState.disconnected, ConnectionState.connected]);
    final late = await d.connectionState.first;
    expect(late, ConnectionState.connected);
  });

  test('timeout cancels the native attempt with a disconnect', () async {
    fake.onConnect = (id, _) async {
      fake.states[id] = BleConnectionState.connecting;
    };
    final d = shield.device(a);
    await expectLater(d.connect(timeout: const Duration(milliseconds: 80)),
        throwsA(shieldError(ShieldErrorCode.connectTimeout)));
    expect(fake.calls, containsAllInOrder(['connect:$a', 'disconnect:$a']));
    expect(d.isConnected, isFalse);
  });

  test('a failed connect releases the GATT client', () async {
    fake.connectError = PlatformException(
        code: '${BleShieldNativeErrorCode.connectionFailed.index}');
    final d = shield.device(a);
    await expectLater(
        d.connect(), throwsA(shieldError(ShieldErrorCode.connectFailed)));
    expect(fake.calls, containsAllInOrder(['connect:$a', 'disconnect:$a']));
  });

  test('a failure event carries the native status (GATT 133)', () async {
    fake.onConnect = (id, _) async {
      await settle(1);
      fake.emitConnection(id, false,
          error: 'GATT_ERROR',
          errorCode: BleShieldNativeErrorCode.connectionFailed,
          nativeErrorCode: 133);
    };
    final d = shield.device(a);
    await expectLater(
        d.connect(),
        throwsA(isA<ShieldError>()
            .having((e) => e.code, 'code', ShieldErrorCode.connectFailed)
            .having((e) => e.nativeCode, 'nativeCode', 133)
            .having((e) => e.platform, 'platform', 'android')));
  });

  test('concurrent connect on the same device fails, nothing queued', () async {
    fake.connectDelay = const Duration(milliseconds: 50);
    final d = shield.device(a);
    final first = d.connect();
    await expectLater(
        d.connect(), throwsA(shieldError(ShieldErrorCode.connectInProgress)));
    await first;
    expect(fake.connects, hasLength(1));
  });

  test('connect on a connected device is a no-op', () async {
    final d = shield.device(a);
    await d.connect();
    await d.connect();
    expect(fake.connects, hasLength(1));
  });

  test('connects of two devices never overlap', () async {
    var active = 0, maxActive = 0;
    fake.onConnect = (id, _) async {
      active++;
      maxActive = max(maxActive, active);
      await wait(60);
      active--;
      fake.emitConnection(id, true);
    };
    await Future.wait([shield.device(a).connect(), shield.device(b).connect()]);
    expect(maxActive, 1);
    expect(fake.calls.where((c) => c.startsWith('connect:')),
        ['connect:$a', 'connect:$b']);
    expect(
        shield.device(a).isConnected && shield.device(b).isConnected, isTrue);
  });

  test('disconnect cancels an in-flight connect at once', () async {
    fake.onConnect = (id, _) async {
      fake.states[id] = BleConnectionState.connecting;
    };
    final d = shield.device(a);
    final pending = d.connect(timeout: const Duration(seconds: 5));
    final sw = Stopwatch()..start();
    await settle();
    await d.disconnect();
    await expectLater(
        pending, throwsA(shieldError(ShieldErrorCode.connectFailed)));
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('disconnect of a connected device ends disconnected', () async {
    final d = shield.device(a);
    await d.connect();
    await d.disconnect();
    expect(d.isConnected, isFalse);
    expect(fake.calls, contains('disconnect:$a'));
  });

  test('a drop reported by the platform updates the state', () async {
    final d = shield.device(a);
    await d.connect();
    fake.emitConnection(a, false);
    expect(d.isConnected, isFalse);
  });
}
