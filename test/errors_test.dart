import 'dart:async';

import 'package:ble_shield/ble_shield.dart';
import 'package:ble_shield/src/errors.dart';
import 'package:ble_shield/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapShieldError', () {
    final table = <BleShieldNativeErrorCode, ShieldErrorCode>{
      BleShieldNativeErrorCode.bluetoothNotEnabled: ShieldErrorCode.adapterOff,
      BleShieldNativeErrorCode.bluetoothUnauthorized:
          ShieldErrorCode.unauthorized,
      BleShieldNativeErrorCode.deviceDisconnected: ShieldErrorCode.notConnected,
      BleShieldNativeErrorCode.deviceNotFound: ShieldErrorCode.deviceNotFound,
      BleShieldNativeErrorCode.connectionInProgress:
          ShieldErrorCode.connectInProgress,
      BleShieldNativeErrorCode.connectionTimeout:
          ShieldErrorCode.connectTimeout,
      BleShieldNativeErrorCode.connectionFailed: ShieldErrorCode.connectFailed,
      BleShieldNativeErrorCode.scanFailed: ShieldErrorCode.scanFailed,
      BleShieldNativeErrorCode.characteristicNotFound:
          ShieldErrorCode.characteristicNotFound,
      BleShieldNativeErrorCode.serviceNotFound:
          ShieldErrorCode.characteristicNotFound,
      BleShieldNativeErrorCode.operationTimeout:
          ShieldErrorCode.operationTimeout,
      BleShieldNativeErrorCode.writeFailed: ShieldErrorCode.gattFailed,
      BleShieldNativeErrorCode.writeRequestBusy: ShieldErrorCode.gattFailed,
      BleShieldNativeErrorCode.notSupported: ShieldErrorCode.unsupported,
      BleShieldNativeErrorCode.illegalArgument: ShieldErrorCode.invalidArgument,
      BleShieldNativeErrorCode.unknownError: ShieldErrorCode.unknown,
    };

    table.forEach((native, expected) {
      test('BleShieldNativeException ${native.name} → ${expected.name}', () {
        final e = mapShieldError(
          BleShieldNativeException(code: native, message: 'x'),
          op: ShieldOperation.other,
          platform: 'android',
        );
        expect(e.code, expected);
        expect(e.platform, 'android');
      });
    });

    test('PlatformException with a numeric native error code', () {
      final e = mapShieldError(
        PlatformException(
          code: '${BleShieldNativeErrorCode.readNotPermitted.index}',
          message: 'nope',
        ),
        op: ShieldOperation.read,
        platform: 'apple',
      );
      expect(e.code, ShieldErrorCode.gattFailed);
      expect(e.message, 'nope');
      expect(e.platform, 'apple');
    });

    test('PlatformException with an out-of-range code does not throw', () {
      final e = mapShieldError(
        PlatformException(code: '9999'),
        op: ShieldOperation.write,
      );
      expect(e.code, ShieldErrorCode.gattFailed);
    });

    test('PlatformException with a textual code', () {
      final e = mapShieldError(
        PlatformException(code: 'bluetooth_not_enabled'),
        op: ShieldOperation.connect,
      );
      expect(e.code, ShieldErrorCode.adapterOff);
    });

    test('unknown errors fall back by operation', () {
      expect(
          mapShieldError(Exception('Queue Cancelled'),
                  op: ShieldOperation.write)
              .code,
          ShieldErrorCode.gattFailed);
      expect(mapShieldError('boom', op: ShieldOperation.connect).code,
          ShieldErrorCode.connectFailed);
      expect(mapShieldError('boom', op: ShieldOperation.scan).code,
          ShieldErrorCode.scanFailed);
      expect(mapShieldError('boom', op: ShieldOperation.other).code,
          ShieldErrorCode.unknown);
    });

    test('a cancelled picker is cancelled; elsewhere the old mapping holds',
        () {
      final cancelled = BleShieldNativeException(
        code: BleShieldNativeErrorCode.operationCancelled,
        message: 'User cancelled the requestDevice() chooser.',
      );
      expect(mapShieldError(cancelled, op: ShieldOperation.picker).code,
          ShieldErrorCode.cancelled);
      expect(mapShieldError(cancelled, op: ShieldOperation.read).code,
          ShieldErrorCode.gattFailed);
      expect(mapShieldError(cancelled, op: ShieldOperation.connect).code,
          ShieldErrorCode.connectFailed);
      expect(mapShieldError('boom', op: ShieldOperation.picker).code,
          ShieldErrorCode.unknown);
    });

    test('TimeoutException depends on the operation', () {
      final t = TimeoutException('t', const Duration(seconds: 1));
      expect(mapShieldError(t, op: ShieldOperation.connect).code,
          ShieldErrorCode.connectTimeout);
      expect(mapShieldError(t, op: ShieldOperation.read).code,
          ShieldErrorCode.operationTimeout);
    });

    test('ConnectionException keeps the native code given by the caller', () {
      final e = mapShieldError(
        ConnectionException('GATT_ERROR'),
        op: ShieldOperation.connect,
        platform: 'android',
        nativeCode: 133,
      );
      expect(e.code, ShieldErrorCode.connectFailed);
      expect(e.nativeCode, 133);
    });

    test('UnsupportedError, ArgumentError and ShieldError', () {
      expect(
          mapShieldError(UnsupportedError('x'), op: ShieldOperation.other).code,
          ShieldErrorCode.unsupported);
      expect(mapShieldError(ArgumentError('x'), op: ShieldOperation.other).code,
          ShieldErrorCode.invalidArgument);
      const own = ShieldError(ShieldErrorCode.adapterOff, 'off');
      expect(identical(mapShieldError(own, op: ShieldOperation.read), own),
          isTrue);
    });

    test('the code enum covers the 13 port codes', () {
      const portCodes = [
        'adapterOff', 'notConnected', 'deviceNotFound', 'connectInProgress',
        'connectTimeout', 'connectFailed', 'scanAlreadyStarted', 'scanFailed',
        'characteristicNotFound', 'operationTimeout', 'gattFailed',
        'unsupported', 'unknown', //
      ];
      final names = ShieldErrorCode.values.map((c) => c.name).toSet();
      expect(names.containsAll(portCodes), isTrue);
    });
  });

  group('canonicalUuid', () {
    test('16, 32 and 128-bit input', () {
      const full = '0000180d-0000-1000-8000-00805f9b34fb';
      expect(canonicalUuid('180D'), full);
      expect(canonicalUuid('0x180d'), full);
      expect(canonicalUuid('0000180D'), full);
      expect(canonicalUuid('0000180D00001000800000805F9B34FB'), full);
      expect(canonicalUuid(full.toUpperCase()), full);
    });

    test('invalid input is a typed error', () {
      expect(
        () => canonicalUuid('xyz'),
        throwsA(isA<ShieldError>()
            .having((e) => e.code, 'code', ShieldErrorCode.invalidArgument)),
      );
    });
  });
}
