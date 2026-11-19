import 'dart:async';

import 'package:flutter/foundation.dart';

import 'errors.dart';
import 'mutex.dart';
import 'native/native.dart';
import 'native/utils/device_id.dart';
import 'platform.dart';
import 'types.dart';
import 'uuid.dart';
import 'value_stream.dart';

part 'device.dart';
part 'gatt.dart';

/// The BLE central. Create one per Flutter engine.
///
/// The constructor does not touch the native layer: nothing native happens until
/// the first API call or [configureRestoration]. This lets a dependency
/// injector build it eagerly without creating the iOS central manager before
/// restoration is configured.
class BleShield {
  BleShield({
    @visibleForTesting BleShieldPlatform? platform,
    TargetPlatform? targetPlatform,
    this.canTurnOn = true,
    this.turnOnTimeout = const Duration(seconds: 30),
    this.scanWatchdog,
    this.closeGattOnDetach = true,
    this.releaseTimeout = const Duration(seconds: 5),
    this.pendingConnectWindow = const Duration(days: 1),
    this.gattTimeout = const Duration(seconds: 10),
    this.adapterStateTimeout = const Duration(seconds: 3),
    RestorationConfigurator? restorationConfigurator,
    RestoredIdStore? restoredIdStore,
  })  : _platformOverride = platform,
        _targetPlatformOverride = targetPlatform,
        _configurator = restorationConfigurator,
        _restoredStore = restoredIdStore ?? InMemoryRestoredIdStore();

  final BleShieldPlatform? _platformOverride;
  final TargetPlatform? _targetPlatformOverride;
  final RestorationConfigurator? _configurator;
  final RestoredIdStore _restoredStore;

  /// False in engines without a foreground Activity (e.g. an Android
  /// background service): [turnOn] then fails at once with
  /// [ShieldErrorCode.unsupported] instead of waiting for [turnOnTimeout].
  final bool canTurnOn;

  /// Upper bound for [turnOn]. The native layer's `enableBluetooth` never
  /// completes without an Activity.
  final Duration turnOnTimeout;

  /// Opt-in warning for a scan that hears nothing. While scanning, each
  /// window of this length without an advertisement adds a
  /// [ShieldErrorCode.scanFailed] to [scanErrors]. It only warns: the session
  /// keeps running, [isScanningNow] stays true and the native scan is not
  /// stopped, so a healthy filtered scan waiting for a device that is
  /// connected or advertises in bursts is never ended. The caller decides
  /// whether to restart. `null` (the default) disables it.
  ///
  /// A real scanner failure does not depend on it: Android's
  /// `ScanCallback.onScanFailed` (and a failure starting the scan) ends the
  /// session and reports [ShieldErrorCode.scanFailed] with the platform code
  /// in [ShieldError.nativeCode]. Apple has no scan-failure callback.
  final Duration? scanWatchdog;

  /// Android: close GATT clients when this engine detaches, so a dead engine
  /// leaves no client registered in the stack.
  final bool closeGattOnDetach;

  /// Bound for the internal disconnect that cancels a failed or timed-out
  /// connect.
  final Duration releaseTimeout;

  /// Dart-side bound the native layer requires for a reconnection request. When
  /// it passes, ble_shield stops waiting but the OS request stays pending.
  final Duration pendingConnectWindow;

  /// Default bound for discovery, read and write.
  final Duration gattTimeout;

  /// How long a subscriber to [adapterState] waits for the platform's first
  /// answer before receiving the cached state (possibly
  /// [AdapterState.unknown]). The wait is a [Timer] started on first use and
  /// cancelled by the platform's first answer or by [dispose].
  final Duration adapterStateTimeout;

  // ---------------------------------------------------------------- platform

  TargetPlatform get _target =>
      _targetPlatformOverride ?? defaultTargetPlatform;

  bool get _isAndroid => !kIsWeb && _target == TargetPlatform.android;

  bool get _isIOS => !kIsWeb && _target == TargetPlatform.iOS;

  /// `android` | `apple` | `web` | null, attached to native errors.
  String? get _platformName => switch (_target) {
        _ when kIsWeb && _targetPlatformOverride == null => 'web',
        TargetPlatform.android => 'android',
        TargetPlatform.iOS || TargetPlatform.macOS => 'apple',
        _ => null,
      };

  /// The form ble_shield emits and keys device ids by: lower case for the
  /// case-insensitive addresses of Android (MAC) and Apple (CoreBluetooth
  /// UUID), verbatim for the opaque, case-sensitive ids of Web Bluetooth.
  /// Follows this engine's platform without installing it, so a call that
  /// only reads ids (e.g. [forgetRestoredId]) takes no native callback slot.
  /// The native layer keys by its single static platform, so engines with
  /// different id rules in one isolate are not supported (they already share
  /// the native callbacks).
  String _canonicalId(String remoteId) {
    final id = remoteId.trim();
    final platform = _platformOverride;
    return platform == null
        ? BleShieldNative.canonicalDeviceId(id)
        : DeviceId.of(id, isAddress: platform.hasAddressDeviceIds).canonical;
  }

  ShieldError _map(Object e, ShieldOperation op, {int? nativeCode}) =>
      mapShieldError(e,
          op: op, platform: _platformName, nativeCode: nativeCode);

  // -------------------------------------------------------------- lifecycle

  bool _installed = false;
  StreamSubscription<AvailabilityState>? _adapterSub;

  /// Installs listeners. Makes no native call.
  void _install() {
    if (_installed) return;
    _installed = true;
    final platform = _platformOverride;
    if (platform != null) BleShieldNative.setInstance(platform);
    // ble_shield serializes GATT itself, including connect, which
    // the native layer's queue does not cover. Its queue would only add a second
    // ordering, so it runs commands directly and just applies timeouts.
    BleShieldNative.queueType = QueueType.none;
    // Global listener: device state, and restored peripherals that have no
    // ShieldDevice yet. ble_shield owns this native callback slot.
    BleShieldNative.onConnectionChange = _onConnectionChange;
    // Diagnostics, routed to devices this engine already handed out. An event
    // for an unknown id is dropped: the value comes back on the next change.
    BleShieldNative.onMtuChange =
        (id, mtu) => _devices[_canonicalId(id)]?._setMtu(mtu);
    BleShieldNative.onConnectionParametersChange = (update) {
      if (!update.isSuccess) return;
      _devices[_canonicalId(update.deviceId)]?._setConnectionParameters(
        ShieldConnectionParameters(
          interval: Duration(microseconds: update.interval * 1250),
          latency: update.latency,
          supervisionTimeout:
              Duration(milliseconds: update.supervisionTimeout * 10),
        ),
      );
    };
  }

  /// Sets the verbosity of the native layer's own logs (logcat tag
  /// `BleShieldNative` on Android, stdout on Apple, and `dart:developer` for
  /// its Dart half), in any build mode. The
  /// default is [ShieldLogLevel.none]. `debug` shows each MTU and
  /// connection-parameter change; `verbose` adds a line per notification, so
  /// do not leave it on in production.
  ///
  /// Process-wide (every engine shares the native layer). Makes no other
  /// native call and does not create the iOS central.
  Future<void> setNativeLogLevel(ShieldLogLevel level) async {
    _install();
    await BleShieldNative.setLogLevel(switch (level) {
      ShieldLogLevel.none => BleLogLevel.none,
      ShieldLogLevel.error => BleLogLevel.error,
      ShieldLogLevel.warning => BleLogLevel.warning,
      ShieldLogLevel.info => BleLogLevel.info,
      ShieldLogLevel.debug => BleLogLevel.debug,
      ShieldLogLevel.verbose => BleLogLevel.verbose,
    });
  }

  void _onConnectionChange(BleConnectionChange change) {
    final id = _canonicalId(change.deviceId);
    final device = _devices[id];
    if (change.isConnected) {
      _knownConnected.add(id);
      // Connected without a connect from ble_shield: restored by the OS
      // (iOS state restoration) or a request that survived elsewhere.
      if (device == null || !device._initiatedByShield) _markRestored(id);
    } else {
      _knownConnected.remove(id);
    }
    device?._onConnectionChange(change);
  }

  // ------------------------------------------------------------ restoration

  /// Ids reported connected by the platform (any source) since start.
  final Set<String> _knownConnected = {};
  final Set<String> _restored = {};
  bool _restoredLoaded = false;

  /// Opts this engine's central into iOS state restoration.
  ///
  /// Call it before any other API of this instance, from the engine that
  /// should own restoration; the app must declare the `bluetooth-central`
  /// background mode. Restoration is opt-in only: no other engine restores,
  /// and there is no default identifier. It installs ble_shield's connection listener
  /// first, so a peripheral restored while the manager is created is not
  /// lost, then calls `BleShieldNativeDarwinCentral.configureRestoration`.
  ///
  /// Returns that call's result: false when restoration was not granted, and
  /// always false (without native calls) on platforms other than iOS.
  Future<bool> configureRestoration(String identifier) async {
    _install();
    if (!_isIOS) return false;
    bool granted;
    try {
      granted = await (_configurator ??
          BleShieldNativeDarwinCentral.configureRestoration)(identifier);
    } catch (e) {
      throw _map(e, ShieldOperation.other);
    }
    _start();
    return granted;
  }

  void _markRestored(String id) {
    if (!_restored.add(id)) return;
    unawaited(_persistRestored());
  }

  Future<void> _persistRestored() async {
    try {
      await _restoredStore.save({..._restored});
    } catch (_) {
      // Persistence is best effort; the in-memory set stays authoritative.
    }
  }

  Future<void> _loadRestored() async {
    if (_restoredLoaded) return;
    _restoredLoaded = true;
    try {
      _restored.addAll((await _restoredStore.load()).map(_canonicalId));
    } catch (_) {
      // Unreadable store: start from what this process saw.
    }
  }

  /// Ids of peripherals the platform reported connected without a connect
  /// from ble_shield, as known to this process. Includes persisted ids
  /// once [restoredDevices] ran.
  Set<String> get restoredIds => Set.unmodifiable(_restored);

  /// Restored peripherals of this and earlier launches (persisted through the
  /// [RestoredIdStore]), each with its current connection state queried from
  /// the platform. A disconnected one is returned too: turn
  /// [ShieldDevice.setAutoReconnect] on to bring it back.
  Future<List<ShieldDevice>> restoredDevices() async {
    _start();
    await _loadRestored();
    final result = <ShieldDevice>[];
    for (final id in _restored.toList()) {
      final device = this.device(id);
      var connected = device.isConnected;
      if (!connected) {
        try {
          connected = await BleShieldNative.getConnectionState(id,
                  timeout: gattTimeout) ==
              BleConnectionState.connected;
        } catch (_) {
          connected = false;
        }
        // Apple re-adopts restored peripherals natively, so they are usable;
        // elsewhere this engine still has to attach its own GATT client.
        if (connected) device._markSystemConnected(needsOwnConnect: !_isIOS);
      }
      result.add(device);
    }
    return result;
  }

  /// Removes [remoteId] from the restored ids and the store.
  Future<void> forgetRestoredId(String remoteId) async {
    await _loadRestored();
    if (_restored.remove(_canonicalId(remoteId))) {
      await _persistRestored();
    }
  }

  // ----------------------------------------------------------------- system

  /// Services seen in advertisements, per device, across scan sessions.
  final Map<String, Set<String>> _advertisedServices = {};

  /// Devices the OS reports connected (by any app) that offer one of
  /// [withServices]. Not filtered by owner.
  ///
  /// They come back with [ShieldDevice.isConnected] true. This engine has no
  /// GATT client for them yet: call [ShieldDevice.connect], which attaches
  /// one at once because the link already exists.
  ///
  /// Android: [withServices] is not passed to the platform, because
  /// the native layer then connects to every device to discover its services.
  /// The native layer reports no services there, so the filter uses
  /// what ble_shield knows (advertised and previously discovered services)
  /// and keeps devices whose services are unknown.
  Future<List<ShieldDevice>> systemDevices({
    required List<String> withServices,
  }) async {
    final wanted = withServices.map(canonicalUuid).toSet();
    _start();
    final List<BleDevice> found;
    try {
      found = await _mutex.protect(() => BleShieldNative.getSystemDevices(
            withServices: _isAndroid ? null : wanted.toList(),
            timeout: gattTimeout,
          ));
    } catch (e) {
      throw _map(e, ShieldOperation.other);
    }
    final result = <ShieldDevice>[];
    for (final d in found) {
      final id = _canonicalId(d.deviceId);
      if (_isAndroid && wanted.isNotEmpty) {
        final known = <String>{
          for (final u in d.services) BleUuidParser.stringOrNull(u) ?? u,
          ...?_advertisedServices[id],
          ...?_devices[id]?._lastKnownServices,
        };
        if (known.isNotEmpty && !known.any(wanted.contains)) continue;
      }
      final device = this.device(id);
      if (!device.isConnected || device._needsOwnConnect) {
        device._markSystemConnected(needsOwnConnect: true);
      }
      result.add(device);
    }
    return result;
  }

  /// Installs listeners and starts tracking the adapter (first native call).
  void _start() {
    _install();
    if (_adapterSub != null) return;
    _adapterSub = BleShieldNative.availabilityStream.listen(
      (s) {
        // Cache first, so a subscriber released below reads the real state.
        _onAdapter(_mapAdapter(s));
        _markAdapterAnswered();
      },
      onError: (Object _) {},
    );
    _adapterTimer = Timer(adapterStateTimeout, _markAdapterAnswered);
  }

  // ---------------------------------------------------------------- adapter

  final ValueStream<AdapterState> _adapter =
      ValueStream<AdapterState>(AdapterState.unknown);

  /// The platform answered once, or [adapterStateTimeout] ran out. A one-shot
  /// event, not a value: a first answer equal to the seed (`unknown`) changes
  /// nothing in the deduplicating [_adapter].
  bool _adapterAnswered = false;
  final Completer<void> _adapterFirst = Completer<void>();
  Timer? _adapterTimer;

  void _markAdapterAnswered() {
    if (_adapterAnswered) return;
    _adapterAnswered = true;
    _adapterTimer?.cancel();
    _adapterFirst.complete();
  }

  static AdapterState _mapAdapter(AvailabilityState s) => switch (s) {
        AvailabilityState.unknown => AdapterState.unknown,
        AvailabilityState.resetting => AdapterState.resetting,
        AvailabilityState.unsupported => AdapterState.unsupported,
        AvailabilityState.unauthorized => AdapterState.unauthorized,
        AvailabilityState.poweredOff => AdapterState.off,
        AvailabilityState.poweredOn => AdapterState.on,
      };

  void _onAdapter(AdapterState state) {
    final wasOn = _adapter.value == AdapterState.on;
    _adapter.set(state);
    final isOn = state == AdapterState.on;
    if (wasOn != isOn && (isOn || state != AdapterState.unknown)) {
      for (final d in _devices.values.toList()) {
        d._onAdapterChanged(isOn);
      }
    }
    // `unknown` is the manager's start-up state on Apple, not a loss.
    final lost = state != AdapterState.on && state != AdapterState.unknown;
    if (lost && _scanning.value) {
      _failScan(ShieldError(
        ShieldErrorCode.adapterOff,
        'adapter left "on" (${state.name}) during scan',
      ));
    }
  }

  /// Last known adapter state; [AdapterState.unknown] until the platform
  /// answers. Reading it starts adapter tracking.
  AdapterState get adapterStateNow {
    _start();
    return _adapter.value;
  }

  /// Delivers the current state to every new subscriber, then changes.
  ///
  /// Until the platform answers for the first time, the first event is held
  /// back, so a new engine does not report a transient [AdapterState.unknown]
  /// before the real state. If the platform does not answer within
  /// [adapterStateTimeout], the cached state is delivered.
  Stream<AdapterState> get adapterState {
    _start();
    if (_adapterAnswered) return _adapter.stream;
    return Stream<AdapterState>.multi((controller) {
      StreamSubscription<AdapterState>? sub;
      var cancelled = false;
      _adapterFirst.future.then((_) {
        if (cancelled) return;
        sub = _adapter.stream.listen(controller.add, onDone: controller.close);
      });
      controller.onCancel = () {
        cancelled = true;
        return sub?.cancel();
      };
    });
  }

  /// False only when the platform reports no Bluetooth LE support. Waits up
  /// to [wait] for a first definite adapter state.
  Future<bool> isSupported({Duration wait = const Duration(seconds: 3)}) async {
    _start();
    bool definite(AdapterState s) =>
        s != AdapterState.unknown && s != AdapterState.resetting;
    var state = _adapter.value;
    if (!definite(state)) {
      state = await _adapter.stream
          .firstWhere(definite)
          .timeout(wait, onTimeout: () => _adapter.value);
    }
    return state != AdapterState.unsupported;
  }

  /// Asks the OS to turn Bluetooth on (Android with an Activity only).
  ///
  /// Throws [ShieldErrorCode.unsupported] on Apple and when [canTurnOn] is
  /// false, [ShieldErrorCode.operationTimeout] when the OS does not answer
  /// within [turnOnTimeout], and [ShieldErrorCode.adapterOff] when the user
  /// declines. Never hangs.
  Future<void> turnOn() async {
    if (!_isAndroid) {
      throw const ShieldError(
        ShieldErrorCode.unsupported,
        'turnOn is only available on Android',
      );
    }
    if (!canTurnOn) {
      throw const ShieldError(
        ShieldErrorCode.unsupported,
        'turnOn needs a foreground Activity (canTurnOn is false)',
      );
    }
    _start();
    if (_adapter.value == AdapterState.on) return;
    bool accepted;
    try {
      accepted = await BleShieldNative.enableBluetooth(timeout: turnOnTimeout);
    } on TimeoutException {
      throw ShieldError(
        ShieldErrorCode.operationTimeout,
        'enableBluetooth did not answer within $turnOnTimeout '
        '(no foreground Activity?)',
      );
    } catch (e) {
      throw _map(e, ShieldOperation.adapter);
    }
    if (!accepted) {
      throw const ShieldError(
        ShieldErrorCode.adapterOff,
        'the request to turn Bluetooth on was declined',
      );
    }
  }

  // ------------------------------------------------------------------- scan

  final ValueStream<bool> _scanning = ValueStream<bool>(false);
  final ValueStream<List<ScanResult>> _results =
      ValueStream<List<ScanResult>>(const [], distinct: false);
  final Map<String, ScanResult> _seen = {};
  final StreamController<ShieldError> _scanErrors =
      StreamController<ShieldError>.broadcast();
  StreamSubscription<BleDevice>? _scanSub;
  bool _scanStarting = false;
  ShieldError? _pendingScanFailure;
  Duration? _removeIfGone;
  Timer? _watchdogTimer;
  Timer? _pruneTimer;

  /// Scan state kept by ble_shield and reconciled with the native scanner: it
  /// turns false on [stopScan], on a start failure, on a native scanner
  /// failure and when the adapter leaves `on`. It never trusts a native flag.
  /// The [scanWatchdog] warning does not change it.
  bool get isScanningNow => _scanning.value;

  /// Delivers the current value to every new subscriber, then changes.
  Stream<bool> get isScanning => _scanning.stream;

  /// Aggregated list, one entry per device, re-emitted on every advertisement.
  /// Delivers the current list to every new subscriber. Cleared by
  /// [startScan]; kept after [stopScan].
  Stream<List<ScanResult>> get scanResults => _results.stream;

  /// Asynchronous scan failures: start failures, native scanner
  /// failures, [scanWatchdog] warnings and the adapter turning off mid-scan.
  /// Never delivered through [scanResults].
  Stream<ShieldError> get scanErrors => _scanErrors.stream;

  /// Starts scanning.
  ///
  /// Throws [ShieldErrorCode.scanAlreadyStarted] when a scan is running. A
  /// native start failure is thrown to the caller, also emitted on
  /// [scanErrors], and leaves the native scanner stopped.
  ///
  /// With [removeIfGone], devices not seen for that long leave the list.
  Future<void> startScan({
    List<String> withServices = const [],
    ScanMode mode = ScanMode.lowPower,
    Duration? removeIfGone,
  }) async {
    if (_scanning.value || _scanStarting) {
      throw const ShieldError(
        ShieldErrorCode.scanAlreadyStarted,
        'a scan is already running',
      );
    }
    final services = withServices.map(canonicalUuid).toList();
    _start();
    _scanStarting = true;
    _pendingScanFailure = null;
    _scanSub ??= BleShieldNative.scanStream.listen(
      _onAdvertisement,
      onError: _onScanStreamError,
    );
    _seen.clear();
    _results.set(const []);
    _removeIfGone = removeIfGone;
    try {
      await BleShieldNative.startScan(
        scanFilter: ScanFilter(withServices: services),
        platformConfig: PlatformConfig(
          android: AndroidOptions(
              scanMode: switch (mode) {
            ScanMode.lowPower => AndroidScanMode.lowPower,
            ScanMode.balanced => AndroidScanMode.balanced,
            ScanMode.lowLatency => AndroidScanMode.lowLatency,
          }),
        ),
      );
    } catch (e) {
      _scanStarting = false;
      final error = _map(e, ShieldOperation.scan);
      _emitScanError(error);
      await _stopNativeScan();
      throw error;
    }
    _scanStarting = false;
    _scanning.set(true);
    final early = _pendingScanFailure;
    if (early != null) {
      // The native scanner failed before startScan returned.
      _pendingScanFailure = null;
      _failScan(early);
      return;
    }
    _armWatchdog();
    if (removeIfGone != null) {
      final ms = (removeIfGone.inMilliseconds ~/ 4).clamp(50, 1000);
      _pruneTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _prune());
    }
  }

  /// Stops scanning. Idempotent and always sent to the native scanner, even
  /// when ble_shield believes it is already stopped. Never throws: a
  /// native failure goes to [scanErrors].
  Future<void> stopScan() async {
    _endScanSession();
    await _stopNativeScan();
  }

  /// Web only: opens the browser's Bluetooth chooser and returns the device
  /// the user picked. Web Bluetooth has no free scan, so this is how a device
  /// becomes known there; connect it with `device(result.remoteId)`.
  ///
  /// Call it from a user gesture (e.g. a button's `onPressed`) in a secure
  /// context (HTTPS or localhost): the browser rejects it otherwise. List
  /// every service you will use in [withServices] (which also filters the
  /// chooser) or [optionalServices]: the browser blocks GATT access to the
  /// others. [optionalManufacturerData] lists the company ids whose
  /// manufacturer data the page may read.
  ///
  /// Throws [ShieldErrorCode.cancelled] when the user dismisses the chooser,
  /// [ShieldErrorCode.unauthorized] without a user gesture,
  /// [ShieldErrorCode.deviceNotFound] when the browser finds no device, and
  /// [ShieldErrorCode.unsupported] on every platform other than the web, in
  /// browsers without Web Bluetooth and outside a secure context (where the
  /// browser does not expose it). Does not touch the scan session.
  Future<ScanResult> requestDevice({
    List<String> withServices = const [],
    List<String> optionalServices = const [],
    List<int> optionalManufacturerData = const [],
  }) async {
    final services = withServices.map(canonicalUuid).toList();
    final optional = optionalServices.map(canonicalUuid).toList();
    _install();
    final BleDevice d;
    try {
      // Only the web options are passed: without `apple`, the Android and
      // Darwin channel throws notSupported without calling the plugin.
      d = await BleShieldNative.requestDevice(
        scanFilter: ScanFilter(withServices: services),
        platformConfig: PickerPlatformConfig(
          web: WebOptions(
            optionalServices: optional,
            optionalManufacturerData: optionalManufacturerData,
          ),
        ),
      );
    } catch (e) {
      throw _map(e, ShieldOperation.picker);
    }
    return _scanResultOf(d);
  }

  ScanResult _scanResultOf(BleDevice d) => ScanResult(
        remoteId: _canonicalId(d.deviceId),
        name: (d.rawName ?? d.name ?? '').trim(),
        rssi: d.rssi ?? -127,
        connectable: d.connectable ?? true,
        manufacturerData: {
          for (final m in d.manufacturerDataList)
            m.companyId: m.payload.toList(),
        },
        serviceUuids: [
          for (final u in d.services) BleUuidParser.stringOrNull(u) ?? u,
        ],
        serviceData: {
          for (final e in d.serviceData.entries) e.key: e.value.toList(),
        },
        lastSeen: DateTime.now(),
      );

  void _onAdvertisement(BleDevice d) {
    if (!_scanning.value) return;
    final id = _canonicalId(d.deviceId);
    _seen[id] = _scanResultOf(d);
    if (d.services.isNotEmpty) {
      (_advertisedServices[id] ??= {}).addAll(_seen[id]!.serviceUuids);
    }
    _results.set(List.unmodifiable(_seen.values));
    _armWatchdog();
  }

  /// A native scanner failure (Pigeon `onScanFailed`) arrives as an error on
  /// the scan stream. During [startScan] it is held until the start returns.
  void _onScanStreamError(Object e) {
    final error = _map(e, ShieldOperation.scan);
    if (_scanStarting) {
      _pendingScanFailure ??= error;
      return;
    }
    _failScan(error);
  }

  /// Warns, never ends the session: re-armed after every window.
  void _armWatchdog() {
    _watchdogTimer?.cancel();
    final window = scanWatchdog;
    if (window == null || !_scanning.value) return;
    _watchdogTimer = Timer(window, () {
      if (!_scanning.value) return;
      _emitScanError(ShieldError(
        ShieldErrorCode.scanFailed,
        'no advertisement within $window (scan kept running)',
      ));
      _armWatchdog();
    });
  }

  void _prune() {
    final window = _removeIfGone;
    if (window == null) return;
    final limit = DateTime.now().subtract(window);
    final before = _seen.length;
    _seen.removeWhere((_, r) => r.lastSeen.isBefore(limit));
    if (_seen.length != before) _results.set(List.unmodifiable(_seen.values));
  }

  /// Ends the session, reports [error] and leaves the native scanner stopped.
  void _failScan(ShieldError error) {
    if (!_scanning.value) return;
    _endScanSession();
    _emitScanError(error);
    unawaited(_stopNativeScan());
  }

  void _endScanSession() {
    _scanning.set(false);
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
  }

  Future<void> _stopNativeScan() async {
    try {
      _install();
      await BleShieldNative.stopScan();
    } catch (e) {
      _emitScanError(_map(e, ShieldOperation.scan));
    }
  }

  void _emitScanError(ShieldError error) {
    if (!_scanErrors.isClosed) _scanErrors.add(error);
  }

  // ---------------------------------------------------------------- devices

  final GattMutex _mutex = GattMutex();
  final Map<String, ShieldDevice> _devices = {};

  /// The device with [remoteId] (any case). Same instance until its
  /// [ShieldDevice.dispose]. Makes no native call.
  ShieldDevice device(String remoteId) {
    _install();
    final id = _canonicalId(remoteId);
    return _devices.putIfAbsent(id, () {
      final device = ShieldDevice._(this, id);
      // A connection reported before the device existed (e.g. restoration).
      if (_knownConnected.contains(id)) device._setConnected(true);
      return device;
    });
  }

  // -------------------------------------------------------------- disposal

  /// Stops listening to the native layer. The instance is unusable afterwards.
  Future<void> dispose() async {
    _endScanSession();
    for (final d in _devices.values.toList()) {
      await d.dispose();
    }
    await _scanSub?.cancel();
    await _adapterSub?.cancel();
    _markAdapterAnswered(); // release subscribers still waiting
    await _adapter.close();
    await _scanning.close();
    await _results.close();
    await _scanErrors.close();
  }
}
