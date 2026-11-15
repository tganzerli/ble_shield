// `requestMtu` discovers the device's services on demand on the platforms where
// the MTU is only meaningful once they are known. It runs before the MTU command
// is queued, so it must not deadlock the per-device queue. Web has no MTU API, so
// these tests are VM-only.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_shield/src/native/utils/cache_handler.dart';
import 'package:ble_shield/src/native/native.dart';

import 'ble_shield_native_test_mock.dart';

class _MtuPlatformMock extends BleShieldNativePlatformMock {
  final List<String> mtuRequests = [];
  final List<String> discoverRequests = [];
  bool failDiscovery = false;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async {
    discoverRequests.add(deviceId);
    if (failDiscovery) {
      throw BleShieldNativeException(
        code: BleShieldNativeErrorCode.failed,
        message: 'discovery failed',
      );
    }
    return const [];
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    mtuRequests.add(deviceId);
    return 247;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceId = 'AA:BB:CC:DD:EE:01';
  final canonicalId = deviceId.toLowerCase();

  late _MtuPlatformMock platform;

  setUp(() {
    platform = _MtuPlatformMock();
    BleShieldNative.setInstance(platform);
    CacheHandler.instance.resetDeviceCache(canonicalId);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    CacheHandler.instance.resetDeviceCache(canonicalId);
  });

  group('discoverServices on demand', () {
    for (final targetPlatform in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      test('on $targetPlatform before discovery', () async {
        debugDefaultTargetPlatformOverride = targetPlatform;

        expect(await BleShieldNative.requestMtu(deviceId, 247), 247);
        expect(platform.discoverRequests, [deviceId]);
        expect(platform.mtuRequests, [deviceId]);
      });
    }
  });

  group('does not discover', () {
    for (final targetPlatform in [
      TargetPlatform.android,
      TargetPlatform.windows,
    ]) {
      test('on $targetPlatform', () async {
        debugDefaultTargetPlatformOverride = targetPlatform;

        expect(await BleShieldNative.requestMtu(deviceId, 247), 247);
        expect(platform.discoverRequests, isEmpty);
        expect(platform.mtuRequests, [deviceId]);
      });
    }
  });

  test('skips discovery when discoverServices already ran', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await BleShieldNative.discoverServices(deviceId);

    expect(await BleShieldNative.requestMtu(deviceId, 247), 247);
    expect(platform.discoverRequests, [deviceId]); // only the explicit call
  });

  test('a failed on-demand discovery still attempts the MTU', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    platform.failDiscovery = true;

    expect(await BleShieldNative.requestMtu(deviceId, 247), 247);
    expect(platform.discoverRequests, [deviceId]);
    expect(platform.mtuRequests, [deviceId]);
  });

  test('matches discovery and request across device id casing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await BleShieldNative.discoverServices(deviceId.toUpperCase());

    expect(await BleShieldNative.requestMtu(deviceId.toLowerCase(), 247), 247);
    expect(platform.discoverRequests, [deviceId.toUpperCase()]);
  });

  test('a disconnect clears the discovery state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    expect(await BleShieldNative.requestMtu(deviceId, 247), 247);
    expect(platform.discoverRequests.length, 1);

    // Drive the production disconnect path, which clears the per-device cache
    // (see `BleShieldNativePlatform.updateConnection`).
    platform.updateConnection(deviceId, false);

    expect(await BleShieldNative.requestMtu(deviceId, 247), 247);
    expect(platform.discoverRequests.length, 2);
  });

  group('shares in-flight discovery', () {
    test('concurrent requestMtu calls discover once', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      await Future.wait([
        BleShieldNative.requestMtu(deviceId, 100),
        BleShieldNative.requestMtu(deviceId, 247),
      ]);

      expect(platform.discoverRequests, [deviceId]);
      expect(platform.mtuRequests, [deviceId, deviceId]);
    });

    test('requestMtu shares a discovery started by discoverServices', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      await Future.wait([
        BleShieldNative.discoverServices(deviceId),
        BleShieldNative.requestMtu(deviceId, 247),
      ]);

      expect(platform.discoverRequests, [deviceId]);
    });

    test('only one of several identical discoverServices calls runs', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      await Future.wait([
        BleShieldNative.discoverServices(deviceId),
        BleShieldNative.discoverServices(deviceId),
      ]);

      expect(platform.discoverRequests, [deviceId]);
    });

    test('a discoverServices with different options still runs its own',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      await Future.wait([
        BleShieldNative.discoverServices(deviceId),
        BleShieldNative.discoverServices(deviceId, withDescriptors: true),
      ]);

      expect(platform.discoverRequests.length, 2);
    });
  });
}
