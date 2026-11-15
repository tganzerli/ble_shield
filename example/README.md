# ble_shield_example

Minimal demo of `ble_shield`: adapter state, scan, connect, service discovery,
notifications and (on iOS) opt-in state restoration via `configureRestoration`.

```sh
cd example
flutter run
```

Android needs `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` (API 31+) or location (API ≤ 30),
declared in `android/app/src/main/AndroidManifest.xml`. iOS declares
`NSBluetoothAlwaysUsageDescription` and the `bluetooth-central` background mode in
`ios/Runner/Info.plist`.
