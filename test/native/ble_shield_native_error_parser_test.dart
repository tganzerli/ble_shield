import 'package:flutter_test/flutter_test.dart';
import 'package:ble_shield/src/native/ble_shield_native.g.dart';
import 'package:ble_shield/src/native/ble_shield_native_exceptions.dart';
import 'package:ble_shield/src/native/utils/ble_shield_native_error_parser.dart';

void main() {
  group(BleShieldNativeErrorParser, () {
    group('getCode', () {
      test('preserves web connection failure codes through wrapping', () {
        final error = BleShieldNativeException(
          code: BleShieldNativeErrorCode.connectionFailed,
          message:
              'Web GATT connection failed: NetworkError: Connection failed',
          details: 'NetworkError: Connection failed',
        );
        final wrapped = ConnectionException(error);
        expect(wrapped.code, BleShieldNativeErrorCode.connectionFailed);
        expect(wrapped.message, contains('NetworkError: Connection failed'));
        expect(wrapped.details, same(error));
      });

      test('classifies a Windows unreachable callback as connection failed',
          () {
        expect(
          BleShieldNativeErrorParser.getCode(
            'Failed to get services: Unreachable',
          ),
          BleShieldNativeErrorCode.connectionFailed,
        );
      });

      test('classifies a Windows access callback as unauthorized', () {
        expect(
          BleShieldNativeErrorParser.getCode(
            'Failed to get services: AccessDenied',
          ),
          BleShieldNativeErrorCode.bluetoothUnauthorized,
        );
      });

      test('classifies a missing Windows device as connection failed', () {
        expect(
          BleShieldNativeErrorParser.getCode('Failed to get device'),
          BleShieldNativeErrorCode.connectionFailed,
        );
      });

      test('classifies a Windows protocol callback as failed', () {
        expect(
          BleShieldNativeErrorParser.getCode(
            'Failed to get services: ProtocolError',
          ),
          BleShieldNativeErrorCode.failed,
        );
      });

      test('does not classify unrelated messages by substring', () {
        expect(
          BleShieldNativeErrorParser.getCode(
            'Request failed after the service became unreachable',
          ),
          BleShieldNativeErrorCode.unknownError,
        );
      });
    });

    group('extractBlueZAttErrorCode', () {
      test('reads the ATT code that follows the phrase', () {
        expect(
          BleShieldNativeErrorParser.extractBlueZAttErrorCode(
            'GDBus.Error:org.bluez.Error.Failed: Operation failed with ATT '
            'error: 0x0F',
          ),
          '15',
        );
      });

      test('prefers the ATT code over an unrelated hex value', () {
        expect(
          BleShieldNativeErrorParser.extractBlueZAttErrorCode(
            'write failed (handle 0xdead) with ATT error: 0x0f',
          ),
          '15',
        );
      });

      test('falls back to a bare hex value when the phrase is absent', () {
        expect(
          BleShieldNativeErrorParser.extractBlueZAttErrorCode(
              'error code 0x1A'),
          '26',
        );
      });

      test('returns null when the message has no code', () {
        expect(
          BleShieldNativeErrorParser.extractBlueZAttErrorCode('not connected'),
          isNull,
        );
      });
    });
  });
}
