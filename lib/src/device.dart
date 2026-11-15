part of 'ble_shield.dart';

/// A peripheral. Obtained from [BleShield.device]; the same instance is
/// returned for the same remote id until [dispose].
class ShieldDevice {
  ShieldDevice._(this._shield, this.remoteId);

  final BleShield _shield;

  /// Lower-case canonical id: MAC on Android, CoreBluetooth UUID on Apple.
  final String remoteId;

  final ValueStream<ConnectionState> _state =
      ValueStream<ConnectionState>(ConnectionState.disconnected);

  bool _disposed = false;
  bool _connecting = false;

  /// Bumped by [disconnect] and [dispose]; a direct connect that sees it
  /// change gives up.
  int _connectGeneration = 0;

  /// Error details of the last disconnection event (native status).
  BleConnectionChange? _lastFailure;

  // ------------------------------------------------------------------ state

  /// Synchronous and coherent with [connectionState].
  bool get isConnected => _state.value == ConnectionState.connected;

  /// Delivers the current state to every new subscriber, then changes.
  Stream<ConnectionState> get connectionState => _state.stream;

  /// A connect started by ble_shield is running or pending.
  bool get _initiatedByShield => _connecting || _attemptPending;

  /// Connected per the OS, but this engine has no GATT client yet
  /// ([BleShield.systemDevices]).
  bool _needsOwnConnect = false;

  void _markSystemConnected({required bool needsOwnConnect}) {
    _needsOwnConnect = needsOwnConnect;
    _setConnected(true);
  }

  void _onConnectionChange(BleConnectionChange change) {
    if (_disposed) return;
    if (!change.isConnected) {
      _forgetConnection();
      _needsOwnConnect = false;
    }
    if (!change.isConnected && change.error != null) _lastFailure = change;
    final wasConnected = isConnected;
    _setConnected(change.isConnected);
    if (!change.isConnected && wasConnected) _onDropped();
  }

  void _setConnected(bool connected) {
    _state.set(
        connected ? ConnectionState.connected : ConnectionState.disconnected);
    if (connected) _onConnected();
  }

  void _onConnected() {
    _connectionEpoch++;
    _attemptPending = false;
    _needsRelease = false;
    _rearmSuspended = false; // a new session: its drops re-arm again
    _cancelArmed(ReconnectSkipReason.superseded);
  }

  void _onDropped() {
    if (_autoReconnect && !_rearmSuspended) _arm(ReconnectOrigin.drop);
  }

  // ------------------------------------------------------------------- GATT

  /// Bumped on every connection; discovery results of an older one are
  /// never cached.
  int _connectionEpoch = 0;
  List<ShieldService>? _services;

  /// Service UUIDs of the last discovery, kept across connections; only used
  /// to filter [BleShield.systemDevices].
  Set<String> _lastKnownServices = const {};
  Future<List<ShieldService>>? _discovering;
  final Set<String> _notifying = {};

  void _forgetConnection() {
    _services = null;
    _discovering = null;
    _notifying.clear();
  }

  /// Services of the current connection. The first call of every connection
  /// runs a real native discovery; later calls return its result until the
  /// device disconnects. Concurrent calls share one discovery.
  Future<List<ShieldService>> discoverServices({Duration? timeout}) {
    _checkAlive();
    if (!isConnected) {
      return Future.error(ShieldError(
          ShieldErrorCode.notConnected, '$remoteId is not connected'));
    }
    final cached = _services;
    if (cached != null) return Future.value(cached);
    final epoch = _connectionEpoch;
    final t = timeout ?? _shield.gattTimeout;
    return _discovering ??= _gatt(
      ShieldOperation.discover,
      () => BleShieldNative.discoverServices(remoteId, timeout: t),
    ).then((native) {
      final services = List<ShieldService>.unmodifiable(native.map((s) {
        final serviceUuid = canonicalUuid(s.uuid);
        return ShieldService._(
          serviceUuid,
          List.unmodifiable(s.characteristics.map((c) => ShieldCharacteristic._(
              this, serviceUuid, canonicalUuid(c.uuid), c.properties))),
        );
      }));
      _lastKnownServices = {for (final s in services) s.uuid};
      if (epoch == _connectionEpoch && isConnected) _services = services;
      return services;
    }).whenComplete(() {
      if (epoch == _connectionEpoch) _discovering = null;
    });
  }

  /// Runs a GATT operation under the global lock, on a connected
  /// device, mapping every error.
  Future<T> _gatt<T>(ShieldOperation op, Future<T> Function() body) async {
    _checkAlive();
    if (!isConnected) {
      throw ShieldError(
          ShieldErrorCode.notConnected, '$remoteId is not connected');
    }
    return _shield._mutex.protect(() async {
      if (!isConnected) {
        throw ShieldError(
            ShieldErrorCode.notConnected, '$remoteId is not connected');
      }
      try {
        return await body();
      } catch (e) {
        throw _shield._map(e, op);
      }
    });
  }

  // ------------------------------------------------------------ connection

  ConnectionPlatformConfig get _connectionConfig => ConnectionPlatformConfig(
        android: AndroidConnectionOptions(
            closeGattOnDetach: _shield.closeGattOnDetach),
      );

  /// Direct connection. Completes connected or throws [ShieldError].
  ///
  /// - [ShieldErrorCode.connectInProgress] if a `connect` for this device is
  ///   already running or waiting; nothing is queued.
  /// - [ShieldErrorCode.connectTimeout] after [timeout]; the native attempt is
  ///   cancelled with a disconnect.
  /// - Any failure releases the native GATT client.
  ///
  /// Runs under the global GATT lock, so it waits for and blocks the GATT
  /// operations of every other device.
  Future<void> connect({
    Duration timeout = const Duration(seconds: 35),
  }) async {
    _checkAlive();
    if (_connecting) {
      throw ShieldError(
        ShieldErrorCode.connectInProgress,
        'connect already in progress for $remoteId',
      );
    }
    if (isConnected && !_needsOwnConnect) return;
    _connecting = true;
    final generation = _connectGeneration;
    try {
      _shield._start();
      await _shield._mutex.protect(() async {
        if (generation != _connectGeneration || _disposed) {
          throw const ShieldError(
            ShieldErrorCode.connectFailed,
            'connect cancelled by disconnect',
          );
        }
        if (isConnected && !_needsOwnConnect) return;
        await _connectLocked(timeout, generation);
      });
    } finally {
      _connecting = false;
    }
  }

  /// Native connect; caller holds the GATT lock.
  Future<void> _connectLocked(Duration timeout, int generation) async {
    _lastFailure = null;
    try {
      await BleShieldNative.connect(
        remoteId,
        timeout: timeout,
        platformConfig: _connectionConfig,
      );
    } on TimeoutException {
      await _releaseNative();
      throw ShieldError(
        ShieldErrorCode.connectTimeout,
        'no connection to $remoteId within $timeout',
        platform: _shield._platformName,
      );
    } catch (e) {
      await _releaseNative();
      if (generation != _connectGeneration) {
        throw const ShieldError(
          ShieldErrorCode.connectFailed,
          'connect cancelled by disconnect',
        );
      }
      throw _shield._map(e, ShieldOperation.connect,
          nativeCode: _lastFailure?.nativeErrorCode);
    }
    _needsOwnConnect = false;
    _setConnected(true);
  }

  /// Cancels a native attempt and releases the GATT client. Never throws.
  Future<void> _releaseNative() async {
    try {
      await BleShieldNative.disconnect(remoteId,
          timeout: _shield.releaseTimeout);
    } catch (_) {
      // The native layer already swallows and logs disconnect failures.
    }
  }

  /// Commanded disconnection; also releases the native GATT client.
  ///
  /// Cancels an armed or pending auto-reconnect attempt first, except in
  /// one case: with the default [rearm], on a device that is not connected and
  /// has no `connect` in flight, while [autoReconnect] is on, an attempt armed
  /// by a drop, a retry or the adapter coming back on is left alone. Nothing is
  /// cancelled and no native disconnect is issued, so the reconnection of that
  /// link loss survives. To stop it, pass `rearm: false` or turn
  /// [autoReconnect] off first. A drop not yet reported to the app counts as
  /// connected.
  ///
  /// On a connected device, if [autoReconnect] stays on, the drop this causes
  /// re-arms reconnection, unless [rearm] is false: then nothing arms
  /// reconnection (not the drop, not the adapter coming back on) until the
  /// device connects again by any path, or until [setAutoReconnect] is called.
  /// [autoReconnect] stays on, so a drop of the next session re-arms as usual.
  /// No timer is involved: the next connection is up to the app. A later
  /// `disconnect()` with the default [rearm] does not lift the suspension. If
  /// the disconnect throws and the device is still connected, there is no
  /// suspension: that session's drops re-arm, including a late drop of this
  /// same disconnect after a timeout (retry it if needed).
  ///
  /// A `connect` in flight is cancelled at once (it does not wait behind the
  /// GATT lock) and fails with [ShieldErrorCode.connectFailed].
  Future<void> disconnect({
    Duration timeout = const Duration(seconds: 35),
    bool rearm = true,
  }) async {
    _checkAlive();
    // No session to end, and the default keeps reconnection: leave the
    // attempt of the link loss alone (no cancel, no native disconnect).
    if (rearm && _keepsLinkLossAttempt()) return;
    _connectGeneration++;
    // Before any await, so the drop this causes already sees it.
    if (!rearm) _rearmSuspended = true;
    _beforeDisconnect();
    _shield._start();
    if (_connecting) {
      // Abort the attempt that holds (or waits for) the lock.
      await _releaseNative();
      return;
    }
    try {
      await _shield._mutex.protect(() async {
        try {
          await BleShieldNative.disconnect(remoteId, timeout: timeout);
        } catch (e) {
          throw _shield._map(e, ShieldOperation.disconnect);
        }
      });
      if (isConnected) {
        throw ShieldError(
          ShieldErrorCode.operationTimeout,
          '$remoteId still connected $timeout after disconnect',
          platform: _shield._platformName,
        );
      }
    } catch (_) {
      // The session survived: its real drops must still re-arm.
      if (!rearm && isConnected) _rearmSuspended = false;
      rethrow;
    }
  }

  static const _linkLossOrigins = {
    ReconnectOrigin.drop,
    ReconnectOrigin.retry,
    ReconnectOrigin.adapterOn,
  };

  /// A default `disconnect()` on a device with no link must not cancel the
  /// reconnection a link loss armed.
  bool _keepsLinkLossAttempt() {
    if (isConnected || _connecting || !_autoReconnect) return false;
    if (_armTimer != null) return _linkLossOrigins.contains(_armOrigin);
    if (_attemptPending) return _linkLossOrigins.contains(_pendingOrigin);
    return false;
  }

  void _beforeDisconnect() {
    _cancelArmed(ReconnectSkipReason.superseded);
    // The native disconnect that follows also cancels a pending request.
    _attemptGeneration++;
    _attemptPending = false;
    _needsRelease = false;
  }

  // ----------------------------------------------------------- reconnection

  bool _autoReconnect = false;
  Duration _reconnectDelay = const Duration(seconds: 3);
  Timer? _armTimer;
  ReconnectOrigin _armOrigin = ReconnectOrigin.kick;

  /// A reconnection request was handed to the OS and has not resolved.
  bool _attemptPending = false;

  /// Origin of the request pending in the OS (valid while [_attemptPending]).
  ReconnectOrigin _pendingOrigin = ReconnectOrigin.kick;

  /// A pending request was forgotten (adapter cycled) and may still exist
  /// natively; release it before issuing another.
  bool _needsRelease = false;
  int _attemptGeneration = 0;

  /// Set by `disconnect(rearm: false)`: nothing arms reconnection until the
  /// next connection or an explicit [setAutoReconnect].
  bool _rearmSuspended = false;

  final StreamController<ReconnectEvent> _reconnectEvents =
      StreamController<ReconnectEvent>.broadcast();

  /// Whether ble_shield keeps this device reconnecting.
  bool get autoReconnect => _autoReconnect;

  /// Every armed attempt: fired, skipped (with reason) or failed. For logs.
  Stream<ReconnectEvent> get reconnectEvents => _reconnectEvents.stream;

  /// Turns reconnection kept by ble_shield on or off.
  ///
  /// Enabled on a disconnected device, including one that never connected,
  /// an attempt is armed after [delay] (the "kick"); after every drop
  /// (connected → disconnected) another is armed. When the delay ends the
  /// attempt is skipped if meanwhile the device connected, received
  /// [disconnect], was disposed, had this turned off, or the adapter is not
  /// `on`. A failed attempt is reported on [reconnectEvents], never thrown,
  /// and re-armed. When the adapter comes back on, a disconnected device is
  /// re-armed too.
  ///
  /// The attempt is a pending OS request with no timeout: Android uses
  /// `autoConnect`; Apple uses a plain CoreBluetooth connect, which does not
  /// expire, re-issued by ble_shield after each drop (iOS 17+ hides drops of
  /// `autoConnect` peripherals from the app). It is issued under the GATT
  /// lock but does not hold it while pending.
  ///
  /// Turning it off cancels an armed attempt but leaves a pending OS request
  /// alone; [disconnect] cancels that (with this off, a `disconnect()` always
  /// does).
  ///
  /// After `disconnect(rearm: false)` no attempt is armed until the next
  /// connection or until this is called again; calling it lifts that
  /// suspension (and, enabled on a disconnected device, kicks as above).
  void setAutoReconnect(
    bool enabled, {
    Duration delay = const Duration(seconds: 3),
  }) {
    _checkAlive();
    _reconnectDelay = delay;
    _rearmSuspended = false; // explicit request from the app
    if (!enabled) {
      _autoReconnect = false;
      _cancelArmed(ReconnectSkipReason.disabled);
      return;
    }
    _autoReconnect = true;
    _shield._start();
    if (!isConnected && _armTimer == null && !_attemptPending) {
      _arm(ReconnectOrigin.kick);
    }
  }

  void _arm(ReconnectOrigin origin) {
    if (_disposed) return;
    _armTimer?.cancel();
    _armOrigin = origin;
    _armTimer = Timer(_reconnectDelay, _fire);
  }

  void _cancelArmed(ReconnectSkipReason reason) {
    final timer = _armTimer;
    if (timer == null) return;
    timer.cancel();
    _armTimer = null;
    _emit(ReconnectEvent(remoteId, ReconnectOutcome.skipped, _armOrigin,
        skipReason: reason));
  }

  void _emit(ReconnectEvent event) {
    if (!_reconnectEvents.isClosed) _reconnectEvents.add(event);
  }

  void _fire() {
    _armTimer = null;
    final origin = _armOrigin;
    ReconnectSkipReason? skip;
    if (!_autoReconnect) {
      skip = ReconnectSkipReason.disabled;
    } else if (isConnected || _connecting || _attemptPending) {
      skip = ReconnectSkipReason.superseded;
    } else if (_shield._adapter.value != AdapterState.on) {
      skip = ReconnectSkipReason.adapterOff;
    }
    if (skip != null) {
      _emit(ReconnectEvent(remoteId, ReconnectOutcome.skipped, origin,
          skipReason: skip));
      return;
    }
    _emit(ReconnectEvent(remoteId, ReconnectOutcome.fired, origin));
    unawaited(_attempt(origin));
  }

  Future<void> _attempt(ReconnectOrigin origin) async {
    _attemptPending = true;
    _pendingOrigin = origin;
    final generation = ++_attemptGeneration;
    final outcome = Completer<Object?>(); // null = connected
    try {
      if (_needsRelease) {
        _needsRelease = false;
        await _releaseNative();
      }
      await _shield._mutex.protect(() async {
        if (generation != _attemptGeneration || _disposed) return;
        // The request is issued synchronously by the native layer; the lock is
        // released without waiting for it to resolve.
        unawaited(BleShieldNative.connect(
          remoteId,
          timeout: _shield.pendingConnectWindow,
          autoConnect: _shield._isAndroid,
          platformConfig: _connectionConfig,
        ).then((_) => outcome.complete(null),
            onError: (Object e) => outcome.complete(e)));
      });
    } catch (e) {
      if (!outcome.isCompleted) outcome.complete(e);
    }
    if (!outcome.isCompleted && generation != _attemptGeneration) return;
    final error = await outcome.future;
    if (error == null) return; // connected; state came through the listener
    if (error is TimeoutException) return; // still pending in the OS
    if (generation != _attemptGeneration || _disposed) return; // superseded
    _attemptPending = false;
    _emit(ReconnectEvent(remoteId, ReconnectOutcome.failed, origin,
        error: _shield._map(error, ShieldOperation.connect,
            nativeCode: _lastFailure?.nativeErrorCode)));
    await _releaseNative();
    if (_autoReconnect && !isConnected && !_disposed && _armTimer == null) {
      _arm(ReconnectOrigin.retry);
    }
  }

  /// Called by [BleShield] on adapter transitions.
  void _onAdapterChanged(bool on) {
    if (_disposed) return;
    if (!on) {
      if (_attemptPending) {
        _attemptPending = false;
        _needsRelease = true;
        _attemptGeneration++;
      }
      return;
    }
    if (_autoReconnect &&
        !_rearmSuspended &&
        !isConnected &&
        _armTimer == null &&
        !_attemptPending) {
      _arm(ReconnectOrigin.adapterOn);
    }
  }

  // -------------------------------------------------------------- lifecycle

  void _checkAlive() {
    if (_disposed) {
      throw ShieldError(
        ShieldErrorCode.invalidArgument,
        'device $remoteId was disposed',
      );
    }
  }

  /// Releases this instance; [BleShield.device] returns a new one afterwards.
  /// Does not disconnect: call [disconnect] first if needed.
  Future<void> dispose() async {
    if (_disposed) return;
    _connectGeneration++;
    _onDispose();
    _disposed = true;
    _shield._devices.remove(remoteId);
    await _state.close();
  }

  void _onDispose() {
    _cancelArmed(ReconnectSkipReason.disposed);
    _attemptGeneration++;
    if (_attemptPending) {
      _attemptPending = false;
      unawaited(_releaseNative());
    }
    unawaited(_reconnectEvents.close());
  }

  @override
  String toString() => 'ShieldDevice($remoteId, ${_state.value.name})';
}
