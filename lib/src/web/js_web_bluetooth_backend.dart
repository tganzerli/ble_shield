// The browser side of WebBluetoothBackend. Compiled only for the web (see
// default_platform_web.dart).
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:ble_shield/src/web/js_bluetooth.dart';
import 'package:ble_shield/src/web/web_bluetooth_backend.dart';

/// [WebBluetoothBackend] over `navigator.bluetooth`.
class JsWebBluetoothBackend implements WebBluetoothBackend {
  JSBluetooth? get _bluetooth {
    final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
    if (navigator == null || !navigator.has('bluetooth')) return null;
    return navigator.getProperty<JSBluetooth?>('bluetooth'.toJS);
  }

  @override
  bool get isSupported => _bluetooth != null;

  JSBluetooth get _api =>
      _bluetooth ??
      (throw const WebBluetoothError(
          'NotSupportedError', 'navigator.bluetooth is not available'));

  @override
  Future<bool> getAvailability() =>
      _guard(() async => (await _api.getAvailability().toDart).toDart);

  @override
  Stream<bool> get availabilityChanges {
    final bluetooth = _bluetooth;
    if (bluetooth == null) return const Stream.empty();
    return _events<bool>(
      (l) => bluetooth.addEventListener('availabilitychanged', l),
      (l) => bluetooth.removeEventListener('availabilitychanged', l),
      (e) => (e as JSValueEvent).value,
    );
  }

  @override
  Future<WebDevice> requestDevice(WebRequestOptions options) => _guard(
        () async =>
            _JsDevice(await _api.requestDevice(_options(options)).toDart),
      );

  static JSObject _options(WebRequestOptions o) {
    final js = JSObject();
    if (o.acceptAllDevices) {
      js['acceptAllDevices'] = true.toJS;
    } else {
      js['filters'] = o.filters.map(_filter).toList().toJS;
      if (o.exclusionFilters.isNotEmpty) {
        js['exclusionFilters'] = o.exclusionFilters.map(_filter).toList().toJS;
      }
    }
    if (o.optionalServices.isNotEmpty) {
      js['optionalServices'] =
          o.optionalServices.map((s) => s.toJS).toList().toJS;
    }
    if (o.optionalManufacturerData.isNotEmpty) {
      js['optionalManufacturerData'] =
          o.optionalManufacturerData.map((c) => c.toJS).toList().toJS;
    }
    return js;
  }

  static JSObject _filter(WebRequestFilter f) {
    final js = JSObject();
    final services = f.services;
    if (services != null) {
      js['services'] = services.map((s) => s.toJS).toList().toJS;
    }
    final namePrefix = f.namePrefix;
    if (namePrefix != null) js['namePrefix'] = namePrefix.toJS;
    final manufacturerData = f.manufacturerData;
    if (manufacturerData != null) {
      js['manufacturerData'] = manufacturerData
          .map((m) {
            final entry = JSObject();
            entry['companyIdentifier'] = m.companyIdentifier.toJS;
            final prefix = m.dataPrefix;
            if (prefix != null) entry['dataPrefix'] = prefix.toJS;
            final mask = m.mask;
            if (mask != null) entry['mask'] = mask.toJS;
            return entry;
          })
          .toList()
          .toJS;
    }
    return js;
  }
}

class _JsDevice implements WebDevice {
  _JsDevice(this._device);

  final JSBluetoothDevice _device;

  JSGattServer get _gatt =>
      _device.gatt ??
      (throw const WebBluetoothError(
          'NotSupportedError', 'the device has no GATT server'));

  @override
  String get id => _device.id;

  @override
  String? get name => _device.name;

  @override
  bool get isConnected => _device.gatt?.connected ?? false;

  @override
  Future<void> connect() => _guard(() => _gatt.connect().toDart);

  @override
  void disconnect() => _device.gatt?.disconnect();

  @override
  Stream<void> get disconnections => _events<void>(
        (l) => _device.addEventListener('gattserverdisconnected', l),
        (l) => _device.removeEventListener('gattserverdisconnected', l),
        (_) {},
      );

  @override
  Future<List<WebService>> getPrimaryServices() =>
      _guard(() async => (await _gatt.getPrimaryServices().toDart)
          .toDart
          .map(_JsService.new)
          .toList());
}

class _JsService implements WebService {
  _JsService(this._service);

  final JSGattService _service;

  @override
  String get uuid => _service.uuid;

  @override
  Future<List<WebCharacteristic>> getCharacteristics() =>
      _guard(() async => (await _service.getCharacteristics().toDart)
          .toDart
          .map(_JsCharacteristic.new)
          .toList());
}

class _JsCharacteristic implements WebCharacteristic {
  _JsCharacteristic(this._c);

  final JSGattCharacteristic _c;

  @override
  String get uuid => _c.uuid;

  @override
  WebCharacteristicProperties get properties {
    final p = _c.properties;
    return WebCharacteristicProperties(
      broadcast: p.broadcast,
      read: p.read,
      write: p.write,
      writeWithoutResponse: p.writeWithoutResponse,
      notify: p.notify,
      indicate: p.indicate,
      authenticatedSignedWrites: p.authenticatedSignedWrites,
    );
  }

  @override
  Future<Uint8List> readValue() =>
      _guard(() async => _bytes(await _c.readValue().toDart));

  @override
  Future<void> writeValueWithResponse(Uint8List value) =>
      _guard(() => _c.writeValueWithResponse(value.toJS).toDart);

  @override
  Future<void> writeValueWithoutResponse(Uint8List value) =>
      _guard(() => _c.writeValueWithoutResponse(value.toJS).toDart);

  @override
  Future<void> startNotifications() =>
      _guard(() => _c.startNotifications().toDart);

  @override
  Future<void> stopNotifications() =>
      _guard(() => _c.stopNotifications().toDart);

  @override
  Stream<Uint8List> get valueChanges => _events<Uint8List>(
        (l) => _c.addEventListener('characteristicvaluechanged', l),
        (l) => _c.removeEventListener('characteristicvaluechanged', l),
        (_) {
          final value = _c.value;
          return value == null ? Uint8List(0) : _bytes(value);
        },
      );

  @override
  Future<List<WebDescriptor>> getDescriptors() =>
      _guard(() async => (await _c.getDescriptors().toDart)
          .toDart
          .map(_JsDescriptor.new)
          .toList());
}

class _JsDescriptor implements WebDescriptor {
  _JsDescriptor(this._d);

  final JSGattDescriptor _d;

  @override
  String get uuid => _d.uuid;

  @override
  Future<Uint8List> readValue() =>
      _guard(() async => _bytes(await _d.readValue().toDart));

  @override
  Future<void> writeValue(Uint8List value) =>
      _guard(() => _d.writeValue(value.toJS).toDart);
}

/// A copy of [view]'s bytes, detached from the browser's buffer.
Uint8List _bytes(JSDataView view) {
  final data = view.toDart;
  return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
}

/// A stream of DOM events: the listener is attached on listen and removed on
/// cancel.
Stream<T> _events<T>(
  void Function(JSFunction) add,
  void Function(JSFunction) remove,
  T Function(JSObject event) read,
) {
  late final StreamController<T> controller;
  final listener = ((JSObject event) {
    try {
      controller.add(read(event));
    } catch (e) {
      controller.addError(e);
    }
  }).toJS;
  controller = StreamController<T>.broadcast(
    onListen: () => add(listener),
    onCancel: () => remove(listener),
  );
  return controller.stream;
}

/// Runs a browser call and turns a rejection (a `DOMException`) into a
/// [WebBluetoothError]. A rejected Promise surfaces as an opaque JS value
/// whose `toString()` is "`<name>: <message>`".
Future<T> _guard<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on WebBluetoothError {
    rethrow;
  } catch (e) {
    throw _webError(e);
  }
}

final _domError =
    RegExp(r'^(?:Error: )?([A-Za-z]+Error):\s*(.*)$', dotAll: true);

WebBluetoothError _webError(Object error) {
  final text = error.toString();
  final match = _domError.firstMatch(text);
  if (match == null) return WebBluetoothError('UnknownError', text);
  return WebBluetoothError(match.group(1)!, match.group(2)!);
}
