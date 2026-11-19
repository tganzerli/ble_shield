import 'dart:async';
import 'dart:typed_data';

/// The browser's Web Bluetooth API, as plain Dart.
///
/// [BleShieldNativeWeb] holds all of the Web logic and talks to the browser
/// only through these interfaces, so it runs (and is tested) on the Dart VM.
/// The `dart:js_interop` implementation lives in
/// `js_web_bluetooth_backend.dart` and is compiled only for the web.
///
/// Every failure the browser reports is surfaced as a [WebBluetoothError].
abstract interface class WebBluetoothBackend {
  /// Whether `navigator.bluetooth` exists in this browser and context.
  bool get isSupported;

  /// `navigator.bluetooth.getAvailability()`.
  Future<bool> getAvailability();

  /// `availabilitychanged` events on `navigator.bluetooth`.
  Stream<bool> get availabilityChanges;

  /// `navigator.bluetooth.requestDevice(options)`: opens the chooser.
  Future<WebDevice> requestDevice(WebRequestOptions options);
}

/// A `BluetoothDevice` the user granted through the chooser.
abstract interface class WebDevice {
  /// The browser's opaque, case-sensitive id.
  String get id;

  String? get name;

  /// `device.gatt.connected`.
  bool get isConnected;

  /// `device.gatt.connect()`.
  Future<void> connect();

  /// `device.gatt.disconnect()`.
  void disconnect();

  /// `gattserverdisconnected` events.
  Stream<void> get disconnections;

  /// `device.gatt.getPrimaryServices()`.
  Future<List<WebService>> getPrimaryServices();
}

/// A `BluetoothRemoteGATTService`.
abstract interface class WebService {
  String get uuid;

  Future<List<WebCharacteristic>> getCharacteristics();
}

/// A `BluetoothRemoteGATTCharacteristic`.
abstract interface class WebCharacteristic {
  String get uuid;

  WebCharacteristicProperties get properties;

  Future<Uint8List> readValue();

  Future<void> writeValueWithResponse(Uint8List value);

  Future<void> writeValueWithoutResponse(Uint8List value);

  Future<void> startNotifications();

  Future<void> stopNotifications();

  /// `characteristicvaluechanged` events, as the characteristic's new value.
  Stream<Uint8List> get valueChanges;

  Future<List<WebDescriptor>> getDescriptors();
}

/// A `BluetoothRemoteGATTDescriptor`.
abstract interface class WebDescriptor {
  String get uuid;

  Future<Uint8List> readValue();

  Future<void> writeValue(Uint8List value);
}

/// `BluetoothCharacteristicProperties`.
class WebCharacteristicProperties {
  const WebCharacteristicProperties({
    this.broadcast = false,
    this.read = false,
    this.write = false,
    this.writeWithoutResponse = false,
    this.notify = false,
    this.indicate = false,
    this.authenticatedSignedWrites = false,
  });

  final bool broadcast;
  final bool read;
  final bool write;
  final bool writeWithoutResponse;
  final bool notify;
  final bool indicate;
  final bool authenticatedSignedWrites;
}

/// One `BluetoothLEScanFilter` of the chooser options.
class WebRequestFilter {
  const WebRequestFilter({
    this.services,
    this.namePrefix,
    this.manufacturerData,
  });

  final List<String>? services;
  final String? namePrefix;
  final List<WebManufacturerDataFilter>? manufacturerData;
}

/// One `manufacturerData` entry of a [WebRequestFilter].
class WebManufacturerDataFilter {
  const WebManufacturerDataFilter({
    required this.companyIdentifier,
    this.dataPrefix,
    this.mask,
  });

  final int companyIdentifier;
  final Uint8List? dataPrefix;
  final Uint8List? mask;
}

/// The `RequestDeviceOptions` dictionary.
///
/// With no [filters] and no [exclusionFilters], the chooser lists every
/// device (`acceptAllDevices: true`).
class WebRequestOptions {
  const WebRequestOptions({
    this.filters = const [],
    this.exclusionFilters = const [],
    this.optionalServices = const [],
    this.optionalManufacturerData = const [],
  });

  final List<WebRequestFilter> filters;
  final List<WebRequestFilter> exclusionFilters;
  final List<String> optionalServices;
  final List<int> optionalManufacturerData;

  bool get acceptAllDevices => filters.isEmpty && exclusionFilters.isEmpty;
}

/// A rejected Web Bluetooth call: the `DOMException`'s [name]
/// (`NotFoundError`, `SecurityError`, `NetworkError`, `NotSupportedError`,
/// `InvalidStateError`, ...) and [message].
class WebBluetoothError implements Exception {
  const WebBluetoothError(this.name, this.message);

  final String name;
  final String message;

  @override
  String toString() => '$name: $message';
}
