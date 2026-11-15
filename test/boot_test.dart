import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';

const x = 'aa:00:00:00:00:01';
const y = 'aa:00:00:00:00:02';
const z = 'aa:00:00:00:00:03';
const svc = '0000fff0-0000-1000-8000-00805f9b34fb';

void main() {
  late FakeBlePlatform fake;

  setUp(() => fake = FakeBlePlatform());

  group('construction is inert (risk 6: eager singletons)', () {
    test('the constructor makes no platform call and installs nothing', () {
      var configured = 0;
      BleShield(
        platform: fake,
        targetPlatform: iOS,
        restorationConfigurator: (_) async => ++configured > 0,
      );
      expect(fake.calls, isEmpty);
      expect(fake.onConnectionChange, isNull,
          reason:
              'the platform instance was not even handed to the native layer');
      expect(configured, 0);
    });

    test('device() installs listeners but makes no native call', () {
      final shield = BleShield(platform: fake, targetPlatform: iOS);
      shield.device(x);
      expect(fake.calls, isEmpty);
      expect(fake.onConnectionChange, isNotNull);
    });
  });

  group('configureRestoration', () {
    test('listener installed first, then configure, then the first native call',
        () async {
      final order = <String>[];
      final shield = BleShield(
        platform: fake,
        targetPlatform: iOS,
        restorationConfigurator: (id) async {
          order.add('configure:$id');
          expect(fake.onConnectionChange, isNotNull,
              reason: 'restoration events may arrive while the manager is '
                  'created');
          expect(fake.calls, isEmpty,
              reason: 'nothing may create the manager before configure');
          return true;
        },
      );
      expect(await shield.configureRestoration('app.central'), isTrue);
      await settle();
      expect(order, ['configure:app.central']);
      expect(fake.calls.first, 'getAvailability');
    });

    test('a peripheral restored during configure is captured and persisted',
        () async {
      final store = InMemoryRestoredIdStore();
      final shield = BleShield(
        platform: fake,
        targetPlatform: iOS,
        restoredIdStore: store,
        restorationConfigurator: (_) async {
          fake.emitConnection('AA:00:00:00:00:01', true); // willRestoreState
          return true;
        },
      );
      await shield.configureRestoration('app.central');
      await settle();
      expect(shield.restoredIds, {x});
      expect(await store.load(), {x});
      expect(shield.device(x).isConnected, isTrue,
          reason: 'a device created after the event starts connected');
    });

    test('not granted is returned as false', () async {
      final shield = BleShield(
          platform: fake,
          targetPlatform: iOS,
          restorationConfigurator: (_) async => false);
      expect(await shield.configureRestoration('app.central'), isFalse);
    });

    test('off iOS: false, without calling the configurator', () async {
      var called = false;
      final shield = BleShield(
          platform: fake,
          targetPlatform: android,
          restorationConfigurator: (_) async => called = true);
      expect(await shield.configureRestoration('app.central'), isFalse);
      expect(called, isFalse);
      expect(fake.calls, isEmpty);
    });

    test('an invalid identifier is a typed error', () async {
      final shield = BleShield(
          platform: fake,
          targetPlatform: iOS,
          restorationConfigurator: (id) async =>
              throw ArgumentError.value(id, 'restorationIdentifier'));
      await expectLater(shield.configureRestoration(' '),
          throwsA(shieldError(ShieldErrorCode.invalidArgument)));
    });
  });

  group('restored ids', () {
    test('connections ble_shield started are not "restored"', () async {
      final shield = BleShield(platform: fake, targetPlatform: iOS);
      await shield.device(x).connect();
      expect(shield.restoredIds, isEmpty);
    });

    test('persisted ids are hydrated with their current state on next launch',
        () async {
      final store = InMemoryRestoredIdStore();
      await store.save({x, y});
      fake.states[x] = BleConnectionState.connected;
      final shield = BleShield(
          platform: fake, targetPlatform: iOS, restoredIdStore: store);
      final devices = await shield.restoredDevices();
      final byId = {for (final d in devices) d.remoteId: d};
      expect(byId.keys.toSet(), {x, y});
      expect(byId[x]!.isConnected, isTrue);
      expect(byId[y]!.isConnected, isFalse,
          reason: 'returned so the app can turn auto-reconnect on');
      await shield.forgetRestoredId(y);
      expect(await store.load(), {x});
    });
  });

  group('systemDevices', () {
    BleDevice sys(String id, [List<String> services = const []]) =>
        BleDevice(deviceId: id, name: null, services: services);

    test(
        'Android: withServices is not passed to the platform; filtered in Dart',
        () async {
      fake.systemDevices = [sys(x), sys(y), sys(z)];
      final shield = BleShield(platform: fake, targetPlatform: android);
      // What ble_shield knows from advertisements: y offers svc, z does not.
      await shield.startScan();
      fake.advertise(y, services: ['FFF0']);
      fake.advertise(z, services: ['180D']);
      await settle();
      await shield.stopScan();

      final found = await shield.systemDevices(withServices: ['FFF0']);
      expect(fake.systemDevicesArgs.single, isNull);
      expect(found.map((d) => d.remoteId).toSet(), {x, y},
          reason: 'x has unknown services (kept); z offers others (dropped)');
      expect(found.every((d) => d.isConnected), isTrue);
    });

    test('Apple: withServices goes to the platform, canonicalised', () async {
      fake.systemDevices = [
        sys(x, ['FFF0'])
      ];
      final shield = BleShield(platform: fake, targetPlatform: iOS);
      final found = await shield.systemDevices(withServices: ['fff0']);
      expect(fake.systemDevicesArgs.single, [svc]);
      expect(found.single.remoteId, x);
    });

    test('connect attaches this engine to an already connected system device',
        () async {
      fake.systemDevices = [sys(x)];
      final shield = BleShield(platform: fake, targetPlatform: android);
      final d = (await shield.systemDevices(withServices: [svc])).single;
      expect(d.isConnected, isTrue);
      await d.connect();
      expect(fake.connects, [(x, false)]);
      await d.connect();
      expect(fake.connects, hasLength(1));
    });
  });
}
