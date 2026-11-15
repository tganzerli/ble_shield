import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ble_shield/src/native/utils/ble_shield_native_filter_util.dart';
import 'package:ble_shield/src/native/native.dart';

void main() {
  // A fresh util per test: the filter is mutable state, so sharing one instance
  // makes a test's outcome depend on the tests before it.
  late BleShieldNativeFilterUtil bleShieldNativeFilter;

  setUp(() {
    bleShieldNativeFilter = BleShieldNativeFilterUtil();
  });

  var device1 = BleDevice(
    deviceId: '1',
    name: '1_device',
    services: ['20a1'],
    manufacturerDataList: [
      ManufacturerData(0x01, Uint8List.fromList([1, 2, 3])),
    ],
  );
  var device2 = BleDevice(
    deviceId: '2',
    name: '2_device',
    services: ['20a2'],
    manufacturerDataList: [
      ManufacturerData(0x02, Uint8List.fromList([1, 2, 3]))
    ],
  );
  var device3 = BleDevice(
    deviceId: '3',
    name: '3_device',
    services: ['20a3'],
    manufacturerDataList: [
      ManufacturerData(0x03, Uint8List.fromList([1, 2, 3]))
    ],
  );

  group("Test Individual Filter", () {
    test('Test isNameMatchingFilters', () {
      var scanFilter = ScanFilter(
        withNamePrefix: ['1', '2'],
      );
      expect(
        bleShieldNativeFilter.nameMatches(scanFilter, device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.nameMatches(scanFilter, device2),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.nameMatches(scanFilter, device3),
        isFalse,
      );
    });

    test('Test isServicesMatchingFilters', () {
      var scanFilter = ScanFilter(
        withServices: ['20a1', '20a6', '20a3'],
      );
      expect(
        bleShieldNativeFilter.servicesMatch(scanFilter, device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.servicesMatch(scanFilter, device2),
        isFalse,
      );
      // A services-only filter constrains nothing in the name dimension.
      expect(
        bleShieldNativeFilter.nameMatches(scanFilter, device3),
        isFalse,
      );
      expect(
        bleShieldNativeFilter.nameMatches(
            ScanFilter(withNamePrefix: ['3']), device3),
        isTrue,
      );
    });

    test('Test isManufacturerDataMatchingFilters', () {
      var scanFilter = ScanFilter(withManufacturerData: [
        ManufacturerDataFilter(
          companyIdentifier: 0x01,
          payloadPrefix: Uint8List.fromList([1, 2]),
        ),
        ManufacturerDataFilter(
          companyIdentifier: 0x02,
        ),
        ManufacturerDataFilter(
          companyIdentifier: 0x03,
          payloadPrefix: Uint8List.fromList([3, 4]),
        )
      ]);
      expect(
        bleShieldNativeFilter.manufacturerDataMatches(
          scanFilter.withManufacturerData,
          device1,
        ),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.manufacturerDataMatches(
          scanFilter.withManufacturerData,
          device2,
        ),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.manufacturerDataMatches(
          scanFilter.withManufacturerData,
          device3,
        ),
        isFalse,
      );
    });
  });

  group("Test Scan Filter", () {
    test('Test filterDevice: Have filter for all', () {
      bleShieldNativeFilter.scanFilter = ScanFilter(
        withNamePrefix: ['1'],
        withServices: ['20a3'],
        withManufacturerData: [
          ManufacturerDataFilter(
            companyIdentifier: 0x02,
          )
        ],
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device2),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device3),
        isTrue,
      );
    });
    test('Test filterDevice: Filter for one', () {
      bleShieldNativeFilter.scanFilter = ScanFilter(
        withNamePrefix: ['1'],
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device2),
        isFalse,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device3),
        isFalse,
      );
    });
    test('Test filterDevice: Filter for two', () {
      bleShieldNativeFilter.scanFilter = ScanFilter(
        withNamePrefix: ['1', '2'],
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device2),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device3),
        isFalse,
      );
    });
    test('Test filterDevice: Empty Filter', () {
      bleShieldNativeFilter.scanFilter = ScanFilter();
      expect(
        bleShieldNativeFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device2),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device3),
        isTrue,
      );
    });
    test('Test filterDevice: Null Filter', () {
      bleShieldNativeFilter.scanFilter = ScanFilter();
      expect(
        bleShieldNativeFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device2),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchedScanFilter(device3),
        isTrue,
      );
    });
  });

  group("Test Exclusion Filter", () {
    test('Test exclusionFilter: Have filter for 1', () {
      bleShieldNativeFilter.scanFilter = ScanFilter(exclusionFilters: [
        ExclusionFilter(
          namePrefix: '1',
          services: ['20a1'],
          manufacturerDataFilter: [
            ManufacturerDataFilter(
              companyIdentifier: 0x01,
            )
          ],
        )
      ]);
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device2),
        isFalse,
      );
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device3),
        isFalse,
      );
    });

    test('Test exclusionFilter: Filter for two', () {
      bleShieldNativeFilter.scanFilter = ScanFilter(exclusionFilters: [
        ExclusionFilter(
          namePrefix: '1',
          services: ['20a1'],
          manufacturerDataFilter: [
            ManufacturerDataFilter(
              companyIdentifier: 0x01,
            )
          ],
        ),
        ExclusionFilter(
          namePrefix: '2',
          services: ['20a2'],
          manufacturerDataFilter: [
            ManufacturerDataFilter(
              companyIdentifier: 0x02,
            )
          ],
        ),
      ]);
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device1),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device2),
        isTrue,
      );
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device3),
        isFalse,
      );
    });

    test('Test exclusionFilter: Invalid filter for last', () {
      bleShieldNativeFilter.scanFilter = ScanFilter(exclusionFilters: [
        ExclusionFilter(
          namePrefix: '3',
          services: ['20a2'],
          manufacturerDataFilter: [
            ManufacturerDataFilter(
              companyIdentifier: 0x01,
            )
          ],
        ),
      ]);
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device1),
        isFalse,
      );
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device2),
        isFalse,
      );
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device3),
        isFalse,
      );
    });

    test('Test exclusionFilter: Empty Filter', () {
      bleShieldNativeFilter.scanFilter = ScanFilter();
      expect(
        bleShieldNativeFilter.matchesExclusionFilter(device1),
        isFalse,
      );
    });

    test('Test connectableOnly filter', () {
      final connectableDevice = BleDevice(
        deviceId: 'c1',
        name: 'connectable',
        connectable: true,
      );
      final nonConnectableDevice = BleDevice(
        deviceId: 'c2',
        name: 'beacon',
        connectable: false,
      );
      final unknownDevice = BleDevice(
        deviceId: 'c3',
        name: 'unknown',
        connectable: null,
      );

      // When connectableOnly is true, non-connectable is rejected
      bleShieldNativeFilter.scanFilter = ScanFilter(connectableOnly: true);
      expect(
          bleShieldNativeFilter.matchedScanFilter(connectableDevice), isTrue);
      expect(bleShieldNativeFilter.matchedScanFilter(nonConnectableDevice),
          isFalse);
      expect(bleShieldNativeFilter.matchedScanFilter(unknownDevice), isTrue);
      expect(bleShieldNativeFilter.matchesConnectableFilter(connectableDevice),
          isTrue);
      expect(
          bleShieldNativeFilter.matchesConnectableFilter(nonConnectableDevice),
          isFalse);
      expect(bleShieldNativeFilter.matchesConnectableFilter(unknownDevice),
          isTrue);

      // When connectableOnly is null or false, non-connectable is allowed
      bleShieldNativeFilter.scanFilter = ScanFilter(connectableOnly: null);
      expect(
          bleShieldNativeFilter.matchedScanFilter(connectableDevice), isTrue);
      expect(bleShieldNativeFilter.matchedScanFilter(nonConnectableDevice),
          isTrue);
      expect(bleShieldNativeFilter.matchedScanFilter(unknownDevice), isTrue);
      expect(
          bleShieldNativeFilter.matchesConnectableFilter(nonConnectableDevice),
          isTrue);

      bleShieldNativeFilter.scanFilter = ScanFilter(connectableOnly: false);
      expect(
          bleShieldNativeFilter.matchedScanFilter(connectableDevice), isTrue);
      expect(bleShieldNativeFilter.matchedScanFilter(nonConnectableDevice),
          isTrue);
      expect(bleShieldNativeFilter.matchedScanFilter(unknownDevice), isTrue);
      expect(
          bleShieldNativeFilter.matchesConnectableFilter(nonConnectableDevice),
          isTrue);
    });
  });

  group("Test Service Data Filter", () {
    // A beacon that carries 0x181A only in its advertising Service Data, without
    // listing it among its advertised services (#57).
    final serviceDataBeacon = BleDevice(
      deviceId: 'sd1',
      name: 'ATC_DD7A81',
      services: [],
      serviceData: {
        '181a': Uint8List.fromList([0x81, 0x7a, 0xdd]),
      },
    );
    // Advertises the service UUID the old way, and carries full-form service
    // data for another UUID.
    final advertisedDevice = BleDevice(
      deviceId: 'sd2',
      name: 'other',
      services: ['20a2'],
      serviceData: {
        '0000feaa-0000-1000-8000-00805f9b34fb': Uint8List.fromList([1]),
      },
    );
    // Neither advertised services nor service data.
    final emptyDevice = BleDevice(
      deviceId: 'sd3',
      name: 'empty',
      services: [],
      serviceData: {},
    );

    test('Test serviceDataMatch: short, case-insensitive and full form', () {
      for (final filterValue in [
        '181a',
        '181A',
        '0x181a',
        '0000181a-0000-1000-8000-00805f9b34fb',
        '0000181A-0000-1000-8000-00805F9B34FB',
      ]) {
        expect(
          bleShieldNativeFilter.serviceDataMatch(
            ScanFilter(withServiceData: [filterValue]),
            serviceDataBeacon,
          ),
          isTrue,
          reason: '$filterValue should match the advertised Service Data UUID',
        );
      }
    });

    test('Test serviceDataMatch: non-matching and empty service data', () {
      final scanFilter = ScanFilter(withServiceData: ['2a6e']);
      expect(
          bleShieldNativeFilter.serviceDataMatch(scanFilter, advertisedDevice),
          isFalse);
      expect(bleShieldNativeFilter.serviceDataMatch(scanFilter, emptyDevice),
          isFalse);
      expect(
          bleShieldNativeFilter.serviceDataMatch(scanFilter, serviceDataBeacon),
          isFalse);
    });

    test('Test serviceDataMatch: unset service data filter does not narrow',
        () {
      expect(
        bleShieldNativeFilter.serviceDataMatch(ScanFilter(), serviceDataBeacon),
        isFalse,
      );
    });

    test('Test matchedScanFilter: Service Data only device is discovered', () {
      // withServices alone does not see the beacon...
      bleShieldNativeFilter.scanFilter = ScanFilter(withServices: ['181a']);
      expect(
          bleShieldNativeFilter.matchedScanFilter(serviceDataBeacon), isFalse);

      // ...but withServiceData does.
      bleShieldNativeFilter.scanFilter = ScanFilter(withServiceData: ['181a']);
      expect(
          bleShieldNativeFilter.matchedScanFilter(serviceDataBeacon), isTrue);
      expect(
          bleShieldNativeFilter.matchedScanFilter(advertisedDevice), isFalse);
      expect(bleShieldNativeFilter.matchedScanFilter(emptyDevice), isFalse);
    });

    test('Test matchedScanFilter: conditions stay in OR relation', () {
      bleShieldNativeFilter.scanFilter = ScanFilter(
        withServices: ['20a2'],
        withServiceData: ['181a'],
      );
      expect(
          bleShieldNativeFilter.matchedScanFilter(serviceDataBeacon), isTrue);
      expect(bleShieldNativeFilter.matchedScanFilter(advertisedDevice), isTrue);
      expect(bleShieldNativeFilter.matchedScanFilter(emptyDevice), isFalse);
    });

    test('Test matchedScanFilter: unset withServiceData keeps old behaviour',
        () {
      bleShieldNativeFilter.scanFilter = ScanFilter(withServices: ['181a']);
      expect(
          bleShieldNativeFilter.matchedScanFilter(serviceDataBeacon), isFalse);

      bleShieldNativeFilter.scanFilter = ScanFilter();
      expect(
          bleShieldNativeFilter.matchedScanFilter(serviceDataBeacon), isTrue);
    });

    test('Test matchedScanFilter: malformed device keys do not throw', () {
      final malformed = BleDevice(
        deviceId: 'sd4',
        name: 'malformed',
        serviceData: {
          'not-a-uuid': Uint8List.fromList([1])
        },
      );
      bleShieldNativeFilter.scanFilter = ScanFilter(withServiceData: ['181a']);
      expect(bleShieldNativeFilter.matchedScanFilter(malformed), isFalse);
    });
  });
}
