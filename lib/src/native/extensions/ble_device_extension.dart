import 'package:ble_shield/src/native/utils/cache_handler.dart';
import 'package:ble_shield/src/native/native.dart';

/// Extension methods for [BleDevice] to simplify common operations.
extension BleDeviceExtension on BleDevice {
  /// A stream of [bool] that emits connection status changes for the device.
  Stream<bool> get connectionStream =>
      BleShieldNative.connectionStream(deviceId);

  /// A stream of [BleConnectionChange] that emits connection status changes
  /// together with the platform's error message and code.
  Stream<BleConnectionChange> get connectionChangeStream =>
      BleShieldNative.connectionChangeStream(deviceId);

  /// A stream of [bool] that emits pairing status changes for the device.
  Stream<bool> get pairingStateStream =>
      BleShieldNative.pairingStateStream(deviceId);

  /// Checks if the device is currently connected.
  Future<bool> get isConnected async =>
      await BleShieldNative.getConnectionState(deviceId) ==
      BleConnectionState.connected;

  /// Connects to the device.
  /// [autoConnect] enables automatic reconnection when the device becomes available.
  /// [platformConfig] sets platform specific connection options.
  Future<void> connect({
    bool autoConnect = false,
    Duration? timeout,
    ConnectionPlatformConfig? platformConfig,
  }) =>
      BleShieldNative.connect(
        deviceId,
        autoConnect: autoConnect,
        timeout: timeout,
        platformConfig: platformConfig,
      );

  /// Disconnects from the device.
  Future<void> disconnect({Duration? timeout, String? queueId}) =>
      BleShieldNative.disconnect(deviceId, timeout: timeout, queueId: queueId);

  /// Requests an MTU (Maximum Transmission Unit) value for the connection.
  ///
  /// **⚠️ Note:** Requesting an MTU is a *best-effort* operation. The final MTU is
  /// often controlled by the OS and remote device. Returns the negotiated MTU value,
  /// which may differ from `expectedMtu`. Concurrent requests for the same device
  /// share a single negotiation.
  ///
  /// On iOS/macOS and Linux the device's services are discovered on demand
  /// first, because the reported MTU is only meaningful once they are known
  /// (CoreBluetooth otherwise reports the default ATT MTU, 23). This is a no-op
  /// when [discoverServices] already ran.
  ///
  /// See [BleShieldNative.requestMtu] for platform limitations and best practices.
  Future<int> requestMtu(int expectedMtu, {String? queueId}) =>
      BleShieldNative.requestMtu(deviceId, expectedMtu, queueId: queueId);

  /// Check if a device is paired.
  ///
  /// For `Apple` and `Web`, you have to pass a "pairingCommand" with an encrypted read or write characteristic.
  /// Returns true/false if it manages to execute the command.
  /// Returns null when no `pairingCommand` is passed.
  /// Note that it will trigger pairing if the device is not already paired.
  Future<bool?> isPaired({
    BleCommand? pairingCommand,
    Duration? timeout,
    String? queueId,
  }) {
    return BleShieldNative.isPaired(
      deviceId,
      pairingCommand: pairingCommand,
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Pair a device.
  ///
  /// It throws error if pairing fails.
  ///
  /// On `Apple` and `Web`, it only works on devices with encrypted characteristics.
  /// It is advised to pass a pairingCommand with an encrypted read or write characteristic.
  /// When not passing a pairingCommand, you should afterwards use [isPaired] with a pairingCommand
  /// to verify the pairing state.
  ///
  /// On `Web/Windows` and `Web/Linux`, it does not work for devices that use `ConfirmOnly` pairing.
  /// Can throw `PairingException`, `ConnectionException` or `PlatformException`.
  Future<void> pair({
    BleCommand? pairingCommand,
    Duration? timeout,
    String? queueId,
  }) {
    return BleShieldNative.pair(
      deviceId,
      pairingCommand: pairingCommand,
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Unpair a device.
  ///
  /// It might throw an error if device is not paired.
  Future<void> unpair({Duration? timeout, String? queueId}) =>
      BleShieldNative.unpair(deviceId, timeout: timeout, queueId: queueId);

  /// Discovers the services offered by the device.
  ///
  /// Returns cached services if already discovered after connection.
  /// [timeout] bounds the call, and on Apple the native discovery too (see
  /// [BleShieldNative.discoverServices]).
  /// [platformConfig]: platform-specific options, e.g. Android's `clearGattCache`.
  Future<List<BleService>> discoverServices({
    Duration? timeout,
    bool withDescriptors = false,
    String? queueId,
    DiscoverServicesPlatformConfig? platformConfig,
  }) async {
    List<BleService> servicesCache = await BleShieldNative.discoverServices(
      deviceId,
      withDescriptors: withDescriptors,
      timeout: timeout,
      queueId: queueId,
      platformConfig: platformConfig,
    );
    CacheHandler.instance.saveServices(
      BleShieldNative.canonicalDeviceId(deviceId),
      servicesCache,
    );
    return servicesCache;
  }

  /// Retrieves a specific service.
  ///
  /// [service] is the UUID of the service.
  /// [preferCached] indicates whether to use cached services. If cache is empty, discoverServices() will be called.
  /// might throw [BleShieldNativeException]
  Future<BleService> getService(
    String service, {
    bool preferCached = true,
    Duration? timeout,
    String? queueId,
  }) async {
    List<BleService> discoveredServices = [];
    if (preferCached) {
      discoveredServices = CacheHandler.instance.getServices(
            BleShieldNative.canonicalDeviceId(deviceId),
          ) ??
          [];
    }
    if (discoveredServices.isEmpty) {
      discoveredServices = await discoverServices(
        timeout: timeout,
        queueId: queueId,
      );
    }

    if (discoveredServices.isEmpty) {
      throw BleShieldNativeException(
        code: BleShieldNativeErrorCode.serviceNotFound,
        message: 'No services found',
      );
    }

    return discoveredServices.firstWhere(
      (s) => BleUuidParser.compareStrings(s.uuid, service),
      orElse: () => throw BleShieldNativeException(
        code: BleShieldNativeErrorCode.serviceNotFound,
        message: 'Service "$service" not available',
      ),
    );
  }

  /// Retrieves a specific characteristic from a service.
  ///
  /// [service] is the UUID of the service.
  /// [characteristic] is the UUID of the characteristic.
  /// [preferCached] indicates whether to use cached services. If cache is empty, discoverServices() will be called.
  /// might throw [BleShieldNativeException]
  Future<BleCharacteristic> getCharacteristic(
    String characteristic, {
    required String service,
    bool preferCached = true,
    Duration? timeout,
    String? queueId,
  }) async {
    BleService bluetoothService = await getService(
      service,
      preferCached: preferCached,
      timeout: timeout,
      queueId: queueId,
    );
    return bluetoothService.getCharacteristic(characteristic);
  }
}
