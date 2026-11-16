import 'dart:async';
import 'dart:typed_data';

import 'package:ble_shield/testing.dart';

/// In-memory native platform. Installed through
/// `BleShield(platform: ...)`, which hands it to `BleShieldNative.setInstance`.
///
/// Every native entry point appends to [calls] so tests can assert order and
/// count. Behaviour is scripted through the public fields.
class FakeBlePlatform extends BleShieldPlatform {
  final List<String> calls = [];

  // ---- adapter ----
  AvailabilityState availability = AvailabilityState.poweredOn;

  /// Completes `enableBluetooth`; `null` = never completes (no Activity).
  Future<bool> Function()? onEnableBluetooth = () async => true;

  void setAvailability(AvailabilityState state) {
    availability = state;
    updateAvailability(state);
  }

  /// When set, `getBluetoothAvailabilityState` waits for it first.
  /// A never-completing future simulates a platform that never answers.
  Future<void>? availabilityGate;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    calls.add('getAvailability');
    final gate = availabilityGate;
    if (gate != null) await gate;
    return availability;
  }

  @override
  Future<bool> enableBluetooth() {
    calls.add('enableBluetooth');
    final handler = onEnableBluetooth;
    if (handler == null) return Completer<bool>().future;
    return handler();
  }

  @override
  Future<bool> disableBluetooth() async {
    calls.add('disableBluetooth');
    return true;
  }

  // ---- scan ----
  bool nativeScanning = false;
  Object? startScanError;

  /// Delay before a scripted startScan returns.
  Duration startScanDelay = Duration.zero;
  ScanFilter? lastScanFilter;
  PlatformConfig? lastScanConfig;

  int get startScanCount => calls.where((c) => c == 'startScan').length;
  int get stopScanCount => calls.where((c) => c == 'stopScan').length;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    calls.add('startScan');
    lastScanFilter = scanFilter;
    lastScanConfig = platformConfig;
    if (startScanDelay > Duration.zero) await Future.delayed(startScanDelay);
    final error = startScanError;
    if (error != null) throw error;
    nativeScanning = true;
  }

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
    nativeScanning = false;
  }

  @override
  Future<bool> isScanning() async {
    calls.add('isScanning');
    return nativeScanning;
  }

  /// The native scanner fails, as Android's `onScanFailed` does.
  void failScan(int errorCode) => updateScanFailure(errorCode);

  void advertise(
    String id, {
    String? name,
    int rssi = -60,
    List<String> services = const [],
    List<ManufacturerData> manufacturerData = const [],
    bool? connectable = true,
  }) {
    updateScanResult(BleDevice(
      deviceId: id,
      name: name,
      rssi: rssi,
      services: services,
      manufacturerDataList: manufacturerData,
      connectable: connectable,
    ));
  }

  // ---- connection ----
  final Map<String, BleConnectionState> states = {};

  /// Delay before a scripted connect succeeds.
  Duration connectDelay = Duration.zero;

  /// When set, `connect` runs this instead of the default success script.
  /// Return normally to leave the attempt pending (nothing emitted).
  Future<void> Function(String id, bool autoConnect)? onConnect;

  /// Records `(id, autoConnect)` for every native connect.
  final List<(String, bool)> connects = [];

  /// When set, `connect` throws it synchronously-async (like a pigeon error).
  Object? connectError;

  /// Native disconnect emits a disconnected event when the device was
  /// connected or connecting (cancelling a pending attempt).
  bool disconnectEmitsEvent = true;

  /// When set, the native `disconnect` throws it (the link is left as is).
  Object? disconnectError;

  // ---- diagnostics ----
  BleLogLevel? logLevel;

  @override
  Future<void> setLogLevel(BleLogLevel logLevel) async {
    calls.add('setLogLevel:${logLevel.name}');
    this.logLevel = logLevel;
  }

  void emitMtu(String id, int mtu) => updateMtu(id, mtu);

  void emitConnectionParameters(
    String id, {
    required int interval,
    int latency = 0,
    int supervisionTimeout = 500,
    int status = 0,
  }) =>
      updateConnectionParameters(BleConnectionParametersChange(
        deviceId: id,
        interval: interval,
        latency: latency,
        supervisionTimeout: supervisionTimeout,
        status: status,
      ));

  void emitConnection(
    String id,
    bool connected, {
    String? error,
    BleShieldNativeErrorCode? errorCode,
    int? nativeErrorCode,
  }) {
    states[id.toLowerCase()] = connected
        ? BleConnectionState.connected
        : BleConnectionState.disconnected;
    updateConnection(id, connected, error, errorCode, nativeErrorCode);
  }

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    calls.add('connect:$deviceId${autoConnect ? ':auto' : ''}');
    connects.add((deviceId, autoConnect));
    final error = connectError;
    if (error != null) throw error;
    final handler = onConnect;
    if (handler != null) return handler(deviceId, autoConnect);
    states[deviceId.toLowerCase()] = BleConnectionState.connecting;
    if (connectDelay > Duration.zero) await Future<void>.delayed(connectDelay);
    if (states[deviceId.toLowerCase()] == BleConnectionState.connecting) {
      emitConnection(deviceId, true);
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect:$deviceId');
    final error = disconnectError;
    if (error != null) throw error;
    final id = deviceId.toLowerCase();
    final was = states[id];
    states[id] = BleConnectionState.disconnected;
    if (disconnectEmitsEvent &&
        (was == BleConnectionState.connected ||
            was == BleConnectionState.connecting)) {
      Future<void>.delayed(Duration.zero, () => updateConnection(id, false));
    }
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async {
    calls.add('getConnectionState:$deviceId');
    return states[deviceId.toLowerCase()] ?? BleConnectionState.disconnected;
  }

  // ---- system devices ----
  List<BleDevice> systemDevices = [];
  final List<List<String>?> systemDevicesArgs = [];

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async {
    calls.add('getSystemDevices');
    systemDevicesArgs.add(withServices);
    if (withServices == null) return systemDevices;
    return systemDevices
        .where((d) => d.services.any(withServices.contains))
        .toList();
  }

  // ---- GATT ----
  final Map<String, List<BleService>> services = {};
  Duration gattDelay = Duration.zero;
  Object? gattError;

  /// Optional per-call hook to observe overlap: invoked at start and end.
  void Function(String op)? onGattStart;
  void Function(String op)? onGattEnd;

  Future<T> _gatt<T>(String op, FutureOr<T> Function() body) async {
    calls.add(op);
    onGattStart?.call(op);
    try {
      if (gattDelay > Duration.zero) await Future<void>.delayed(gattDelay);
      final error = gattError;
      if (error != null) throw error;
      return await body();
    } finally {
      onGattEnd?.call(op);
    }
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) =>
      _gatt('discover:$deviceId', () => services[deviceId.toLowerCase()] ?? []);

  final Map<String, Uint8List> readValues = {};
  final List<(String, String, List<int>, BleOutputProperty)> writes = [];
  final List<(String, String, BleInputProperty)> notifyCalls = [];

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) =>
      _gatt('read:$deviceId:$characteristic',
          () => readValues[characteristic] ?? Uint8List(0));

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) =>
      _gatt('write:$deviceId:$characteristic', () {
        writes
            .add((deviceId, characteristic, value.toList(), bleOutputProperty));
      });

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) =>
      _gatt('notify:$deviceId:$characteristic:${bleInputProperty.name}', () {
        notifyCalls.add((deviceId, characteristic, bleInputProperty));
      });

  void emitValue(String id, String characteristic, List<int> value) =>
      updateCharacteristicValue(
          id, characteristic, Uint8List.fromList(value), null);

  // ---- unused by ble_shield ----
  @override
  Future<Uint8List> readDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor, {
    Duration? timeout,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> writeDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
    Uint8List value,
  ) =>
      throw UnimplementedError();

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => expectedMtu;

  @override
  Future<int> readRssi(String deviceId) async => -50;

  @override
  Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  ) async {}

  @override
  Future<bool> isPaired(String deviceId) async => false;

  @override
  Future<bool> pair(String deviceId) async => false;

  @override
  Future<void> unpair(String deviceId) async {}
}

BleService service(String uuid, List<BleCharacteristic> characteristics) =>
    BleService(uuid, characteristics);

BleCharacteristic characteristic(
  String uuid,
  List<CharacteristicProperty> properties,
) =>
    BleCharacteristic(uuid, properties, const []);
