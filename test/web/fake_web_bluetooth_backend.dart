import 'dart:async';
import 'dart:typed_data';

import 'package:ble_shield/src/web/web_bluetooth_backend.dart';

/// A scripted browser: [nextPick] is what the chooser returns.
class FakeWebBluetoothBackend implements WebBluetoothBackend {
  FakeWebBluetoothBackend({this.isSupported = true});

  @override
  bool isSupported;

  bool available = true;
  final availability = StreamController<bool>.broadcast();

  /// Returned (or thrown) by the next [requestDevice].
  Object? nextPick;
  final List<WebRequestOptions> requests = [];

  @override
  Future<bool> getAvailability() async => available;

  @override
  Stream<bool> get availabilityChanges => availability.stream;

  @override
  Future<WebDevice> requestDevice(WebRequestOptions options) async {
    requests.add(options);
    final pick = nextPick;
    if (pick is WebDevice) return pick;
    throw pick ?? StateError('no pick scripted');
  }
}

class FakeWebDevice implements WebDevice {
  FakeWebDevice(this.id, {this.name, List<FakeWebService>? services})
      : services = services ?? [];

  @override
  final String id;

  @override
  final String? name;

  final List<FakeWebService> services;

  @override
  bool isConnected = false;

  int connectCalls = 0;
  int disconnectCalls = 0;
  int discoverCalls = 0;

  /// When set, [connect] waits on it (and fails with its error, if any).
  Completer<void>? connectGate;
  Object? connectError;

  final _disconnections = StreamController<void>.broadcast();

  @override
  Future<void> connect() async {
    connectCalls++;
    final gate = connectGate;
    if (gate != null) await gate.future;
    final error = connectError;
    if (error != null) throw error;
    isConnected = true;
  }

  @override
  void disconnect() {
    disconnectCalls++;
    isConnected = false;
  }

  /// The browser reports the link dropped (`gattserverdisconnected`).
  void drop() {
    isConnected = false;
    _disconnections.add(null);
  }

  @override
  Stream<void> get disconnections => _disconnections.stream;

  @override
  Future<List<WebService>> getPrimaryServices() async {
    discoverCalls++;
    return services;
  }
}

class FakeWebService implements WebService {
  FakeWebService(this.uuid, this.characteristics);

  @override
  final String uuid;

  final List<FakeWebCharacteristic> characteristics;

  @override
  Future<List<WebCharacteristic>> getCharacteristics() async => characteristics;
}

class FakeWebCharacteristic implements WebCharacteristic {
  FakeWebCharacteristic(
    this.uuid, {
    this.properties = const WebCharacteristicProperties(
      read: true,
      write: true,
      notify: true,
    ),
    List<FakeWebDescriptor>? descriptors,
  }) : descriptors = descriptors ?? [];

  @override
  final String uuid;

  @override
  final WebCharacteristicProperties properties;

  final List<FakeWebDescriptor> descriptors;

  Uint8List value = Uint8List(0);
  final List<(Uint8List, bool)> writes = [];
  bool notifying = false;

  /// Thrown by the next GATT call, then cleared.
  Object? nextError;

  final _values = StreamController<Uint8List>.broadcast();

  void _fail() {
    final e = nextError;
    nextError = null;
    if (e != null) throw e;
  }

  void notify(List<int> bytes) => _values.add(Uint8List.fromList(bytes));

  void notifyError(Object error) => _values.addError(error);

  @override
  Future<Uint8List> readValue() async {
    _fail();
    return value;
  }

  @override
  Future<void> writeValueWithResponse(Uint8List v) async {
    _fail();
    writes.add((v, true));
  }

  @override
  Future<void> writeValueWithoutResponse(Uint8List v) async {
    _fail();
    writes.add((v, false));
  }

  @override
  Future<void> startNotifications() async {
    _fail();
    notifying = true;
  }

  @override
  Future<void> stopNotifications() async {
    _fail();
    notifying = false;
  }

  @override
  Stream<Uint8List> get valueChanges => _values.stream;

  @override
  Future<List<WebDescriptor>> getDescriptors() async => descriptors;
}

class FakeWebDescriptor implements WebDescriptor {
  FakeWebDescriptor(this.uuid);

  @override
  final String uuid;

  Uint8List value = Uint8List(0);

  @override
  Future<Uint8List> readValue() async => value;

  @override
  Future<void> writeValue(Uint8List v) async => value = v;
}
