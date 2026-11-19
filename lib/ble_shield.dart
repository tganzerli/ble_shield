/// A defensive BLE central layer for Flutter (Android, iOS, macOS, Web).
library;

export 'src/ble_shield.dart'
    show BleShield, ShieldCharacteristic, ShieldDevice, ShieldService;
export 'src/errors.dart' show ShieldError, ShieldErrorCode;
export 'src/types.dart';
export 'src/uuid.dart' show canonicalUuid;
