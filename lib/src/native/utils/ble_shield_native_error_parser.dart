import 'package:flutter/services.dart';
import 'package:ble_shield/src/native/ble_shield_native_exceptions.dart';
import 'package:ble_shield/src/native/ble_shield_native.g.dart';

/// Utility class to parse error codes from dynamic errors
class BleShieldNativeErrorParser {
  static BleShieldNativeErrorCode getCode(dynamic error) {
    if (error is BleShieldNativeException) return error.code;
    if (error is BleShieldNativeErrorCode) return error;

    if (error is PlatformException) {
      int? errorCodeInt = int.tryParse((error).code);
      if (errorCodeInt != null) {
        return BleShieldNativeErrorCode.values[errorCodeInt];
      }
    }

    if (error is num) {
      return _parseNumericErrorCode((error).toInt());
    }

    if (error is String) {
      int? errorCodeInt = int.tryParse(error);
      if (errorCodeInt != null) {
        return _parseNumericErrorCode(errorCodeInt);
      } else {
        return _parseStringErrorCode(error) ??
            BleShieldNativeErrorCode.unknownError;
      }
    }

    return BleShieldNativeErrorCode.unknownError;
  }

  /// Extracts the ATT error code from a BlueZ GATT failure message as a decimal
  /// string, e.g. `'Operation failed with ATT error: 0x90'` => `'144'`, or
  /// `null` when the message carries no code.
  ///
  /// BlueZ reports a GATT protocol error as `org.bluez.Error.Failed` with an
  /// "ATT error: 0xNN" message. The phrase is matched first (case-insensitively),
  /// so an unrelated hex value elsewhere in the message is not mistaken for the
  /// ATT code. Only when the phrase is absent is the first `0x`-prefixed hex token
  /// (lower-case prefix) used as a best-effort fallback; a message with no such
  /// token returns `null`.
  static String? extractBlueZAttErrorCode(String message) {
    final attCode = RegExp(
      r'ATT error:\s*0x([0-9a-fA-F]+)',
      caseSensitive: false,
    ).firstMatch(message)?.group(1);
    final hex =
        attCode ?? RegExp(r'0x([0-9a-fA-F]+)').firstMatch(message)?.group(1);
    if (hex == null) return null;
    final decimalValue = int.tryParse(hex, radix: 16);
    return decimalValue?.toString() ?? '0x$hex';
  }

  static BleShieldNativeErrorCode? _parseStringErrorCode(String code) {
    switch (code.toLowerCase()) {
      case 'failed to get device':
      case 'failed to get services: unreachable':
        return BleShieldNativeErrorCode.connectionFailed;
      case 'failed to get services: accessdenied':
        return BleShieldNativeErrorCode.bluetoothUnauthorized;
      case 'failed to get services: protocolerror':
        return BleShieldNativeErrorCode.failed;
      case 'notsupported':
      case 'not_supported':
        return BleShieldNativeErrorCode.notSupported;
      case 'notimplemented':
      case 'not_implemented':
        return BleShieldNativeErrorCode.notImplemented;
      case 'channel-error':
      case 'channelerror':
        return BleShieldNativeErrorCode.channelError;
      case 'failed':
        return BleShieldNativeErrorCode.failed;
      case 'bluetoothnotavailable':
      case 'bluetooth_not_available':
        return BleShieldNativeErrorCode.bluetoothNotAvailable;
      case 'bluetoothnotenabled':
      case 'bluetooth_not_enabled':
        return BleShieldNativeErrorCode.bluetoothNotEnabled;
      case 'bluetoothnotallowed':
      case 'bluetooth_not_allowed':
        return BleShieldNativeErrorCode.bluetoothNotAllowed;
      case 'bluetoothunauthorized':
      case 'bluetooth_unauthorized':
        return BleShieldNativeErrorCode.bluetoothUnauthorized;
      case 'devicedisconnected':
      case 'device_disconnected':
        return BleShieldNativeErrorCode.deviceDisconnected;
      case 'connectiontimeout':
      case 'connection_timeout':
        return BleShieldNativeErrorCode.connectionTimeout;
      case 'connectionfailed':
      case 'connection_failed':
        return BleShieldNativeErrorCode.connectionFailed;
      case 'connectionrejected':
      case 'connection_rejected':
        return BleShieldNativeErrorCode.connectionRejected;
      case 'connecting':
      case 'connectioninprogress':
      case 'connection_in_progress':
        return BleShieldNativeErrorCode.connectionInProgress;
      case 'connectionterminated':
      case 'connection_terminated':
        return BleShieldNativeErrorCode.connectionTerminated;
      case 'illegalargument':
      case 'illegal_argument':
        return BleShieldNativeErrorCode.illegalArgument;
      case 'devicenotfound':
      case 'device_not_found':
        return BleShieldNativeErrorCode.deviceNotFound;
      case 'servicenotfound':
      case 'service_not_found':
        return BleShieldNativeErrorCode.serviceNotFound;
      case 'characteristicnotfound':
      case 'characteristic_not_found':
        return BleShieldNativeErrorCode.characteristicNotFound;
      case 'invalidserviceuuid':
      case 'invalid_service_uuid':
        return BleShieldNativeErrorCode.invalidServiceUuid;
      case 'invalidcharacteristicuuid':
      case 'invalid_characteristic_uuid':
        return BleShieldNativeErrorCode.invalidCharacteristicUuid;
      case 'readfailed':
      case 'read_failed':
        return BleShieldNativeErrorCode.readFailed;
      case 'writefailed':
      case 'write_failed':
      case 'writeerror':
      case 'write_error':
        return BleShieldNativeErrorCode.writeFailed;
      case 'invalidaction':
      case 'invalid_action':
        return BleShieldNativeErrorCode.invalidAction;
      case 'operationnotsupported':
      case 'operation_not_supported':
        return BleShieldNativeErrorCode.operationNotSupported;
      case 'operationtimeout':
      case 'operation_timeout':
        return BleShieldNativeErrorCode.operationTimeout;
      case 'operationcancelled':
      case 'operation_cancelled':
        return BleShieldNativeErrorCode.operationCancelled;
      case 'inprogress':
      case 'alreadyinprogress':
      case 'already_in_progress':
        return BleShieldNativeErrorCode.operationInProgress;
      case 'notpaired':
      case 'not_paired':
        return BleShieldNativeErrorCode.notPaired;
      case 'notpairable':
      case 'not_pairable':
        return BleShieldNativeErrorCode.notPairable;
      case 'alreadypaired':
      case 'already_paired':
        return BleShieldNativeErrorCode.alreadyPaired;
      case 'pairingfailed':
      case 'pairing_failed':
        return BleShieldNativeErrorCode.pairingFailed;
      case 'pairingcancelled':
      case 'pairing_cancelled':
        return BleShieldNativeErrorCode.pairingCancelled;
      case 'pairingtimeout':
      case 'pairing_timeout':
        return BleShieldNativeErrorCode.pairingTimeout;
      case 'pairingnotallowed':
      case 'pairing_not_allowed':
        return BleShieldNativeErrorCode.pairingNotAllowed;
      case 'authenticationfailure':
      case 'authentication_failure':
        return BleShieldNativeErrorCode.authenticationFailure;
      case 'authenticationtimeout':
      case 'authentication_timeout':
      case 'authenticationnotallowed':
      case 'authentication_not_allowed':
        return BleShieldNativeErrorCode.authenticationFailure;
      case 'hardwarefailure':
      case 'hardware_failure':
      case 'toomanyconnections':
      case 'too_many_connections':
      case 'notreadytopair':
      case 'not_ready_to_pair':
      case 'nonsupportedprofiles':
      case 'no_supported_profiles':
      case 'invalidceremonydata':
      case 'invalid_ceremony_data':
      case 'requiredhandlernotregistered':
      case 'required_handler_not_registered':
      case 'rejectedbyhandler':
      case 'rejected_by_handler':
      case 'remotedevicehasassociation':
      case 'remote_device_has_association':
        return BleShieldNativeErrorCode.pairingFailed;
      case 'protectionlevelcouldnotbemet':
      case 'protection_level_could_not_be_met':
        return BleShieldNativeErrorCode.protectionLevelNotMet;
      case 'unpairingfailed':
      case 'unpairing_failed':
        return BleShieldNativeErrorCode.unpairingFailed;
      case 'alreadyunpaired':
      case 'already_unpaired':
        return BleShieldNativeErrorCode.alreadyUnpaired;
      case 'accessdenied':
      case 'access_denied':
        return BleShieldNativeErrorCode.accessDenied;
      case 'scan_failed_already_started':
      case 'scanfailedalreadystarted':
      case 'scan_failed_application_registration_failed':
      case 'scanfailedapplicationregistrationfailed':
      case 'scan_failed_feature_unsupported':
      case 'scanfailedfeatureunsupported':
      case 'scan_failed_internal_error':
      case 'scanfailedinternalerror':
      case 'scan_failed_out_of_hardware_resources':
      case 'scanfailedoutofhardwareresources':
      case 'scan_failed_scanning_too_frequently':
      case 'scanfailedscanningtoofrequently':
        return BleShieldNativeErrorCode.scanFailed;
      case 'stoppingscaninprogress':
      case 'stopping_scan_in_progress':
        return BleShieldNativeErrorCode.stoppingScanInProgress;
      case 'gatt_failure':
      case 'gattfailure':
      case 'unreachable':
      case 'protocolerror':
      case 'protocol_error':
      case 'gattunreachable':
      case 'gatt_protocol_error':
      case 'gatt_unlikely':
      case 'gattunlikely':
      case 'gatt_insufficient_resources':
      case 'gattinsufficientresources':
        return BleShieldNativeErrorCode.failed;
      case 'gatt_read_not_permitted':
      case 'gattreadnotpermitted':
        return BleShieldNativeErrorCode.readNotPermitted;
      case 'gatt_write_not_permitted':
      case 'gattwritenotpermitted':
        return BleShieldNativeErrorCode.writeNotPermitted;
      case 'gatt_insufficient_authentication':
      case 'gattinsufficientauthentication':
        return BleShieldNativeErrorCode.insufficientAuthentication;
      case 'gatt_insufficient_authorization':
      case 'gattinsufficientauthorization':
        return BleShieldNativeErrorCode.insufficientAuthorization;
      case 'gatt_insufficient_encryption':
      case 'gattinsufficientencryption':
        return BleShieldNativeErrorCode.insufficientEncryption;
      case 'gatt_insufficient_key_size':
      case 'gattinsufficientkeysize':
        return BleShieldNativeErrorCode.insufficientKeySize;
      case 'gatt_request_not_supported':
      case 'gattrequestnotsupported':
        return BleShieldNativeErrorCode.operationNotSupported;
      case 'gatt_invalid_offset':
      case 'gattinvalidoffset':
        return BleShieldNativeErrorCode.invalidOffset;
      case 'gatt_invalid_attribute_length':
      case 'gattinvalidattributelength':
        return BleShieldNativeErrorCode.invalidAttributeLength;
      case 'gatt_connection_congested':
      case 'gattconnectioncongested':
        return BleShieldNativeErrorCode.connectionFailed;
      case 'gatt_invalid_handle':
      case 'gattinvalidhandle':
        return BleShieldNativeErrorCode.invalidHandle;
      case 'gatt_invalid_pdu':
      case 'gattinvalidpdu':
        return BleShieldNativeErrorCode.invalidPdu;
      case 'gatt_prepare_queue_full':
      case 'gattpreparequeuefull':
        return BleShieldNativeErrorCode.operationInProgress;
      case 'gatt_attr_not_found':
      case 'gattattrnotfound':
        return BleShieldNativeErrorCode.serviceNotFound;
      case 'gatt_attr_not_long':
      case 'gattattrnotlong':
        return BleShieldNativeErrorCode.invalidAttributeLength;
      case 'gatt_unsupported_group':
      case 'gattunsupportedgroup':
        return BleShieldNativeErrorCode.operationNotSupported;
      case 'feature_not_configured':
      case 'featurenotconfigured':
      case 'feature_not_supported':
      case 'featurenotsupported':
      case 'feature_supported':
      case 'featuresupported':
        return BleShieldNativeErrorCode.notSupported;
      case 'error_profile_service_not_bound':
      case 'errorprofileservicenotbound':
        return BleShieldNativeErrorCode.failed;
      case 'error_missing_bluetooth_connect_permission':
      case 'errormissingbluetoothconnectpermission':
        return BleShieldNativeErrorCode.bluetoothNotAllowed;
      case 'error_device_not_bonded':
      case 'errordevicenotbonded':
        return BleShieldNativeErrorCode.notPaired;
      case 'error_gatt_write_not_allowed':
      case 'errorgattwritenotallowed':
        return BleShieldNativeErrorCode.writeNotPermitted;
      case 'error_gatt_write_request_busy':
      case 'errorgattwriterequestbusy':
        return BleShieldNativeErrorCode.writeRequestBusy;
      case 'error_unknown':
      case 'errorunknown':
        return BleShieldNativeErrorCode.unknownError;
      case 'webbluetoothgloballydisabled':
      case 'web_bluetooth_globally_disabled':
        return BleShieldNativeErrorCode.webBluetoothGloballyDisabled;
      default:
        return null;
    }
  }

  static BleShieldNativeErrorCode _parseNumericErrorCode(int code) {
    switch (code) {
      case 0x00:
        return BleShieldNativeErrorCode.unknownError;
      case 0x01:
        return BleShieldNativeErrorCode.invalidHandle;
      case 0x02:
        return BleShieldNativeErrorCode.readNotPermitted;
      case 0x03:
        return BleShieldNativeErrorCode.writeNotPermitted;
      case 0x04:
        return BleShieldNativeErrorCode.invalidPdu;
      case 0x05:
        return BleShieldNativeErrorCode.insufficientAuthentication;
      // Consolidated: gattRequestNotSupported -> operationNotSupported
      case 0x06:
        return BleShieldNativeErrorCode.operationNotSupported;
      case 0x07:
        return BleShieldNativeErrorCode.invalidOffset;
      case 0x08:
        return BleShieldNativeErrorCode.insufficientAuthorization;
      // Consolidated: gattPrepareQueueFull -> operationInProgress
      case 0x09:
        return BleShieldNativeErrorCode.operationInProgress;
      // Consolidated: gattAttrNotFound -> serviceNotFound
      case 0x0A:
        return BleShieldNativeErrorCode.serviceNotFound;
      // Consolidated: gattAttrNotLong -> invalidAttributeLength
      case 0x0B:
        return BleShieldNativeErrorCode.invalidAttributeLength;
      case 0x0C:
        return BleShieldNativeErrorCode.insufficientKeySize;
      case 0x0D:
        return BleShieldNativeErrorCode.invalidAttributeLength;
      // Consolidated: gattUnlikely -> failed
      case 0x0E:
        return BleShieldNativeErrorCode.failed;
      case 0x0F:
        return BleShieldNativeErrorCode.insufficientEncryption;
      // Consolidated: gattUnsupportedGroup -> operationNotSupported
      case 0x10:
        return BleShieldNativeErrorCode.operationNotSupported;
      // Consolidated: gattInsufficientResources -> failed
      case 0x11:
        return BleShieldNativeErrorCode.failed;
      // Consolidated: gattConnectionCongested -> connectionFailed
      case 0x85:
        return BleShieldNativeErrorCode.connectionFailed;
      // Consolidated: gattFailure -> failed
      case 0x101:
        return BleShieldNativeErrorCode.failed;
    }
    // HCI error codes - consolidated to higher-level errors
    switch (code) {
      // Connection errors
      case 0x08: // Connection Timeout
      case 0x10: // Connection Accept Timeout Exceeded
        return BleShieldNativeErrorCode.connectionTimeout;
      case 0x09: // Connection Limit Exceeded
      case 0x0A: // Synchronous Connection Limit To A Device Exceeded
        return BleShieldNativeErrorCode.connectionLimitExceeded;
      case 0x0B: // Connection Already Exists
        return BleShieldNativeErrorCode.connectionAlreadyExists;
      case 0x0D: // Connection Rejected due to Limited Resources
      case 0x0F: // Connection Rejected due to Unacceptable BD_ADDR
      case 0x39: // Connection Rejected due to No Suitable Channel Found
        return BleShieldNativeErrorCode.connectionRejected;
      case 0x0E: // Connection Rejected Due To Security Reasons
        return BleShieldNativeErrorCode.connectionRejected;
      case 0x13: // Remote User Terminated Connection
      case 0x14: // Remote Device Terminated Connection due to Low Resources
      case 0x15: // Remote Device Terminated Connection due to Power Off
      case 0x16: // Connection Terminated By Local Host
      case 0x3D: // Connection Terminated due to MIC Failure
        return BleShieldNativeErrorCode.connectionTerminated;
      case 0x3E: // Connection Failed to be Established
      case 0x3F: // MAC Connection Failed
        return BleShieldNativeErrorCode.connectionFailed;
      // Pairing/Authentication errors
      case 0x05: // Authentication Failure
        return BleShieldNativeErrorCode.authenticationFailure;
      case 0x18: // Pairing Not Allowed
        return BleShieldNativeErrorCode.pairingNotAllowed;
      case 0x03: // Hardware Failure
      case 0x29: // Pairing With Unit Key Not Supported
      case 0x37: // Secure Simple Pairing Not Supported By Host
      case 0x38: // Host Busy - Pairing
        return BleShieldNativeErrorCode.pairingFailed;
      case 0x2F: // Insufficient Security
        return BleShieldNativeErrorCode.insufficientEncryption;
      // Operation errors
      case 0x0C: // Command Disallowed
      case 0x11: // Unsupported Feature or Parameter Value
      case 0x12: // Invalid HCI Command Parameters
      case 0x1A: // Unsupported Remote Feature
      case 0x1E: // Invalid LMP Parameters
      case 0x20: // Unsupported LMP Parameter Value
        return BleShieldNativeErrorCode.operationNotSupported;
      case 0x22: // LMP Response Timeout
        return BleShieldNativeErrorCode.operationTimeout;
      // General errors
      case 0x01: // Unknown HCI Command
      case 0x02: // Unknown Connection Identifier
        return BleShieldNativeErrorCode.unknownError;
      case 0x04: // Page Timeout
        return BleShieldNativeErrorCode.connectionTimeout;
      case 0x06: // PIN or Key Missing
        return BleShieldNativeErrorCode.authenticationFailure;
      case 0x07: // Memory Capacity Exceeded
        return BleShieldNativeErrorCode.failed;
      case 0x17: // Repeated Attempts
        return BleShieldNativeErrorCode.failed;
      case 0x25: // Encryption Mode Not Acceptable
        return BleShieldNativeErrorCode.insufficientEncryption;
      case 0x26: // Link Key cannot be Changed
      case 0x27: // Requested QoS Not Supported
      case 0x2C: // QoS Unacceptable Parameter
      case 0x2D: // QoS Rejected
      case 0x2E: // Channel Classification Not Supported
      case 0x30: // Parameter Out Of Mandatory Range
      case 0x32: // Role Switch Pending
      case 0x35: // Role Switch Failed
      case 0x36: // Extended Inquiry Response Too Large
      case 0x3A: // Controller Busy
      case 0x3B: // Unacceptable Connection Parameters
      case 0x3C: // Advertising Timeout
        return BleShieldNativeErrorCode.failed;
    }
    // Default to unknown error for unmapped codes
    return BleShieldNativeErrorCode.unknownError;
  }
}
