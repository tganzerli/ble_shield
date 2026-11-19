// Web Bluetooth bindings on dart:js_interop. Compiled only for the web (see
// default_platform_web.dart). Only the members ble_shield uses are declared.
import 'dart:js_interop';

/// `navigator.bluetooth`.
extension type JSBluetooth._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> getAvailability();
  external JSPromise<JSBluetoothDevice> requestDevice(JSObject options);
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

/// The `availabilitychanged` event.
extension type JSValueEvent._(JSObject _) implements JSObject {
  external bool get value;
}

/// `BluetoothDevice`.
extension type JSBluetoothDevice._(JSObject _) implements JSObject {
  external String get id;
  external String? get name;
  external JSGattServer? get gatt;
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

/// `BluetoothRemoteGATTServer`.
extension type JSGattServer._(JSObject _) implements JSObject {
  external bool get connected;
  external JSPromise<JSGattServer> connect();
  external void disconnect();
  external JSPromise<JSArray<JSGattService>> getPrimaryServices();
}

/// `BluetoothRemoteGATTService`.
extension type JSGattService._(JSObject _) implements JSObject {
  external String get uuid;
  external JSPromise<JSArray<JSGattCharacteristic>> getCharacteristics();
}

/// `BluetoothRemoteGATTCharacteristic`.
extension type JSGattCharacteristic._(JSObject _) implements JSObject {
  external String get uuid;
  external JSCharacteristicProperties get properties;
  external JSDataView? get value;
  external JSPromise<JSDataView> readValue();
  external JSPromise<JSAny?> writeValueWithResponse(JSUint8Array value);
  external JSPromise<JSAny?> writeValueWithoutResponse(JSUint8Array value);
  external JSPromise<JSGattCharacteristic> startNotifications();
  external JSPromise<JSGattCharacteristic> stopNotifications();
  external JSPromise<JSArray<JSGattDescriptor>> getDescriptors();
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

/// `BluetoothCharacteristicProperties`.
extension type JSCharacteristicProperties._(JSObject _) implements JSObject {
  external bool get broadcast;
  external bool get read;
  external bool get write;
  external bool get writeWithoutResponse;
  external bool get notify;
  external bool get indicate;
  external bool get authenticatedSignedWrites;
}

/// `BluetoothRemoteGATTDescriptor`.
extension type JSGattDescriptor._(JSObject _) implements JSObject {
  external String get uuid;
  external JSPromise<JSDataView> readValue();
  external JSPromise<JSAny?> writeValue(JSUint8Array value);
}
