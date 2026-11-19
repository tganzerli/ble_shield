import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/src/web/ble_shield_native_web.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';
import 'support/helpers.dart';
import 'web/fake_web_bluetooth_backend.dart';

void main() {
  test('address ids are folded to lower case', () async {
    final shield = BleShield(platform: FakeBlePlatform());
    final device = shield.device(' AA:BB:CC:DD:EE:FF ');
    expect(device.remoteId, 'aa:bb:cc:dd:ee:ff');
    expect(identical(shield.device('aa:bb:cc:dd:ee:ff'), device), isTrue);
    await shield.dispose();
  });

  group('web ids are opaque', () {
    late BleShieldNativeWeb web;
    late BleShield shield;

    setUp(() {
      web = BleShieldNativeWeb(FakeWebBluetoothBackend());
      shield = BleShield(platform: web);
    });

    tearDown(() async {
      await shield.dispose();
      await web.dispose();
    });

    test('kept verbatim, and ids that differ only in case are distinct', () {
      final upper = shield.device('aB3+xY9/Qw==');
      final lower = shield.device('ab3+xy9/qw==');
      expect(upper.remoteId, 'aB3+xY9/Qw==');
      expect(lower.remoteId, 'ab3+xy9/qw==');
      expect(identical(upper, lower), isFalse);
      // Surrounding whitespace is still trimmed.
      expect(identical(shield.device(' aB3+xY9/Qw== '), upper), isTrue);
    });

    test('a connection event finds its device by the verbatim id', () async {
      final backend = FakeWebBluetoothBackend();
      final picked = FakeWebDevice('Zq9/Kp==');
      backend.nextPick = picked;
      final w = BleShieldNativeWeb(backend);
      final s = BleShield(platform: w);
      final device = s.device((await s.requestDevice()).remoteId);
      await device.connect();
      expect(device.isConnected, isTrue);
      picked.drop();
      await settle();
      expect(device.isConnected, isFalse);
      await s.dispose();
      await w.dispose();
    });

    test('forgetRestoredId keeps the id verbatim before any install', () async {
      final store = InMemoryRestoredIdStore();
      await store.save({'aB3+xY9/Qw==', 'other'});
      final w = BleShieldNativeWeb(FakeWebBluetoothBackend());
      final s = BleShield(platform: w, restoredIdStore: store);
      // First call on a fresh engine: a folded id would match nothing.
      await s.forgetRestoredId('aB3+xY9/Qw==');
      expect(await store.load(), {'other'});
      await s.dispose();
      await w.dispose();
    });
  });
}
