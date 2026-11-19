# ble_shield

A defensive BLE central plugin for Flutter (Android, iOS and macOS). It ships
its own native layer, derived from
[universal_ble](https://pub.dev/packages/universal_ble) 3.2.0 (see
*Third-party code*), and adds the things a long-running BLE app needs and a
plain plugin leaves to the caller:

- adapter and connection state cached in Dart, replayed to every subscriber;
- an aggregated scan list (one entry per device) with `removeIfGone`, a scan
  state that ble_shield keeps itself, and native scanner failures reported
  (Android) instead of a scan that silently stops;
- one GATT client per device on Android, even across auto-reconnects;
- every GATT operation of every device serialized by one lock, `connect`
  included;
- `connect` with a timeout that cancels the native attempt and releases the
  GATT client on failure;
- an auto-reconnect state machine that never raises errors into your zone;
- discovery that is real on every new connection, cached within it;
- one error type with typed codes;
- opt-in iOS central state restoration for apps with several engines.

ble_shield is published on [pub.dev](https://pub.dev/packages/ble_shield) for
Android, iOS and macOS. It has no dependency on universal_ble, on `bluez`/`dbus` or
on `flutter_web_bluetooth`, and its native identity (Android package, classes,
Pigeon channels, iOS module) is its own, so it can share an app with
universal_ble or flutter_blue_plus.

## Installation

```sh
flutter pub add ble_shield
```

Then declare the Bluetooth permissions and request them at runtime, as
described in *Permissions*. ble_shield does not request them for you.

## Quick start

```dart
final ble = BleShield(); // one per Flutter engine; the constructor is inert

ble.adapterState.listen((s) => print('adapter: $s'));

ble.scanResults.listen((list) => print('${list.length} devices'));
ble.scanErrors.listen((e) => print('scan problem: $e')); // restart if needed
await ble.startScan(withServices: ['180d'], removeIfGone: const Duration(seconds: 10));

final device = ble.device('AA:BB:CC:DD:EE:FF');
await device.connect(); // 35 s timeout by default
final services = await device.discoverServices();
final hr = services.expand((s) => s.characteristics).firstWhere((c) => c.canNotify);
hr.onValueReceived.listen(print);
await hr.setNotify(true);

device.setAutoReconnect(true); // re-armed 3 s after every drop
device.reconnectEvents.listen(print); // "[Reconnect] aa:bb:… fired origin=drop"
```

## Permissions

Declare what the platform needs:

- **Android** (`AndroidManifest.xml`): `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`
  on API 31+, and `ACCESS_FINE_LOCATION` for scanning on API 30 and below:

  ```xml
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
      android:usesPermissionFlags="neverForLocation" />
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
      android:maxSdkVersion="30" />
  ```

- **iOS** (`Info.plist`): `NSBluetoothAlwaysUsageDescription`.

- **macOS**: `NSBluetoothAlwaysUsageDescription` in `Info.plist`, and the
  `com.apple.security.device.bluetooth` entitlement in both
  `DebugProfile.entitlements` and `Release.entitlements`. Without the
  entitlement the App Sandbox blocks Bluetooth.

  ```xml
  <key>com.apple.security.device.bluetooth</key>
  <true/>
  ```

ble_shield does **not** request runtime permissions and has no API for them.
Request them in the app (for example with `permission_handler`) before
scanning or connecting. On iOS the system prompt appears when the central
manager is created, which happens on the first central call, not in the
`BleShield()` constructor.

## API overview

### Configuration

All options are constructor parameters of `BleShield`:

| Option | Default | Meaning |
|---|---|---|
| `canTurnOn` | `true` | `false` makes `turnOn()` fail at once with `unsupported` (for background engines). |
| `turnOnTimeout` | 30 s | Bound for `turnOn()`. |
| `scanWatchdog` | `null` (off) | Warns on `scanErrors` when no advertisement arrives within this window. It never ends the scan. |
| `closeGattOnDetach` | `true` | Closes this engine's GATT clients when the engine detaches (Android). |
| `releaseTimeout` | 5 s | Bound for the internal disconnect that cancels a failed or timed-out connect. |
| `pendingConnectWindow` | 1 day | Dart-side bound for a reconnection request. When it passes, ble_shield stops waiting; the OS request stays pending. |
| `gattTimeout` | 10 s | Default bound for discovery, read and write. |
| `adapterStateTimeout` | 3 s | How long a new `adapterState` subscriber waits for the platform's first answer. |
| `restoredIdStore` | in memory | Storage for iOS restored ids, see *iOS state restoration*. |

### `BleShield` (central)

| Member | Behaviour |
|---|---|
| `BleShield({...})` | Makes no plugin call. Safe in eager dependency injectors. |
| `adapterStateNow`, `adapterState` | Cached `AdapterState` (`unknown`, `resetting`, `unsupported`, `unauthorized`, `off`, `on`); the stream replays the current value. On a new engine its first event waits for the platform's first answer (up to `adapterStateTimeout`, 3 s), so it never starts with a transient `unknown`. |
| `isSupported({wait})` | False only when the platform reports no BLE. |
| `turnOn()` | Android with an Activity only. Throws `unsupported` on Apple or with `canTurnOn: false`, `operationTimeout` after `turnOnTimeout`. Never hangs. |
| `startScan({withServices, mode, removeIfGone})` | Throws `scanAlreadyStarted` during a scan. Start failures are thrown and also emitted on `scanErrors`, and the native scan is stopped. `mode` (`lowPower` by default, `balanced`, `lowLatency`) applies to Android only. |
| `stopScan()` | Idempotent, always sent to the native scanner, never throws. |
| `isScanningNow`, `isScanning` | Scan state kept by ble_shield, not a native flag. |
| `scanResults` | Aggregated `List<ScanResult>`, re-emitted on every advertisement. |
| `scanErrors` | Start failures, native scanner failures (Android `onScanFailed`, which also end the scan), adapter turning off mid-scan, and the opt-in `scanWatchdog` warning (off by default; it only warns and never ends the scan). |
| `systemDevices({required withServices})` | Devices connected at OS level. Call `connect()` on them to attach this engine's GATT client. |
| `device(remoteId)` | Same `ShieldDevice` per id (case-insensitive) until it is disposed. |
| `configureRestoration(id)` | iOS state restoration, see below. |
| `restoredIds`, `restoredDevices()`, `forgetRestoredId(id)` | Peripherals the OS reported connected without a connect from ble_shield. |
| `setNativeLogLevel(level)` | Logs of the native layer, see *Diagnostics*. |
| `dispose()` | Stops listening. |

### `ShieldDevice`

| Member | Behaviour |
|---|---|
| `isConnected`, `connectionState` | Synchronous and coherent; the stream replays the current state. |
| `connect({timeout = 35 s})` | Throws `connectInProgress` if one is already running (nothing is queued), and `connectTimeout` after the timeout (the native attempt is cancelled). Any failure releases the GATT client. Runs under the global GATT lock. |
| `disconnect({timeout = 35 s, rearm = true})` | Cancels an armed reconnection first, except, by default, one armed by a link loss on a device that is already disconnected (see *Reconnection*). Cancels an in-flight `connect` at once. `rearm: false` ends the session without re-arming auto-reconnect until the next connection (see *Reconnection*). |
| `setAutoReconnect(enabled, {delay = 3 s})`, `autoReconnect` | See *Reconnection*. |
| `reconnectEvents` | `ReconnectEvent(outcome: fired/skipped/failed, origin, reason)`. |
| `discoverServices({timeout})` | Real discovery on the first call of each connection, cached until it ends. `timeout` defaults to `gattTimeout`. |
| `mtuNow`, `mtu`; `connectionParametersNow`, `connectionParameters` | Link diagnostics, see *Diagnostics*. |
| `dispose()` | Cancels an armed attempt and releases a pending OS request. It does not disconnect. |

`ShieldCharacteristic` has:

- properties: `canRead`, `canWrite` (`canWriteWithResponse` or
  `canWriteWithoutResponse`), `canNotify` (`supportsNotify` or
  `supportsIndicate`) and `isNotifying`;
- `read({timeout})` and `write(value, {withoutResponse = false, timeout})`, both
  bounded by `gattTimeout` unless `timeout` is given;
- `setNotify(enabled, {timeout = 15 s})`, which picks notify or indicate;
- `onValueReceived`, for this device and characteristic only.

### Scan results

`scanResults` emits a `List<ScanResult>`, one entry per device:

| Field | Content |
|---|---|
| `remoteId` | Lower-case id: MAC address on Android, CoreBluetooth UUID on Apple. |
| `name` | Name reported for the advertisement, empty if none. |
| `rssi` | Signal strength; -127 when the platform reported none. |
| `connectable` | `true` unless the platform said otherwise. |
| `manufacturerData` | Company id → payload, without the two company id bytes. |
| `serviceUuids`, `serviceData` | Advertised services and their data, canonical UUIDs. |
| `lastSeen` | When the scanner last saw the device. |

The whole list is re-emitted on every advertisement. On iOS one discovery may
arrive as two emissions a fraction of a millisecond apart (the advertisement
and its scan response), so a listener that starts work on each emission should
be idempotent.

### UUIDs and ids

All UUIDs are accepted as 16, 32 or 128 bits and emitted as canonical 128-bit
lower-case strings; `canonicalUuid(uuid)` gives the same form for your own
constants. Remote ids are emitted in lower case.

### Errors

Every failure is a `ShieldError(code, message, platform, nativeCode)`. The
code is one of `adapterOff`, `notConnected`, `deviceNotFound`,
`connectInProgress`, `connectTimeout`, `connectFailed`, `scanAlreadyStarted`,
`scanFailed`, `characteristicNotFound`, `operationTimeout`, `gattFailed`,
`unsupported`, `unauthorized`, `invalidArgument` or `unknown`. No raw plugin
exception escapes. Asynchronous failures go to `scanErrors` and
`reconnectEvents`; nothing goes to the zone.

## Diagnostics

For a slow or unstable link, the app can see what the link negotiated and turn
on the native layer's own logs, in any build mode:

```dart
await ble.setNativeLogLevel(ShieldLogLevel.debug); // default: none

device.mtu.listen((mtu) => log('mtu=$mtu'));
device.connectionParameters.listen((p) => log('params=$p'));
```

- `setNativeLogLevel` is process-wide. The native logs go to logcat (tag
  `BleShieldNative`) on Android and to stdout on Apple; the Dart half of the
  native layer logs through `dart:developer` (`BleShieldNative:*`). No log
  reaches a Dart stream. `debug`
  shows each MTU and connection-parameter change; `verbose` adds a line per
  notification, so do not leave it on in production. It makes no other native
  call and does not create the iOS central.
- `mtuNow` / `mtu`: the ATT MTU the platform reported, `null` until it reports
  one and again after a disconnection. Android reports every negotiation,
  including the one Android 14+ makes on its own after connecting; Apple
  reports it on connect. A link the OS already had (for example, a device still
  connected from a previous process) may keep an MTU that was never reported,
  so `null` means "unknown", not 23. On Android, an MTU exchange that the
  peripheral starts may also go unreported. ble_shield does not request an MTU
  itself.
- `connectionParametersNow` / `connectionParameters`: interval, latency and
  supervision timeout, when the Android controller reports them (Android 8+,
  on each update), in debug and in minified release builds alike. Always `null`
  on Apple and on older Android.

## Reconnection

`setAutoReconnect(true)` on a disconnected device, even one that never
connected, arms an attempt after `delay`. Each drop (connected → disconnected)
arms another, and so does the adapter coming back on. When the delay ends, the
attempt is skipped if meanwhile the device connected, `disconnect` was called,
the device was disposed, auto-reconnect was turned off or the adapter is not
`on`. A failed attempt is reported as `failed` and re-armed.

The attempt is a pending OS request with no timeout:

- **Android:** a native `autoConnect` request. It survives the screen being
  off while a foreground service runs. It is issued under the GATT lock but
  does not hold it while pending.
- **Apple:** a plain CoreBluetooth connect, which never expires on its own.
  ble_shield issues it again after each drop instead of using `autoConnect`,
  because on iOS 17+ `autoConnect` hides drops from the app.

`disconnect()` with auto-reconnect still on re-arms through the drop it causes.
To disconnect for good, turn auto-reconnect off first.

To end a session without reconnecting right away, but keep auto-reconnect for
real drops later, pass `rearm: false`:

```dart
await device.disconnect(rearm: false);
```

Nothing arms reconnection afterwards (not the drop, not the adapter coming back
on) until the device connects again by any path (`connect`, a pending attempt,
`systemDevices`) or until `setAutoReconnect` is called. `autoReconnect` stays
`true`, so a drop of the next session re-arms as usual. There is no timer: when
to connect again is up to the app.

A `disconnect()` on a device that already dropped does not cancel the
reconnection of that drop. With the default `rearm: true`, auto-reconnect on,
the device not connected and no `connect` in flight, an attempt armed by a drop,
a retry or the adapter coming back on is left alone: nothing is cancelled and
no native disconnect is issued. A typical case is a session that fails because
the link was lost, followed by the app's own cleanup `disconnect()`. To stop
that reconnection, pass `rearm: false` or turn auto-reconnect off first. A kick
(`setAutoReconnect(true)` on a device that never dropped) is still cancelled.

## iOS state restoration

No `CBCentralManager` is created when the plugin registers: it is created on
the first central call. Restoration is **opt-in only**. There is no default
identifier, so nothing restores unless one engine claims an identifier of its
own (in an app with a UI engine and a background engine, typically the
background one):

1. In `ios/Runner/Info.plist`:

   ```xml
   <key>UIBackgroundModes</key>
   <array>
     <string>bluetooth-central</string>
   </array>
   ```

2. In the engine that should own restoration (typically the background one),
   call `configureRestoration` **before any other ble_shield call** on that
   engine:

   ```dart
   final ble = BleShield(restoredIdStore: MyStore()); // inert constructor
   final granted = await ble.configureRestoration('com.example.app.central');
   // Peripherals the OS restored as connected are reported here:
   for (final d in await ble.restoredDevices()) {
     d.setAutoReconnect(true); // restored but already dropped → reconnect
   }
   ```

   `configureRestoration` installs ble_shield's connection listener first and
   then creates the manager, so a peripheral restored during creation is not
   lost. It returns `false` when restoration was not granted: another live
   engine owns the identifier, the manager already existed, or the
   background mode is missing. It always returns `false` off iOS.

3. Restored ids are kept by an injectable `RestoredIdStore`. The default,
   `InMemoryRestoredIdStore`, lives only as long as the process. ble_shield
   ships no storage plugin, so implement the interface over your own storage
   if you need the ids across launches.

## Android notes

- `autoConnect` reconnection requests are only as durable as the process. Run
  a foreground service if they must survive the app going to the background.
- `turnOn()` needs a foreground Activity. Construct the instance with
  `canTurnOn: false` in background engines to get an immediate `unsupported`
  error instead of a timeout.
- `closeGattOnDetach` (default true) closes this engine's GATT clients when
  the engine detaches.
- `systemDevices` does not pass `withServices` to the platform, because
  the native layer would connect to every device to discover its services. The
  filter therefore runs in Dart, using the services ble_shield has seen
  advertised or discovered. Devices whose services are unknown are kept.
- Minified release builds need no ProGuard rule from the app: the plugin ships
  its own consumer rules.

## Platforms

Android (`minSdk` 21), iOS (13.1) and macOS (10.15). iOS and macOS share
the Darwin sources.

| | Android | iOS | macOS |
|---|---|---|---|
| Scan, connect, GATT, notifications | ✓ | ✓ | ✓ |
| `systemDevices` | ✓ | ✓ | ✓ |
| `mtu` | ✓ | ✓ | ✓ |
| `connectionParameters` | 8.0+ | — | — |
| `turnOn` | ✓ | — | — |
| State restoration (`configureRestoration`) | — | ✓ (opt-in) | — |

Where a feature is missing, `turnOn` throws `ShieldErrorCode.unsupported`,
`configureRestoration` returns false and `connectionParameters` stays null.

Permissions are described in *Permissions*. Both CocoaPods and Swift Package
Manager builds are supported. See `example/` for a complete app.

## Roadmap

ble_shield is growing toward every platform its native layer can reach. A
platform is declared only once the example app builds and runs on it, and none
may add a dependency that clashes with common Linux or web packages
(`bluez`, `dbus`, `flutter_web_bluetooth`).

| Platform | Status |
|---|---|
| Android | Available since 0.2.0 |
| iOS | Available since 0.2.0 |
| macOS | Available since 0.3.0 |
| Windows | Planned: C++/WinRT native code, no new Dart dependency |
| Web | Planned: Web Bluetooth through `dart:js_interop`, with the browser's device chooser in place of a free scan |
| Linux | Planned: a separate, optional package, so apps that do not target Linux never resolve `bluez` or `dbus` |

When this rollout is complete, ble_shield moves to **1.0.0**. No dates are
promised.

## Testing

```sh
flutter test
```

The tests drive a fake native platform (`test/support/fake_platform.dart`),
built on the types exported by `package:ble_shield/testing.dart` and passed as
`BleShield(platform: ...)`. They prove the Dart behaviour, not the behaviour of
the radios. The native layer's own tests live in `test/native/` (Dart) and
`android/src/test/` (Kotlin, run with
`cd example/android && ./gradlew :ble_shield:testDebugUnitTest`).

## Third-party code

The native layer (`android/`, `darwin/`, `pigeon/`, `lib/src/native/`,
`test/native/`) is derived from universal_ble 3.2.0, Copyright (c) 2024,
Navideck Labs OÜ, distributed under the BSD 3-Clause License. Its notice is in
[NOTICE](NOTICE) and the full licence in
[third_party/universal_ble/LICENSE](third_party/universal_ble/LICENSE). How it is
imported, renamed and patched is recorded in
[third_party/UPSTREAM.md](third_party/UPSTREAM.md). ble_shield is not affiliated
with or endorsed by the universal_ble authors.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
