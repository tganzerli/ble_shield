import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';

const id = 'aa:00:00:00:00:01';
const other = 'aa:00:00:00:00:02';

/// Short delay so the scenarios run fast; one test checks the 3 s default.
const delay = Duration(milliseconds: 200);

void main() {
  late FakeBlePlatform fake;
  late BleShield shield;
  late List<ReconnectEvent> events;

  Future<ShieldDevice> build({TargetPlatform target = android}) async {
    shield = BleShield(platform: fake, targetPlatform: target);
    shield.adapterStateNow; // start adapter tracking
    await settle();
    final d = shield.device(id);
    d.reconnectEvents.listen(events.add);
    return d;
  }

  int autoConnects() => fake.connects.where((c) => c.$2).length;
  List<String> log() => events.map((e) => e.toString()).toList();

  setUp(() {
    fake = FakeBlePlatform();
    events = [];
  });

  // Field scenario: the user turns Bluetooth off, every device drops, each
  // arms its reconnection, and when the delay ends the adapter is off.
  group('a reconnection failure never leaks', () {
    test('a native connect that throws is reported, not raised', () async {
      final d = await build();
      await d.connect();
      fake.connectError = PlatformException(
        code: '${BleShieldNativeErrorCode.bluetoothNotEnabled.index}',
        message: 'Bluetooth must be turned on',
      );
      final zone = await zoneErrors(() async {
        d.setAutoReconnect(true, delay: delay);
        fake.emitConnection(id, false);
        await wait(300);
      });
      expect(zone, isEmpty,
          reason: 'an error in the zone is what a global handler reports as '
              'a fatal crash');
      expect(autoConnects(), 1);
      final failed =
          events.firstWhere((e) => e.outcome == ReconnectOutcome.failed);
      expect(failed.origin, ReconnectOrigin.drop);
      expect(failed.error!.code, ShieldErrorCode.adapterOff);
      await d.dispose();
    });

    test('a device disposed during the delay fires no orphan connect',
        () async {
      final d = await build();
      await d.connect();
      d.setAutoReconnect(true, delay: delay);
      fake.emitConnection(id, false);
      await settle();
      await d.dispose();
      await wait(300);
      expect(autoConnects(), 0);
      expect(log(),
          contains('[Reconnect] $id skipped origin=drop reason=disposed'));
    });

    test('adapter off skips the attempt; reconnection resumes afterwards',
        () async {
      final d = await build();
      await d.connect();
      d.setAutoReconnect(true, delay: delay);
      fake.setAvailability(AvailabilityState.poweredOff);
      fake.emitConnection(id, false);
      await wait(300);
      expect(autoConnects(), 0);
      expect(log(),
          contains('[Reconnect] $id skipped origin=drop reason=adapter-off'));

      // The skip must not leave the machine stuck: adapter back on re-arms,
      // and a later drop arms again.
      fake.setAvailability(AvailabilityState.poweredOn);
      await wait(300);
      expect(autoConnects(), 1);
      expect(d.isConnected, isTrue);
      fake.emitConnection(id, false);
      await wait(300);
      expect(autoConnects(), 2);
      expect(log(), contains('[Reconnect] $id fired origin=adapterOn'));
      expect(log(), contains('[Reconnect] $id fired origin=drop'));
      await d.dispose();
    });
  });

  // Two timers arm the pending connect: the KICK of setAutoReconnect(true)
  // and the DROP of a connected → disconnected transition. The kick must give
  // up if the device connected or was disconnected by the app meanwhile; the
  // drop never.
  group('kick × drop', () {
    test(
        'connection + commanded disconnect during the wait ⇒ the kick gives '
        'up; the drop reconnects', () async {
      final d = await build();
      d.setAutoReconnect(true, delay: const Duration(milliseconds: 300));
      await wait(100);
      await d.connect();
      await wait(10);
      await d.disconnect(); // end of the session
      await wait(220); // t ≈ 330 ms: the kick would have fired
      expect(autoConnects(), 0,
          reason: 'a kick firing after the commanded disconnect reconnected '
              'the device and opened a second session');
      await wait(200); // t ≈ 530 ms: the drop (disconnect + 300 ms) fired
      expect(autoConnects(), 1);
      expect(log(),
          contains('[Reconnect] $id skipped origin=kick reason=superseded'));
      expect(log(), contains('[Reconnect] $id fired origin=drop'));
      await d.dispose();
    });

    test('no connection in between ⇒ the kick fires', () async {
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      await wait(260);
      expect(autoConnects(), 1);
      expect(log(), contains('[Reconnect] $id fired origin=kick'));
      await d.dispose();
    });

    test('a failed direct connect ⇒ the kick still fires', () async {
      fake.onConnect = (deviceId, auto) async {
        if (!auto) {
          throw PlatformException(
              code: '${BleShieldNativeErrorCode.connectionFailed.index}');
        }
        fake.emitConnection(deviceId, true);
      };
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      await expectLater(
          d.connect(), throwsA(shieldError(ShieldErrorCode.connectFailed)));
      await wait(260);
      expect(autoConnects(), 1);
      expect(d.isConnected, isTrue);
      await d.dispose();
    });

    test('an uncommanded drop (link loss) ⇒ reconnects', () async {
      final d = await build();
      await d.connect();
      d.setAutoReconnect(true, delay: delay);
      fake.emitConnection(id, false);
      await wait(260);
      expect(autoConnects(), 1);
      expect(log(), ['[Reconnect] $id fired origin=drop']);
      await d.dispose();
    });
  });

  group('state machine guards', () {
    test('turning it off during the delay skips with "disabled"', () async {
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      await wait(50);
      d.setAutoReconnect(false);
      await wait(250);
      expect(fake.connects, isEmpty);
      expect(log(), ['[Reconnect] $id skipped origin=kick reason=disabled']);
    });

    test('disconnect cancels the armed attempt before the native call',
        () async {
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      final before = fake.calls.length;
      await d.disconnect();
      expect(events.single.skipReason, ReconnectSkipReason.superseded);
      expect(fake.calls.sublist(before), contains('disconnect:$id'));
      await wait(250);
      expect(fake.connects, isEmpty);
    });

    test('a pending request is not stacked by repeated kicks', () async {
      fake.onConnect = (_, __) async {}; // stays pending
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      await wait(260);
      d.setAutoReconnect(true, delay: delay);
      d.setAutoReconnect(true, delay: delay);
      await wait(260);
      expect(fake.connects, hasLength(1));
      await d.dispose();
    });

    test('a pending request does not hold the GATT lock', () async {
      fake.onConnect = (deviceId, auto) async {
        if (!auto) fake.emitConnection(deviceId, true);
      };
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      await wait(260);
      await shield
          .device(other)
          .connect()
          .timeout(const Duration(milliseconds: 500));
      expect(shield.device(other).isConnected, isTrue);
      await d.dispose();
    });

    test('Android: the attempt is a native autoConnect request', () async {
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      await wait(260);
      expect(fake.connects.single, (id, true));
      await d.dispose();
    });

    test('Apple: plain connect, re-issued by ble_shield after each drop',
        () async {
      final d = await build(target: iOS);
      d.setAutoReconnect(true, delay: delay);
      await wait(260);
      expect(fake.connects, [(id, false)]);
      fake.emitConnection(id, false);
      await wait(260);
      expect(fake.connects, [(id, false), (id, false)]);
      await d.dispose();
    });

    test('a failed attempt is re-armed (retry)', () async {
      fake.connectError = PlatformException(
          code: '${BleShieldNativeErrorCode.connectionFailed.index}');
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      await wait(500);
      expect(fake.connects.length, greaterThanOrEqualTo(2));
      expect(log(), contains('[Reconnect] $id fired origin=retry'));
      await d.dispose();
    });

    test('the default delay is 3 s', () async {
      final d = await build();
      d.setAutoReconnect(true);
      await wait(2800);
      expect(fake.connects, isEmpty);
      await wait(400);
      expect(fake.connects, hasLength(1));
      await d.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // A session ended by the app with disconnect(rearm: false) must not
  // reconnect on its own; the next connection is up to the app. No timer: the suspension ends on an event.
  group('disconnect(rearm: false)', () {
    Future<ShieldDevice> session() async {
      final d = await build();
      await d.connect();
      d.setAutoReconnect(true, delay: delay);
      return d;
    }

    test('ends the session without re-arming; autoReconnect stays on',
        () async {
      final d = await session();
      await d.disconnect(rearm: false);
      await wait(450);
      expect(d.isConnected, isFalse);
      expect(autoConnects(), 0,
          reason: 'a re-armed drop is the reconnection loop it prevents');
      expect(log(), isEmpty, reason: 'nothing was armed, so nothing skipped');
      expect(d.autoReconnect, isTrue);
      await d.dispose();
    });

    test('the adapter coming back on does not re-arm either', () async {
      final d = await session();
      await d.disconnect(rearm: false);
      fake.setAvailability(AvailabilityState.poweredOff);
      await settle();
      fake.setAvailability(AvailabilityState.poweredOn);
      await wait(450);
      expect(autoConnects(), 0);
      expect(log(), isEmpty);
      await d.dispose();
    });

    test('the next direct connection lifts it: its drop re-arms', () async {
      final d = await session();
      await d.disconnect(rearm: false);
      await wait(300);
      await d.connect();
      fake.emitConnection(id, false); // link loss in the new session
      await wait(260);
      expect(autoConnects(), 1);
      expect(log(), ['[Reconnect] $id fired origin=drop']);
      await d.dispose();
    });

    test('a connection adopted from systemDevices lifts it too', () async {
      final d = await session();
      await d.disconnect(rearm: false);
      await wait(300);
      fake.systemDevices = [BleDevice(deviceId: id, name: null)];
      final adopted = (await shield.systemDevices(withServices: [])).single;
      expect(identical(adopted, d), isTrue);
      expect(d.isConnected, isTrue);
      fake.emitConnection(id, false);
      await wait(260);
      expect(autoConnects(), 1);
      expect(log(), ['[Reconnect] $id fired origin=drop']);
      await d.dispose();
    });

    test('an explicit setAutoReconnect(true) lifts it and kicks', () async {
      final d = await session();
      await d.disconnect(rearm: false);
      await wait(300);
      d.setAutoReconnect(true, delay: delay);
      await wait(260);
      expect(autoConnects(), 1);
      expect(log(), ['[Reconnect] $id fired origin=kick']);
      await d.dispose();
    });

    test('a device that never connected: the kick gives up, nothing after',
        () async {
      final d = await build();
      d.setAutoReconnect(true, delay: delay);
      await wait(50);
      await d.disconnect(rearm: false);
      fake.setAvailability(AvailabilityState.poweredOff);
      await settle();
      fake.setAvailability(AvailabilityState.poweredOn);
      await wait(450);
      expect(fake.connects, isEmpty);
      expect(log(), ['[Reconnect] $id skipped origin=kick reason=superseded']);
      await d.dispose();
    });

    test('a connect in flight fails and nothing is armed', () async {
      fake.onConnect = (deviceId, _) async {
        fake.states[deviceId] = BleConnectionState.connecting;
      };
      final d = await build();
      d.setAutoReconnect(true, delay: const Duration(seconds: 5));
      final pending = d.connect(timeout: const Duration(seconds: 5));
      await settle();
      await d.disconnect(rearm: false);
      await expectLater(
          pending, throwsA(shieldError(ShieldErrorCode.connectFailed)));
      await wait(300);
      expect(autoConnects(), 0);
      expect(log(), ['[Reconnect] $id skipped origin=kick reason=superseded']);
      await d.dispose();
    });

    test('a later default disconnect does not lift it', () async {
      final d = await session();
      await d.disconnect(rearm: false);
      await d.disconnect();
      await wait(450);
      expect(autoConnects(), 0);
      expect(log(), isEmpty);
      await d.dispose();
    });

    test('a failed disconnect keeps the session re-arming on a real drop',
        () async {
      final d = await session();
      fake.disconnectEmitsEvent = false; // the link survives the disconnect
      await expectLater(
          d.disconnect(
              rearm: false, timeout: const Duration(milliseconds: 100)),
          throwsA(isA<ShieldError>()));
      expect(d.isConnected, isTrue);
      fake.emitConnection(id, false); // real drop of the surviving session
      await wait(260);
      expect(autoConnects(), 1,
          reason: 'a suspension left on a live session silences real drops');
      expect(log(), ['[Reconnect] $id fired origin=drop']);
      await d.dispose();
    });

    test('a native disconnect error keeps the session re-arming too', () async {
      final d = await session();
      fake.disconnectError = PlatformException(code: 'disconnect-failed');
      await expectLater(
          d.disconnect(rearm: false), throwsA(isA<ShieldError>()));
      expect(d.isConnected, isTrue);
      fake.emitConnection(id, false);
      await wait(260);
      expect(autoConnects(), 1);
      expect(log(), ['[Reconnect] $id fired origin=drop']);
      await d.dispose();
    });

    test('the default disconnect still re-arms (contract unchanged)', () async {
      final d = await session();
      await d.disconnect();
      await wait(260);
      expect(autoConnects(), 1);
      expect(log(), ['[Reconnect] $id fired origin=drop']);
      await d.dispose();
    });
  });

  // A default disconnect() on a device that already lost its link must
  // not cancel the reconnection that link loss armed. The
  // kick, rearm: false and autoReconnect off keep cancelling.
  group('disconnect without a link', () {
    /// Connected session with auto-reconnect on, then a real drop.
    Future<ShieldDevice> dropped({TargetPlatform target = android}) async {
      final d = await build(target: target);
      await d.connect();
      d.setAutoReconnect(true, delay: delay);
      fake.emitConnection(id, false);
      await settle();
      return d;
    }

    int nativeDisconnectsSince(int from) =>
        fake.calls.sublist(from).where((c) => c == 'disconnect:$id').length;

    test('the armed timer of a drop survives and fires', () async {
      final d = await dropped();
      final before = fake.calls.length;
      await d.disconnect();
      expect(nativeDisconnectsSince(before), 0,
          reason:
              'a native disconnect cancels the pending request (cancelOpen)');
      expect(log(), isEmpty, reason: 'nothing was cancelled');
      await wait(260);
      expect(autoConnects(), 1);
      expect(log(), ['[Reconnect] $id fired origin=drop']);
      await d.dispose();
    });

    test('the pending request of a drop survives and connects', () async {
      fake.onConnect = (deviceId, auto) async {
        if (!auto) fake.emitConnection(deviceId, true); // auto stays pending
      };
      final d = await dropped();
      await wait(260); // the drop fired: autoConnect pending in the OS
      expect(autoConnects(), 1);
      final before = fake.calls.length;
      await d.disconnect();
      expect(nativeDisconnectsSince(before), 0);
      fake.emitConnection(id, true); // the OS completes the pending request
      await settle();
      expect(d.isConnected, isTrue);
      await d.dispose();
    });

    test('Apple: the pending plain connect of a drop survives too', () async {
      fake.onConnect = (deviceId, auto) async {
        if (fake.connects.length == 1) fake.emitConnection(deviceId, true);
      };
      final d = await dropped(target: iOS);
      await wait(260);
      expect(fake.connects, [(id, false), (id, false)]);
      final before = fake.calls.length;
      await d.disconnect();
      expect(nativeDisconnectsSince(before), 0);
      await d.dispose();
    });

    test('a retry armed after a failed attempt survives', () async {
      var autoCalls = 0;
      fake.onConnect = (deviceId, auto) async {
        if (!auto) return fake.emitConnection(deviceId, true);
        if (++autoCalls == 1) {
          throw PlatformException(
              code: '${BleShieldNativeErrorCode.connectionFailed.index}');
        }
        fake.emitConnection(deviceId, true);
      };
      final d = await dropped();
      await wait(260); // drop fired and failed: the retry is armed
      expect(log(), contains('[Reconnect] $id fired origin=drop'));
      final before = fake.calls.length;
      await d.disconnect();
      expect(nativeDisconnectsSince(before), 0);
      await wait(260);
      expect(log(), contains('[Reconnect] $id fired origin=retry'));
      expect(log().where((e) => e.contains('skipped')), isEmpty);
      expect(d.isConnected, isTrue);
      await d.dispose();
    });

    test('an attempt armed by the adapter coming back on survives', () async {
      final d = await build();
      await d.connect();
      d.setAutoReconnect(true, delay: delay);
      fake.setAvailability(AvailabilityState.poweredOff);
      fake.emitConnection(id, false);
      await wait(260); // the drop is skipped: adapter off
      fake.setAvailability(AvailabilityState.poweredOn);
      await settle(); // adapterOn armed
      final before = fake.calls.length;
      await d.disconnect();
      expect(nativeDisconnectsSince(before), 0);
      await wait(260);
      expect(log(), contains('[Reconnect] $id fired origin=adapterOn'));
      expect(d.isConnected, isTrue);
      await d.dispose();
    });

    test('rearm: false still cancels and suspends', () async {
      final d = await dropped();
      final before = fake.calls.length;
      await d.disconnect(rearm: false);
      expect(nativeDisconnectsSince(before), 1);
      expect(log(), ['[Reconnect] $id skipped origin=drop reason=superseded']);
      await wait(260);
      expect(autoConnects(), 0);
      await d.dispose();
    });

    test('with autoReconnect off, disconnect still cancels the pending request',
        () async {
      fake.onConnect = (deviceId, auto) async {
        if (!auto) fake.emitConnection(deviceId, true);
      };
      final d = await dropped();
      await wait(260); // pending in the OS
      d.setAutoReconnect(false); // leaves the pending request alone
      final before = fake.calls.length;
      await d.disconnect();
      expect(nativeDisconnectsSince(before), 1,
          reason: 'documented way to drop a pending request');
      await d.dispose();
    });

    test('a connect in flight: the drop attempt is cancelled as before',
        () async {
      final d = await dropped();
      fake.onConnect = (deviceId, auto) async {
        fake.states[deviceId] = BleConnectionState.connecting; // stays pending
      };
      final pending = expectLater(
          d.connect(timeout: const Duration(seconds: 5)),
          throwsA(shieldError(ShieldErrorCode.connectFailed)));
      final before = fake.calls.length;
      await d.disconnect();
      await pending;
      expect(nativeDisconnectsSince(before), 1);
      expect(log(), ['[Reconnect] $id skipped origin=drop reason=superseded']);
      await wait(260);
      expect(autoConnects(), 0);
      await d.dispose();
    });

    test('a connected device: the default disconnect is unchanged', () async {
      final d = await build();
      await d.connect();
      d.setAutoReconnect(true, delay: delay);
      final before = fake.calls.length;
      await d.disconnect();
      expect(nativeDisconnectsSince(before), 1);
      await wait(260);
      expect(log(), ['[Reconnect] $id fired origin=drop'],
          reason: 'its own drop re-arms');
      await d.dispose();
    });

    test('nothing armed: the native disconnect still releases the client',
        () async {
      final d = await build();
      await d.connect();
      fake.emitConnection(id, false); // drop with auto-reconnect off
      await settle();
      final before = fake.calls.length;
      await d.disconnect();
      expect(nativeDisconnectsSince(before), 1);
      await d.dispose();
    });
  });
}
