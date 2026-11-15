import 'dart:async';

import 'package:ble_shield/ble_shield.dart';
import 'package:flutter/foundation.dart';
// ble_shield's ConnectionState clashes with Flutter's AsyncSnapshot one.
// Flutter 3.50 deprecates this library in favour of package:material_ui; the
// example keeps it so it still builds on the package's minimum Flutter.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' hide ConnectionState;

/// Identifier this demo claims for iOS state restoration. Restoration is
/// opt-in: without this call no engine restores.
const restorationId = 'io.github.tganzerli.ble_shield_example.central';

void main() => runApp(const DemoApp());

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  final BleShield shield = BleShield();

  @override
  void dispose() {
    unawaited(shield.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ble_shield demo',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: ScanPage(shield: shield),
      );
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.shield});

  final BleShield shield;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  String? _restoration;

  BleShield get shield => widget.shield;

  Future<void> _toggleScan() async {
    try {
      if (shield.isScanningNow) {
        await shield.stopScan();
      } else {
        await shield.startScan(mode: ScanMode.lowLatency);
      }
    } on ShieldError catch (e) {
      _show('Scan: ${e.code.name} ${e.message}');
    }
  }

  Future<void> _configureRestoration() async {
    final granted = await shield.configureRestoration(restorationId);
    setState(() => _restoration = granted
        ? 'granted; restored ids: ${shield.restoredIds.join(', ')}'
        : 'not granted (not iOS, no bluetooth-central, or already created)');
  }

  void _show(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: StreamBuilder<AdapterState>(
            stream: shield.adapterState,
            initialData: shield.adapterStateNow,
            builder: (_, s) => Text('Adapter: ${s.data?.name}'),
          ),
          actions: [
            if (defaultTargetPlatform == TargetPlatform.iOS)
              IconButton(
                tooltip: 'Configure restoration',
                icon: const Icon(Icons.restore),
                onPressed: _configureRestoration,
              ),
          ],
        ),
        floatingActionButton: StreamBuilder<bool>(
          stream: shield.isScanning,
          initialData: shield.isScanningNow,
          builder: (_, s) => FloatingActionButton.extended(
            onPressed: _toggleScan,
            icon: Icon(s.data! ? Icons.stop : Icons.search),
            label: Text(s.data! ? 'Stop' : 'Scan'),
          ),
        ),
        body: Column(
          children: [
            if (_restoration != null)
              ListTile(
                  title: const Text('Restoration'),
                  subtitle: Text(_restoration!)),
            Expanded(
              child: StreamBuilder<List<ScanResult>>(
                stream: shield.scanResults,
                initialData: const [],
                builder: (_, s) => ListView(
                  children: [
                    for (final r in s.data!)
                      ListTile(
                        title: Text(r.name.isEmpty ? '(no name)' : r.name),
                        subtitle: Text(r.remoteId),
                        trailing: Text('${r.rssi} dBm'),
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) =>
                              DevicePage(device: shield.device(r.remoteId)),
                        )),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.device});

  final ShieldDevice device;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  List<ShieldService> _services = const [];
  final Map<String, String> _values = {};
  final List<StreamSubscription<List<int>>> _subs = [];

  ShieldDevice get device => widget.device;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on ShieldError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${e.code.name}: ${e.message}')));
      }
    }
  }

  Future<void> _connect() => _run(() async {
        await device.connect();
        final services = await device.discoverServices();
        setState(() => _services = services);
      });

  Future<void> _notify(ShieldCharacteristic c) => _run(() async {
        _subs.add(c.onValueReceived.listen((v) => setState(() =>
            _values[c.uuid] =
                v.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '))));
        await c.setNotify(true);
      });

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(device.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(device.remoteId)),
        body: StreamBuilder<ConnectionState>(
          stream: device.connectionState,
          builder: (_, s) {
            final connected = s.data == ConnectionState.connected;
            return ListView(
              children: [
                ListTile(
                  title: Text(connected ? 'Connected' : 'Disconnected'),
                  trailing: FilledButton(
                    onPressed:
                        connected ? () => _run(device.disconnect) : _connect,
                    child: Text(connected ? 'Disconnect' : 'Connect'),
                  ),
                ),
                for (final service in _services)
                  ExpansionTile(
                    title: Text(service.uuid),
                    children: [
                      for (final c in service.characteristics)
                        ListTile(
                          dense: true,
                          title: Text(c.uuid),
                          subtitle: Text(_values[c.uuid] ?? ''),
                          trailing: c.canNotify
                              ? IconButton(
                                  icon: const Icon(Icons.notifications_active),
                                  onPressed: () => _notify(c),
                                )
                              : null,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      );
}
