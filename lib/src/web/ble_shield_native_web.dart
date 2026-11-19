import 'dart:async';
import 'dart:typed_data';

import 'package:ble_shield/src/native/native.dart';
import 'package:ble_shield/src/native/utils/universal_logger.dart';
import 'package:ble_shield/src/web/web_bluetooth_backend.dart';

/// The Web Bluetooth implementation of the native layer.
///
/// Ported from universal_ble's `universal_ble_web.dart` (BSD-3, see NOTICE),
/// with the browser behind [WebBluetoothBackend] instead of
/// `flutter_web_bluetooth`, so this class has no JS dependency and runs on the
/// Dart VM in tests.
///
/// Web Bluetooth has no free scan: a device becomes known only when the user
/// picks it in the browser's chooser ([requestDevice]). [startScan] therefore
/// throws `notSupported`.
class BleShieldNativeWeb extends BleShieldNativePlatform {
  BleShieldNativeWeb(this._backend) {
    if (_backend.isSupported) {
      _availabilitySub = _backend.availabilityChanges.listen(
        (available) => updateAvailability(
          available
              ? AvailabilityState.poweredOn
              : AvailabilityState.poweredOff,
        ),
        onError: (Object e) =>
            UniversalLogger.logError('WebAvailabilityError: $e'),
      );
    }
  }

  final WebBluetoothBackend _backend;
  StreamSubscription<bool>? _availabilitySub;

  /// Devices the chooser returned, by the browser's own id. Never pruned: the
  /// browser keeps the grant for the page's lifetime, and a disconnected
  /// device must stay connectable.
  final Map<String, WebDevice> _devices = {};
  final Map<String, StreamSubscription<void>> _disconnectSubs = {};
  final Map<_CharacteristicKey, StreamSubscription<Uint8List>> _notifySubs = {};
  final Map<String, List<_Service>> _serviceCache = {};
  final Map<String, Completer<void>> _connectCancellations = {};
  final Map<String, Future<void>> _disconnectOperations = {};
  final Map<String, int> _generations = {};

  /// How long a cancelled connect keeps its reservation when the browser's
  /// `gatt.connect()` does not settle, so a retry does not overlap it.
  static const connectionCancellationGrace = Duration(seconds: 5);

  /// Web Bluetooth ids are opaque, case-sensitive browser tokens, not
  /// addresses: they are emitted and matched verbatim.
  @override
  bool get hasAddressDeviceIds => false;

  /// Cancels the listeners this instance holds. For tests.
  Future<void> dispose() async {
    await _availabilitySub?.cancel();
    for (final sub in _disconnectSubs.values) {
      await sub.cancel();
    }
    for (final sub in _notifySubs.values) {
      await sub.cancel();
    }
    _disconnectSubs.clear();
    _notifySubs.clear();
  }

  // ------------------------------------------------------------- adapter

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    if (!_backend.isSupported) return AvailabilityState.unsupported;
    try {
      return await _backend.getAvailability()
          ? AvailabilityState.poweredOn
          : AvailabilityState.poweredOff;
    } catch (e) {
      UniversalLogger.logError('WebGetAvailabilityError: $e');
      return AvailabilityState.unknown;
    }
  }

  @override
  Future<bool> enableBluetooth() => _unsupported('enableBluetooth');

  @override
  Future<bool> disableBluetooth() => _unsupported('disableBluetooth');

  // ---------------------------------------------------------------- scan

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) =>
      _unsupported(
        'startScan',
        'Web Bluetooth has no free scan; use requestDevice to open the '
            "browser's device chooser",
      );

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isScanning() async => false;

  @override
  bool receivesAdvertisements(String deviceId) => false;

  @override
  Future<BleDevice> requestDevice({
    ScanFilter? scanFilter,
    PickerPlatformConfig? platformConfig,
  }) async {
    if (!_backend.isSupported) {
      throw _WebException(
        BleShieldNativeErrorCode.notSupported,
        'Web Bluetooth is not available in this browser or context',
      );
    }
    final options = requestOptionsFor(scanFilter, platformConfig?.web);
    final WebDevice device;
    try {
      device = await _backend.requestDevice(options);
    } catch (e) {
      throw _mapError(e, _Op.chooser);
    }
    _devices[device.id] = device;
    final now = DateTime.now().microsecondsSinceEpoch;
    return BleDevice(
      deviceId: device.id,
      name: device.name,
      timestamp: now ~/ Duration.microsecondsPerMillisecond,
      timestampMicroseconds: now,
    );
  }

  /// Translates a scan filter and [WebOptions] into the chooser's options.
  ///
  /// Services from the filter are also requested as optional services unless
  /// [webOptions] names its own, because the browser blocks GATT access to any
  /// service the page did not ask for. Filters the chooser cannot express
  /// throw `illegalArgument` rather than silently widen the match.
  static WebRequestOptions requestOptionsFor(
    ScanFilter? scanFilter,
    WebOptions? webOptions,
  ) {
    if (scanFilter != null && scanFilter.withServiceData.isNotEmpty) {
      throw _WebException(
        BleShieldNativeErrorCode.illegalArgument,
        "the browser's device chooser cannot filter on service data",
      );
    }
    final filters = <WebRequestFilter>[];
    final optionalServices = <String>[
      ...?webOptions?.optionalServices.toValidUUIDList(),
    ];
    final optionalManufacturerData = <int>[
      ...?webOptions?.optionalManufacturerData,
    ];
    final ownServices = webOptions?.optionalServices.isNotEmpty ?? false;
    final ownManufacturers =
        webOptions?.optionalManufacturerData.isNotEmpty ?? false;

    for (final service
        in scanFilter?.withServices.toValidUUIDList() ?? const <String>[]) {
      filters.add(WebRequestFilter(services: [service]));
      if (!ownServices && !optionalServices.contains(service)) {
        optionalServices.add(service);
      }
    }
    for (final m in scanFilter?.withManufacturerData ??
        const <ManufacturerDataFilter>[]) {
      filters.add(WebRequestFilter(manufacturerData: [_manufacturer(m)]));
      if (!ownManufacturers &&
          !optionalManufacturerData.contains(m.companyIdentifier)) {
        optionalManufacturerData.add(m.companyIdentifier);
      }
    }
    for (final prefix in scanFilter?.withNamePrefix ?? const <String>[]) {
      filters.add(WebRequestFilter(namePrefix: prefix));
    }

    final exclusions = [
      for (final e in scanFilter?.exclusionFilters ?? const <ExclusionFilter>[])
        if (e.hasValidFilters)
          WebRequestFilter(
            services: e.services.isEmpty ? null : e.services.toValidUUIDList(),
            namePrefix: e.namePrefix,
            manufacturerData: e.manufacturerDataFilter.isEmpty
                ? null
                : e.manufacturerDataFilter.map(_manufacturer).toList(),
          ),
    ];
    if (filters.isEmpty && exclusions.isNotEmpty) {
      throw _WebException(
        BleShieldNativeErrorCode.illegalArgument,
        "the browser's device chooser needs an inclusion filter "
        '(services, name prefix or manufacturer data) to use exclusions',
      );
    }
    if (optionalServices.isEmpty && filters.isEmpty) {
      UniversalLogger.logWarning(
        'requestDevice on web without services: the browser blocks GATT '
        'access to services the page did not list',
      );
    }
    return WebRequestOptions(
      filters: filters,
      exclusionFilters: exclusions,
      optionalServices: optionalServices,
      optionalManufacturerData: optionalManufacturerData,
    );
  }

  static WebManufacturerDataFilter _manufacturer(ManufacturerDataFilter m) =>
      WebManufacturerDataFilter(
        companyIdentifier: m.companyIdentifier,
        dataPrefix: m.payloadPrefix,
        mask: m.payloadMask,
      );

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) =>
      _unsupported('getSystemDevices');

  // ---------------------------------------------------------- connection

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      _devices[deviceId]?.isConnected ?? false
          ? BleConnectionState.connected
          : BleConnectionState.disconnected;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    // autoConnect and platformConfig have no equivalent on the web.
    final device = _devices[deviceId];
    if (device == null) {
      throw _WebException(
        BleShieldNativeErrorCode.deviceNotFound,
        '$deviceId was not returned by requestDevice in this page',
      );
    }
    if (_connectCancellations.containsKey(deviceId) ||
        _disconnectOperations.containsKey(deviceId)) {
      throw _WebException(
        BleShieldNativeErrorCode.connectionInProgress,
        'a connection operation is already in progress for $deviceId',
      );
    }
    final generation = _bump(deviceId);
    _serviceCache.remove(deviceId);
    final cancellation = Completer<void>();
    _connectCancellations[deviceId] = cancellation;
    unawaited(cancellation.future.then((_) async {
      await Future<void>.delayed(connectionCancellationGrace);
      if (identical(_connectCancellations[deviceId], cancellation)) {
        _connectCancellations.remove(deviceId);
      }
    }));

    // The reservation lasts until setup settles (or the grace above expires).
    final setup =
        _connectDevice(device, generation, cancellation).whenComplete(() {
      if (identical(_connectCancellations[deviceId], cancellation)) {
        _connectCancellations.remove(deviceId);
      }
    });
    final result = Future.any<void>([
      setup,
      cancellation.future.then<void>((_) => throw _WebException(
            BleShieldNativeErrorCode.deviceDisconnected,
            '$deviceId disconnected during connection setup',
          )),
    ]);
    try {
      await (connectionTimeout == null
          ? result
          : result.timeout(connectionTimeout));
    } catch (error) {
      // An old attempt must never disconnect or clear a newer session.
      if (_generations[deviceId] == generation) {
        _clean(deviceId);
        device.disconnect();
      }
      if (error is TimeoutException) {
        throw _WebException(
          BleShieldNativeErrorCode.connectionTimeout,
          'connection to $deviceId timed out',
        );
      }
      throw _mapError(error, _Op.connect);
    }
  }

  Future<void> _connectDevice(
    WebDevice device,
    int generation,
    Completer<void> cancellation,
  ) async {
    final id = device.id;
    await _disconnectSubs.remove(id)?.cancel();
    _assertGeneration(id, generation);
    await device.connect();
    if (_generations[id] != generation) {
      // A newer attempt or a disconnect took over. Drop the link this attempt
      // opened unless a newer pending attempt or tracked connection owns it.
      final owner = _connectCancellations[id];
      final newerPending = owner != null &&
          !identical(owner, cancellation) &&
          !owner.isCompleted;
      if (!newerPending && !_disconnectSubs.containsKey(id)) {
        device.disconnect();
      }
    }
    _assertGeneration(id, generation);
    _disconnectSubs[id] = device.disconnections.listen(
      (_) {
        if (_generations[id] != generation) return;
        _clean(id);
        updateConnection(id, false);
      },
      onError: (Object e) =>
          UniversalLogger.logError('WebDisconnectionError: $e'),
    );
    updateConnection(id, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final existing = _disconnectOperations[deviceId];
    if (existing != null) return existing;
    final operation = _disconnectDevice(deviceId);
    _disconnectOperations[deviceId] = operation;
    try {
      await operation;
    } finally {
      if (identical(_disconnectOperations[deviceId], operation)) {
        _disconnectOperations.remove(deviceId)?.ignore();
      }
      // Cleanup has finished; callbacks may now start another connection.
      updateConnection(deviceId, false);
    }
  }

  Future<void> _disconnectDevice(String deviceId) async {
    _bump(deviceId);
    final cancellation = _connectCancellations[deviceId];
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    // Abort a pending native connect before waiting for listener cleanup.
    _devices[deviceId]?.disconnect();
    _serviceCache.remove(deviceId);
    await _disconnectSubs.remove(deviceId)?.cancel();
    await _cancelNotifications(deviceId);
  }

  /// A drop or a failed connect: invalidates every attempt in flight and
  /// forgets the per-connection state.
  void _clean(String deviceId) {
    _bump(deviceId);
    final cancellation = _connectCancellations[deviceId];
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final sub = _disconnectSubs.remove(deviceId);
    if (sub != null) unawaited(sub.cancel());
    unawaited(_cancelNotifications(deviceId));
    _serviceCache.remove(deviceId);
  }

  Future<void> _cancelNotifications(String deviceId) async {
    final keys = _notifySubs.keys
        .where((k) => k.deviceId == deviceId)
        .toList(growable: false);
    for (final key in keys) {
      await _notifySubs.remove(key)?.cancel();
    }
  }

  int _bump(String deviceId) =>
      _generations[deviceId] = (_generations[deviceId] ?? 0) + 1;

  void _assertGeneration(String deviceId, int generation) {
    if ((_generations[deviceId] ?? 0) == generation) return;
    throw _WebException(
      BleShieldNativeErrorCode.deviceDisconnected,
      '$deviceId disconnected during GATT setup',
    );
  }

  // ---------------------------------------------------------------- GATT

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async {
    final generation = _generations[deviceId] ?? 0;
    final services = <BleService>[];
    for (final service in await _services(deviceId)) {
      services.add(await service.toBleService(deviceId, withDescriptors));
      _assertGeneration(deviceId, generation);
    }
    return services;
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    final c = await _characteristic(deviceId, service, characteristic);
    final key = _CharacteristicKey(
      deviceId,
      BleUuidParser.string(service),
      BleUuidParser.string(characteristic),
    );
    try {
      if (bleInputProperty == BleInputProperty.disabled) {
        await c.stopNotifications();
        await _notifySubs.remove(key)?.cancel();
        return;
      }
      await _notifySubs.remove(key)?.cancel();
      await c.startNotifications();
      _notifySubs[key] = c.valueChanges.listen(
        (value) => updateCharacteristicValue(
          deviceId,
          characteristic,
          value,
          DateTime.now().millisecondsSinceEpoch,
        ),
        onError: (Object e) =>
            UniversalLogger.logError('WebNotificationError: $e'),
      );
    } catch (e) {
      throw _mapError(e, _Op.gatt);
    }
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    final c = await _characteristic(deviceId, service, characteristic);
    try {
      final read = c.readValue();
      return await (timeout == null ? read : read.timeout(timeout));
    } on TimeoutException {
      throw _WebException(
        BleShieldNativeErrorCode.operationTimeout,
        'read of $characteristic timed out',
      );
    } catch (e) {
      throw _mapError(e, _Op.gatt);
    }
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    final c = await _characteristic(deviceId, service, characteristic);
    final copy = Uint8List.fromList(value);
    try {
      if (bleOutputProperty == BleOutputProperty.withResponse) {
        await c.writeValueWithResponse(copy);
      } else {
        await c.writeValueWithoutResponse(copy);
      }
    } catch (e) {
      throw _mapError(e, _Op.gatt);
    }
  }

  @override
  Future<Uint8List> readDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor, {
    Duration? timeout,
  }) async {
    final d = await _descriptor(deviceId, service, characteristic, descriptor);
    try {
      final read = d.readValue();
      return await (timeout == null ? read : read.timeout(timeout));
    } on TimeoutException {
      throw _WebException(
        BleShieldNativeErrorCode.operationTimeout,
        'read of descriptor $descriptor timed out',
      );
    } catch (e) {
      throw _mapError(e, _Op.gatt);
    }
  }

  @override
  Future<void> writeDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
    Uint8List value,
  ) async {
    final d = await _descriptor(deviceId, service, characteristic, descriptor);
    try {
      await d.writeValue(Uint8List.fromList(value));
    } catch (e) {
      throw _mapError(e, _Op.gatt);
    }
  }

  /// Services and their characteristics, cached per connection.
  Future<List<_Service>> _services(String deviceId) async {
    final device = _devices[deviceId];
    if (device == null) {
      throw _WebException(
        BleShieldNativeErrorCode.deviceNotFound,
        '$deviceId was not returned by requestDevice in this page',
      );
    }
    final cached = _serviceCache[deviceId];
    if (cached != null && cached.isNotEmpty) return cached;
    final generation = _generations[deviceId] ?? 0;
    final services = <_Service>[];
    try {
      final discovered = await device.getPrimaryServices();
      _assertGeneration(deviceId, generation);
      for (final service in discovered) {
        services.add(_Service(service, await service.getCharacteristics()));
        _assertGeneration(deviceId, generation);
      }
    } catch (e) {
      throw _mapError(e, _Op.gatt);
    }
    _serviceCache[deviceId] = services;
    return services;
  }

  Future<WebCharacteristic> _characteristic(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    for (final s in await _services(deviceId)) {
      if (!BleUuidParser.compareStrings(s.service.uuid, service)) continue;
      for (final c in s.characteristics) {
        if (BleUuidParser.compareStrings(c.uuid, characteristic)) return c;
      }
    }
    throw _WebException(
      BleShieldNativeErrorCode.characteristicNotFound,
      'characteristic $characteristic of service $service not found',
    );
  }

  Future<WebDescriptor> _descriptor(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
  ) async {
    final c = await _characteristic(deviceId, service, characteristic);
    final List<WebDescriptor> descriptors;
    try {
      descriptors = await c.getDescriptors();
    } catch (e) {
      throw _mapError(e, _Op.gatt);
    }
    for (final d in descriptors) {
      if (BleUuidParser.compareStrings(d.uuid, descriptor)) return d;
    }
    throw _WebException(
      BleShieldNativeErrorCode.characteristicNotFound,
      'descriptor $descriptor of characteristic $characteristic not found',
    );
  }

  // --------------------------------------------------------- unsupported

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) =>
      _unsupported('requestMtu');

  @override
  Future<int> readRssi(String deviceId) => _unsupported('readRssi');

  @override
  Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  ) =>
      _unsupported('requestConnectionPriority');

  @override
  Future<bool> isPaired(String deviceId) => _unsupported('isPaired');

  @override
  Future<bool> pair(String deviceId) => _unsupported('pair');

  @override
  Future<void> unpair(String deviceId) => _unsupported('unpair');

  Future<T> _unsupported<T>(String method, [String? why]) =>
      Future<T>.error(_WebException(
        BleShieldNativeErrorCode.notSupported,
        why ?? '$method is not supported on web',
      ));

  // -------------------------------------------------------------- errors

  /// The one place browser errors become native error codes.
  static BleShieldNativeException _mapError(Object error, _Op op) {
    if (error is BleShieldNativeException) return error;
    if (error is! WebBluetoothError) {
      return BleShieldNativeException(
        code: BleShieldNativeErrorCode.unknownError,
        message: error.toString(),
        details: error,
      );
    }
    final message = error.message;
    final code = switch (error.name) {
      // The user or an enterprise policy turned Web Bluetooth off.
      _ when message.toLowerCase().contains('globally disabled') =>
        BleShieldNativeErrorCode.notSupported,
      // Chrome reports the dismissed chooser and "no device" with the same
      // name; only the message tells them apart.
      'NotFoundError' when op == _Op.chooser =>
        message.toLowerCase().contains('cancel')
            ? BleShieldNativeErrorCode.operationCancelled
            : BleShieldNativeErrorCode.deviceNotFound,
      'NotFoundError' when op == _Op.gatt =>
        BleShieldNativeErrorCode.characteristicNotFound,
      'NotFoundError' => BleShieldNativeErrorCode.deviceNotFound,
      'SecurityError' ||
      'NotAllowedError' =>
        BleShieldNativeErrorCode.bluetoothNotAllowed,
      'NotSupportedError' => BleShieldNativeErrorCode.notSupported,
      'NetworkError' when op == _Op.connect =>
        BleShieldNativeErrorCode.connectionFailed,
      'NetworkError' ||
      'InvalidStateError' =>
        BleShieldNativeErrorCode.deviceDisconnected,
      'AbortError' => BleShieldNativeErrorCode.operationCancelled,
      _ => BleShieldNativeErrorCode.unknownError,
    };
    return BleShieldNativeException(
      code: code,
      message: '${error.name}: $message',
      details: error.name,
    );
  }
}

enum _Op { chooser, connect, gatt }

class _WebException extends BleShieldNativeException {
  _WebException(BleShieldNativeErrorCode code, String message)
      : super(code: code, message: message);
}

class _CharacteristicKey {
  const _CharacteristicKey(this.deviceId, this.service, this.characteristic);

  final String deviceId;
  final String service;
  final String characteristic;

  @override
  bool operator ==(Object other) =>
      other is _CharacteristicKey &&
      other.deviceId == deviceId &&
      other.service == service &&
      other.characteristic == characteristic;

  @override
  int get hashCode => Object.hash(deviceId, service, characteristic);
}

class _Service {
  _Service(this.service, this.characteristics);

  final WebService service;
  final List<WebCharacteristic> characteristics;

  Future<BleService> toBleService(String deviceId, bool withDescriptors) async {
    final characteristics = <BleCharacteristic>[];
    for (final c in this.characteristics) {
      var descriptors = <BleDescriptor>[];
      if (withDescriptors) {
        try {
          descriptors = (await c.getDescriptors())
              .map((d) => BleDescriptor(d.uuid))
              .toList();
        } catch (_) {
          // A characteristic without readable descriptors keeps none.
        }
      }
      final p = c.properties;
      characteristics.add(BleCharacteristic.withMetaData(
        deviceId: deviceId,
        serviceId: service.uuid,
        uuid: c.uuid,
        properties: [
          if (p.broadcast) CharacteristicProperty.broadcast,
          if (p.read) CharacteristicProperty.read,
          if (p.write) CharacteristicProperty.write,
          if (p.writeWithoutResponse)
            CharacteristicProperty.writeWithoutResponse,
          if (p.notify) CharacteristicProperty.notify,
          if (p.indicate) CharacteristicProperty.indicate,
          if (p.authenticatedSignedWrites)
            CharacteristicProperty.authenticatedSignedWrites,
        ],
        descriptors: descriptors,
      ));
    }
    return BleService(service.uuid, characteristics);
  }
}
