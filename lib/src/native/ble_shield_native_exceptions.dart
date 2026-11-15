import 'package:flutter/services.dart';
import 'package:ble_shield/src/native/ble_shield_native.g.dart';
import 'package:ble_shield/src/native/utils/ble_shield_native_error_parser.dart';

/// Base exception class for all BLE errors with typed error codes
class BleShieldNativeException implements Exception {
  final BleShieldNativeErrorCode code;
  final String message;
  final dynamic details;

  BleShieldNativeException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() =>
      "BleShieldNativeException: Code: $code, Message: $message, Details: $details";

  factory BleShieldNativeException.fromError(dynamic error) {
    String message = error.toString();
    dynamic details = error;
    if (error is PlatformException) {
      message = error.message ?? error.details?.toString() ?? error.code;
      details = error.details;
    }
    return BleShieldNativeException(
      code: BleShieldNativeErrorParser.getCode(error),
      message: message,
      details: details,
    );
  }
}

/// Exception thrown when connection-related errors occur
class ConnectionException extends BleShieldNativeException {
  ConnectionException._({
    required super.code,
    required super.message,
    super.details,
  });

  ConnectionException([dynamic error])
      : this._(
          code: BleShieldNativeErrorParser.getCode(error),
          message: _errorParser(error),
          details: error,
        );
}

/// Exception thrown when pairing-related errors occur
class PairingException extends BleShieldNativeException {
  PairingException._({
    required super.code,
    required super.message,
    super.details,
  });

  /// Legacy constructor for backward compatibility
  PairingException([dynamic error])
      : this._(
          code: BleShieldNativeErrorParser.getCode(error),
          message: _errorParser(error),
          details: error,
        );
}

/// Exception thrown when Web Bluetooth API is globally disabled
class WebBluetoothGloballyDisabled extends BleShieldNativeException {
  WebBluetoothGloballyDisabled({
    super.code = BleShieldNativeErrorCode.webBluetoothGloballyDisabled,
    required super.message,
    super.details,
  });
}

/// Legacy error parser for backward compatibility
String _errorParser(dynamic error) {
  if (error == null) {
    return "Failed";
  } else if (error is PlatformException) {
    return error.message ?? error.details ?? error.code ?? 'Unknown error';
  } else if (error is String) {
    return error;
  } else {
    return error.toString();
  }
}
