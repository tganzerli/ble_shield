## 0.4.0

- Web is now a declared platform, on Web Bluetooth through `dart:js_interop`
  (no `flutter_web_bluetooth`, no `package:web`; `flutter_web_plugins` from
  the Flutter SDK). Web has no free scan: `startScan` throws `unsupported`.
- New `BleShield.requestDevice({withServices, optionalServices,
  optionalManufacturerData})`: opens the browser's Bluetooth chooser and
  returns the picked device as a `ScanResult`. Call it from a user gesture.
  It throws `unsupported` on every other platform.
- New `ShieldErrorCode.cancelled`, thrown when the user dismisses the
  chooser. If you `switch` over `ShieldErrorCode` without a default branch,
  add the case.
- On the web, remote ids are the browser's opaque, case-sensitive tokens and
  are kept verbatim; Android and Apple ids are still lower-cased.
  `ShieldError.platform` is `web` there.

## 0.3.0

- macOS is now a declared platform (10.15+), on the same shared Darwin
  sources as iOS. Apps need `NSBluetoothAlwaysUsageDescription` and the
  `com.apple.security.device.bluetooth` entitlement. State restoration is
  iOS-only: `configureRestoration` returns false on macOS. The README has a
  feature table per platform.
- The README has a Roadmap: Windows, Web and Linux are planned, and the
  package reaches 1.0.0 when that rollout is complete.

## 0.2.3

- Documentation only: the README covers installation, runtime permissions
  (requested by the app, not by ble_shield), the constructor options and their
  defaults, GATT timeouts and capability getters, scan result fields, and the
  MTU and scan caveats per platform. No code change.

## 0.2.2

- Android: `ShieldDevice.connectionParameters` now works in minified release
  builds. The plugin ships a consumer ProGuard rule that keeps the hidden
  `onConnectionUpdated` callback, which the code shrinker used to strip.

## 0.2.1

- Diagnostics (public API contract 3.1, additive):
  `BleShield.setNativeLogLevel(ShieldLogLevel)` turns on the native layer's
  logs in any build mode (the upstream debug-only guard is gone);
  `ShieldDevice.mtuNow`/`mtu` report the ATT MTU the platform negotiated,
  requested or not (Android on every negotiation, Apple on connect);
  `ShieldDevice.connectionParametersNow`/`connectionParameters` report the
  Android connection interval, latency and supervision timeout (Android 8+).
- Native: new `onMtuChanged` callback on the Pigeon callback channel.

## 0.2.0

First published version.

- ble_shield is now a Flutter plugin with its own native layer for Android and
  iOS, derived from universal_ble 3.2.0 (see `NOTICE` and
  `third_party/UPSTREAM.md`). The dependency on universal_ble and the path
  override to its fork are gone, and so are `bluez`, `dbus` and
  `flutter_web_bluetooth` from the resolution.
- Own native identity: Android package `io.github.tganzerli.ble_shield`,
  plugin class `BleShieldPlugin`, Pigeon channels `dev.flutter.pigeon.ble_shield.*`,
  iOS module `ble_shield`, own Android request codes. ble_shield can share an
  app with universal_ble or flutter_blue_plus.
- iOS: no `CBCentralManager` is created at plugin registration. State
  restoration is opt-in only through `configureRestoration`; there is no default
  identifier and no Info.plist key.
- iOS: the adapter state always comes from a real central manager, so the
  adapter stream keeps updating after the permission prompt.
- Breaking (tests only): `BleShield(platform:)` now takes a `BleShieldPlatform`
  from `package:ble_shield/testing.dart` and is `@visibleForTesting`.
- Peripheral (GATT server) mode is not included.
- Breaking: `scanWatchdog` is off by default, and when set it only adds
  `scanFailed` to `scanErrors`: the scan keeps running. It used to end the
  session after 30 s without adverts, which killed healthy filtered scans.
- Android: a scanner failure (`ScanCallback.onScanFailed`, or a failure
  starting the scan) now ends the scan session and is reported on `scanErrors`
  as `scanFailed`, with the platform code in `nativeCode`.
- Android: one GATT client per device. `connect` reuses a pending
  auto-connect or closes the previous client before opening a new one, so
  auto-reconnects and `systemDevices` adoption no longer leave orphan clients.
- `ShieldDevice.disconnect` takes `rearm` (default `true`, unchanged). With
  `rearm: false`, auto-reconnect is not re-armed (by the drop or by the adapter
  coming back on) until the device connects again or `setAutoReconnect` is
  called; `autoReconnect` stays on for drops of the next session.
- `adapterState` no longer emits a transient `unknown` on a new engine: until
  the platform answers for the first time, the first event is held back (up to
  the new `adapterStateTimeout`, default 3 s), then the cached state is
  delivered. `adapterStateNow` is unchanged.
- Breaking: a default `disconnect()` on a device that is not connected no
  longer cancels a reconnection armed by a drop, a retry or the adapter coming
  back on, while `autoReconnect` is on: the timer and a pending OS request are
  left alone and no native disconnect is issued. Use `disconnect(rearm: false)`,
  or turn `autoReconnect` off first, to stop it. A kick is still cancelled.

## 0.1.0-dev

Initial development version (not published).

- `BleShield` central with an inert constructor: adapter state cache with
  replay, `isSupported`, and a `turnOn` that never hangs.
- Scanning: aggregated results with `removeIfGone`, a scan state kept by
  ble_shield, `scanErrors`, and a watchdog for silently dead scanners.
- `ShieldDevice`: connect with a 35 s timeout (cancelled natively on timeout),
  GATT release on failure, `connectInProgress`, and a global GATT lock that
  covers connect.
- Auto-reconnect state machine (kick, drop, retry, adapter-on), whose failures
  are reported on `reconnectEvents` and never thrown.
- GATT: per-connection discovery, read, write (with response by default),
  `setNotify` choosing notify or indicate, and per-characteristic values.
- iOS restoration opt-in (`configureRestoration`), restored ids kept by an
  injectable store, and `systemDevices` with Dart-side filtering on Android.
- A single `ShieldError` type with typed codes.
