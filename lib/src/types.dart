import 'dart:async';

import 'errors.dart';

/// State of the Bluetooth adapter.
///
/// The native layer has no "turning on/off" states; [resetting] is Apple's
/// transient state while the stack restarts.
enum AdapterState { unknown, resetting, unsupported, unauthorized, off, on }

/// Scan mode. Apple ignores it.
enum ScanMode { lowPower, balanced, lowLatency }

/// Connection state of a device as seen by ble_shield.
enum ConnectionState { disconnected, connected }

/// One entry of the aggregated scan list (one per remote id).
class ScanResult {
  const ScanResult({
    required this.remoteId,
    required this.name,
    required this.rssi,
    required this.connectable,
    required this.manufacturerData,
    required this.serviceUuids,
    required this.serviceData,
    required this.lastSeen,
  });

  /// The device id: lower-case MAC on Android, lower-case CoreBluetooth UUID
  /// on Apple, and the browser's opaque, case-sensitive id (verbatim) on the
  /// web.
  final String remoteId;

  /// Name reported by the platform for this advertisement, empty if none.
  ///
  /// Android: the resolved device name. Apple: the advertised local name,
  /// falling back to the peripheral's cached GATT name. The native layer does not
  /// expose the two separately.
  final String name;

  /// Signal strength; -127 when the platform reported none.
  final int rssi;

  /// True unless the platform said otherwise.
  final bool connectable;

  /// companyId → payload (without the two companyId bytes). When an
  /// advertisement carries the same companyId twice, the last one wins.
  final Map<int, List<int>> manufacturerData;

  /// Advertised service UUIDs, canonical form.
  final List<String> serviceUuids;

  /// Service data keyed by canonical service UUID.
  final Map<String, List<int>> serviceData;

  /// When this device was last seen by the scanner.
  final DateTime lastSeen;

  @override
  String toString() => 'ScanResult($remoteId, "$name", $rssi)';
}

/// What happened to an armed reconnection attempt.
enum ReconnectOutcome { fired, skipped, failed }

/// Why the attempt was armed.
enum ReconnectOrigin {
  /// `setAutoReconnect(true)` on a disconnected device (incl. initial state).
  kick,

  /// The device dropped (connected → disconnected).
  drop,

  /// A previous attempt failed.
  retry,

  /// The adapter came back on while the device was disconnected.
  adapterOn,
}

/// Why an armed attempt was skipped.
enum ReconnectSkipReason { disposed, disabled, superseded, adapterOff }

/// One reconnection event, for logging.
class ReconnectEvent {
  const ReconnectEvent(
    this.remoteId,
    this.outcome,
    this.origin, {
    this.skipReason,
    this.error,
  });

  final String remoteId;
  final ReconnectOutcome outcome;
  final ReconnectOrigin origin;

  /// Set when [outcome] is [ReconnectOutcome.skipped].
  final ReconnectSkipReason? skipReason;

  /// Set when [outcome] is [ReconnectOutcome.failed].
  final ShieldError? error;

  /// `disposed` | `disabled` | `superseded` | `adapter-off` | error message.
  String? get reason => switch (skipReason) {
        ReconnectSkipReason.disposed => 'disposed',
        ReconnectSkipReason.disabled => 'disabled',
        ReconnectSkipReason.superseded => 'superseded',
        ReconnectSkipReason.adapterOff => 'adapter-off',
        null => error?.message,
      };

  @override
  String toString() => '[Reconnect] $remoteId ${outcome.name} '
      'origin=${origin.name}${reason == null ? '' : ' reason=$reason'}';
}

/// Persistence for ids of peripherals the OS restored as connected.
///
/// ble_shield ships no storage plugin: the default [InMemoryRestoredIdStore]
/// forgets everything when the process dies. Apps that need the ids across
/// launches implement this over their own storage.
abstract interface class RestoredIdStore {
  Future<Set<String>> load();
  Future<void> save(Set<String> ids);
}

/// Default [RestoredIdStore]: process memory only.
class InMemoryRestoredIdStore implements RestoredIdStore {
  Set<String> _ids = {};

  @override
  Future<Set<String>> load() async => {..._ids};

  @override
  Future<void> save(Set<String> ids) async => _ids = {...ids};
}

/// Opts the engine into iOS central state restoration. The default calls
/// `BleShieldNativeDarwinCentral.configureRestoration`.
typedef RestorationConfigurator = Future<bool> Function(String identifier);

/// Verbosity of the native layer's own logs ([BleShield.setNativeLogLevel]):
/// logcat tag `BleShieldNative` on Android, stdout on Apple. Each level
/// includes the ones before it.
enum ShieldLogLevel { none, error, warning, info, debug, verbose }

/// Connection parameters of a link, as the Android controller reports them
/// (API 26+). Apple exposes none.
class ShieldConnectionParameters {
  const ShieldConnectionParameters({
    required this.interval,
    required this.latency,
    required this.supervisionTimeout,
  });

  /// Time between connection events (the link's pace for notifications).
  final Duration interval;

  /// Connection events the peripheral may skip.
  final int latency;

  /// How long without traffic before the link is considered lost.
  final Duration supervisionTimeout;

  @override
  bool operator ==(Object other) =>
      other is ShieldConnectionParameters &&
      other.interval == interval &&
      other.latency == latency &&
      other.supervisionTimeout == supervisionTimeout;

  @override
  int get hashCode => Object.hash(interval, latency, supervisionTimeout);

  @override
  String toString() => 'ShieldConnectionParameters(interval: '
      '${interval.inMicroseconds / 1000} ms, latency: $latency, '
      'supervisionTimeout: ${supervisionTimeout.inMilliseconds} ms)';
}
