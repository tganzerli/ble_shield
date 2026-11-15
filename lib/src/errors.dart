import 'dart:async';

import 'package:flutter/services.dart';
import 'native/native.dart';

/// Typed error codes. Callers never need to parse a message.
enum ShieldErrorCode {
  /// The Bluetooth adapter is off (or became unavailable mid-operation).
  adapterOff,

  /// The operation needs a connected device.
  notConnected,

  /// The OS does not know the device.
  deviceNotFound,

  /// A `connect` is already running for this device.
  connectInProgress,

  /// `connect` did not complete within its timeout.
  connectTimeout,

  /// `connect` failed.
  connectFailed,

  /// `startScan` while a scan is running.
  scanAlreadyStarted,

  /// The scan failed to start, the native scanner failed, or the opt-in
  /// `scanWatchdog` heard no advertisement within its window.
  scanFailed,

  /// Service or characteristic is not present on the device.
  characteristicNotFound,

  /// A GATT operation did not complete within its timeout.
  operationTimeout,

  /// A GATT operation failed (read, write, subscribe, discovery).
  gattFailed,

  /// The platform cannot do this (e.g. `turnOn` on iOS).
  unsupported,

  /// Missing Bluetooth permission.
  unauthorized,

  /// The caller passed an invalid argument (e.g. a malformed UUID).
  invalidArgument,

  /// Anything else.
  unknown,
}

/// The single error type thrown or emitted by ble_shield.
class ShieldError implements Exception {
  const ShieldError(
    this.code,
    this.message, {
    this.platform,
    this.nativeCode,
  });

  final ShieldErrorCode code;
  final String message;

  /// `android` or `apple` when the error came from the native layer.
  final String? platform;

  /// Native status (e.g. Android GATT status 133), when known.
  final int? nativeCode;

  @override
  String toString() {
    final extra = [
      if (platform != null) platform!,
      if (nativeCode != null) 'native=$nativeCode',
    ];
    return 'ShieldError(${code.name}${extra.isEmpty ? '' : ', ${extra.join(', ')}'}): $message';
  }
}

/// What was being attempted when an error happened. It chooses the fallback
/// code for errors that carry no specific one.
enum ShieldOperation {
  adapter,
  scan,
  connect,
  disconnect,
  discover,
  read,
  write,
  notify,
  other,
}

ShieldErrorCode _fallbackFor(ShieldOperation op) => switch (op) {
      ShieldOperation.scan => ShieldErrorCode.scanFailed,
      ShieldOperation.connect => ShieldErrorCode.connectFailed,
      ShieldOperation.discover ||
      ShieldOperation.read ||
      ShieldOperation.write ||
      ShieldOperation.notify =>
        ShieldErrorCode.gattFailed,
      _ => ShieldErrorCode.unknown,
    };

/// Maps every error ble_shield can meet to a [ShieldError]. This is the only
/// place where raw plugin errors are interpreted.
///
/// [platform] is attached to errors that came from the native layer.
/// [nativeCode] is attached when the caller knows it (e.g. from a connection
/// change event).
ShieldError mapShieldError(
  Object error, {
  required ShieldOperation op,
  String? platform,
  int? nativeCode,
}) {
  if (error is ShieldError) return error;

  if (error is TimeoutException) {
    return ShieldError(
      op == ShieldOperation.connect
          ? ShieldErrorCode.connectTimeout
          : ShieldErrorCode.operationTimeout,
      error.message ?? 'timed out after ${error.duration}',
      nativeCode: nativeCode,
    );
  }

  if (error is BleShieldNativeException) {
    return ShieldError(
      _codeFor(error.code, op),
      error.message,
      platform: platform,
      nativeCode: nativeCode ?? _intOrNull(error.details),
    );
  }

  if (error is PlatformException) {
    return ShieldError(
      _codeFor(_parsePlatformCode(error), op),
      error.message ?? error.code,
      platform: platform,
      nativeCode: nativeCode ?? _intOrNull(error.details),
    );
  }

  if (error is UnsupportedError) {
    return ShieldError(
      ShieldErrorCode.unsupported,
      error.message ?? 'unsupported',
    );
  }

  if (error is ArgumentError || error is FormatException) {
    return ShieldError(ShieldErrorCode.invalidArgument, error.toString());
  }

  // Includes `Exception('Queue Cancelled')` from the native layer's queue.
  return ShieldError(_fallbackFor(op), error.toString(),
      nativeCode: nativeCode);
}

BleShieldNativeErrorCode _parsePlatformCode(PlatformException e) {
  final numeric = int.tryParse(e.code);
  if (numeric != null) {
    if (numeric >= 0 && numeric < BleShieldNativeErrorCode.values.length) {
      return BleShieldNativeErrorCode.values[numeric];
    }
    return BleShieldNativeErrorCode.unknownError;
  }
  try {
    final byCode = BleShieldNativeException.fromError(e.code).code;
    if (byCode != BleShieldNativeErrorCode.unknownError) return byCode;
    final message = e.message;
    if (message != null) {
      return BleShieldNativeException.fromError(message).code;
    }
  } catch (_) {
    // Fall through.
  }
  return BleShieldNativeErrorCode.unknownError;
}

int? _intOrNull(Object? value) =>
    value is int ? value : (value is String ? int.tryParse(value) : null);

ShieldErrorCode _codeFor(BleShieldNativeErrorCode code, ShieldOperation op) {
  switch (code) {
    case BleShieldNativeErrorCode.bluetoothNotEnabled:
    case BleShieldNativeErrorCode.bluetoothNotAvailable:
      return ShieldErrorCode.adapterOff;
    case BleShieldNativeErrorCode.bluetoothNotAllowed:
    case BleShieldNativeErrorCode.bluetoothUnauthorized:
    case BleShieldNativeErrorCode.accessDenied:
      return ShieldErrorCode.unauthorized;
    case BleShieldNativeErrorCode.deviceDisconnected:
    case BleShieldNativeErrorCode.connectionTerminated:
      return op == ShieldOperation.connect
          ? ShieldErrorCode.connectFailed
          : ShieldErrorCode.notConnected;
    case BleShieldNativeErrorCode.deviceNotFound:
      return ShieldErrorCode.deviceNotFound;
    case BleShieldNativeErrorCode.connectionInProgress:
      return ShieldErrorCode.connectInProgress;
    case BleShieldNativeErrorCode.connectionTimeout:
      return ShieldErrorCode.connectTimeout;
    case BleShieldNativeErrorCode.connectionFailed:
    case BleShieldNativeErrorCode.connectionRejected:
    case BleShieldNativeErrorCode.connectionLimitExceeded:
    case BleShieldNativeErrorCode.connectionAlreadyExists:
      return ShieldErrorCode.connectFailed;
    case BleShieldNativeErrorCode.scanFailed:
    case BleShieldNativeErrorCode.stoppingScanInProgress:
      return ShieldErrorCode.scanFailed;
    case BleShieldNativeErrorCode.serviceNotFound:
    case BleShieldNativeErrorCode.characteristicNotFound:
    case BleShieldNativeErrorCode.invalidServiceUuid:
    case BleShieldNativeErrorCode.invalidCharacteristicUuid:
      return ShieldErrorCode.characteristicNotFound;
    case BleShieldNativeErrorCode.operationTimeout:
      return op == ShieldOperation.connect
          ? ShieldErrorCode.connectTimeout
          : ShieldErrorCode.operationTimeout;
    case BleShieldNativeErrorCode.notSupported:
    case BleShieldNativeErrorCode.notImplemented:
    case BleShieldNativeErrorCode.operationNotSupported:
      return ShieldErrorCode.unsupported;
    case BleShieldNativeErrorCode.illegalArgument:
      return ShieldErrorCode.invalidArgument;
    case BleShieldNativeErrorCode.invalidOffset:
    case BleShieldNativeErrorCode.invalidAttributeLength:
    case BleShieldNativeErrorCode.invalidPdu:
    case BleShieldNativeErrorCode.invalidHandle:
    case BleShieldNativeErrorCode.readFailed:
    case BleShieldNativeErrorCode.readNotPermitted:
    case BleShieldNativeErrorCode.writeFailed:
    case BleShieldNativeErrorCode.writeNotPermitted:
    case BleShieldNativeErrorCode.writeRequestBusy:
    case BleShieldNativeErrorCode.invalidAction:
    case BleShieldNativeErrorCode.operationCancelled:
    case BleShieldNativeErrorCode.operationInProgress:
    case BleShieldNativeErrorCode.characteristicDoesNotSupportRead:
    case BleShieldNativeErrorCode.characteristicDoesNotSupportWrite:
    case BleShieldNativeErrorCode
          .characteristicDoesNotSupportWriteWithoutResponse:
    case BleShieldNativeErrorCode.characteristicDoesNotSupportNotify:
    case BleShieldNativeErrorCode.characteristicDoesNotSupportIndicate:
    case BleShieldNativeErrorCode.insufficientAuthentication:
    case BleShieldNativeErrorCode.insufficientAuthorization:
    case BleShieldNativeErrorCode.insufficientEncryption:
    case BleShieldNativeErrorCode.insufficientKeySize:
    case BleShieldNativeErrorCode.authenticationFailure:
    case BleShieldNativeErrorCode.protectionLevelNotMet:
      return op == ShieldOperation.connect
          ? ShieldErrorCode.connectFailed
          : ShieldErrorCode.gattFailed;
    default:
      return _fallbackFor(op);
  }
}
