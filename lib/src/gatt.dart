part of 'ble_shield.dart';

/// A discovered GATT service.
class ShieldService {
  ShieldService._(this.uuid, this.characteristics);

  /// Canonical 128-bit lower-case UUID.
  final String uuid;
  final List<ShieldCharacteristic> characteristics;

  @override
  String toString() => 'ShieldService($uuid, ${characteristics.length} chars)';
}

/// A GATT characteristic of a discovered service.
///
/// It is a handle (device + UUIDs): it keeps working after a reconnection,
/// but [ShieldDevice.discoverServices] returns fresh objects per connection.
class ShieldCharacteristic {
  ShieldCharacteristic._(
    this._device,
    this.serviceUuid,
    this.uuid,
    Iterable<CharacteristicProperty> properties,
  ) : _properties = properties.toSet();

  final ShieldDevice _device;
  final Set<CharacteristicProperty> _properties;

  /// Canonical 128-bit lower-case UUIDs.
  final String uuid;
  final String serviceUuid;

  String get remoteId => _device.remoteId;

  bool get canRead => _properties.contains(CharacteristicProperty.read);

  /// Write with or without response.
  bool get canWrite =>
      _properties.contains(CharacteristicProperty.write) ||
      _properties.contains(CharacteristicProperty.writeWithoutResponse);

  bool get canWriteWithResponse =>
      _properties.contains(CharacteristicProperty.write);

  bool get canWriteWithoutResponse =>
      _properties.contains(CharacteristicProperty.writeWithoutResponse);

  /// Notify OR indicate. [setNotify] picks the mode.
  bool get canNotify => supportsNotify || supportsIndicate;

  bool get supportsNotify =>
      _properties.contains(CharacteristicProperty.notify);

  bool get supportsIndicate =>
      _properties.contains(CharacteristicProperty.indicate);

  /// True after a successful `setNotify(true)` on the current connection.
  bool get isNotifying => _device._notifying.contains(_key);

  String get _key => '$serviceUuid/$uuid';

  /// Reads the value. Runs under the global GATT lock.
  Future<List<int>> read({Duration? timeout}) async {
    final t = timeout ?? _device._shield.gattTimeout;
    final value = await _device._gatt(
      ShieldOperation.read,
      () => BleShieldNative.read(remoteId, serviceUuid, uuid, timeout: t),
    );
    return value.toList();
  }

  /// Writes [value], with response unless [withoutResponse].
  Future<void> write(
    List<int> value, {
    bool withoutResponse = false,
    Duration? timeout,
  }) {
    final t = timeout ?? _device._shield.gattTimeout;
    return _device._gatt(
      ShieldOperation.write,
      () => BleShieldNative.write(
        remoteId,
        serviceUuid,
        uuid,
        Uint8List.fromList(value),
        withoutResponse: withoutResponse,
        timeout: t,
      ),
    );
  }

  /// Subscribes or unsubscribes. Uses notifications when the characteristic
  /// supports them, otherwise indications. Throws
  /// [ShieldErrorCode.unsupported] when it supports neither, and
  /// [ShieldErrorCode.operationTimeout] after [timeout].
  Future<void> setNotify(
    bool enabled, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!enabled) {
      await _device._gatt(
        ShieldOperation.notify,
        () => BleShieldNative.unsubscribe(remoteId, serviceUuid, uuid,
            timeout: timeout),
      );
      _device._notifying.remove(_key);
      return;
    }
    if (!canNotify) {
      throw ShieldError(
        ShieldErrorCode.unsupported,
        'characteristic $uuid supports neither notify nor indicate',
      );
    }
    await _device._gatt(
      ShieldOperation.notify,
      () => supportsNotify
          ? BleShieldNative.subscribeNotifications(remoteId, serviceUuid, uuid,
              timeout: timeout)
          : BleShieldNative.subscribeIndications(remoteId, serviceUuid, uuid,
              timeout: timeout),
    );
    _device._notifying.add(_key);
  }

  /// Values received for this characteristic of this device only.
  ///
  /// The native layer keys values by device and characteristic UUID, not by
  /// service: two services exposing the same characteristic UUID on one
  /// device share this stream.
  Stream<List<int>> get onValueReceived =>
      BleShieldNative.characteristicValueStream(remoteId, uuid)
          .map((v) => v.toList());

  @override
  String toString() => 'ShieldCharacteristic($uuid of $serviceUuid)';
}
