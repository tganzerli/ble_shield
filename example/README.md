# ble_shield_example

Minimal demo of `ble_shield`: adapter state, scan (on the web, the browser's
device chooser), connect, service discovery, notifications and (on iOS) opt-in
state restoration via `configureRestoration`.

```sh
cd example
flutter run
```

Android needs `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` (API 31+) or location (API ≤ 30),
declared in `android/app/src/main/AndroidManifest.xml`. iOS declares
`NSBluetoothAlwaysUsageDescription` and the `bluetooth-central` background mode in
`ios/Runner/Info.plist`. macOS declares `NSBluetoothAlwaysUsageDescription` in
`macos/Runner/Info.plist` and the `com.apple.security.device.bluetooth`
entitlement in both `macos/Runner/*.entitlements`.

On macOS, `flutter run` started from a terminal app can be killed by the
privacy system (TCC) on the first Bluetooth access: macOS checks the usage
description of the *responsible* process, which is the terminal, not the
example. Build with `flutter build macos` and open
`build/macos/Build/Products/Debug/ble_shield_example.app` (or run from Xcode).

On the web, run `flutter run -d chrome` (served on `localhost`, a secure
context) and press **Choose device**. List the services you want to use
(for example `180d`): the browser only lets the page reach the services it
asked for in the chooser.
