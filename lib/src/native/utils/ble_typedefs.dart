import 'package:ble_shield/src/native/native.dart';

/// Central mode callbacks
///
typedef OnConnectionChange = void Function(BleConnectionChange change);

typedef OnValueChange = void Function(BleCharacteristicValue value);

typedef OnScanResult = void Function(BleDevice scanResult);

typedef OnAvailabilityChange = void Function(AvailabilityState state);

typedef OnPairingStateChange = void Function(String deviceId, bool isPaired);

typedef OnConnectionParametersChange = void Function(
    BleConnectionParametersChange update);

typedef OnMtuChange = void Function(String deviceId, int mtu);

typedef OnQueueUpdate = void Function(String id, int remainingQueueItems);
