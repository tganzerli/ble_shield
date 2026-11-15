import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_shield/src/native/ble_shield_native.g.dart';
import 'package:ble_shield/src/native/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = 'dev.flutter.pigeon.ble_shield.'
      'BleShieldNativeDarwinCentralChannel.configureRestoration';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final codec = BleShieldNativeDarwinCentralChannel.pigeonChannelCodec;

  final calls = <String>[];
  void mockReply(bool granted) {
    messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(channel, codec), (message) async {
      calls.add((message as List)[0] as String);
      return <Object?>[granted];
    });
  }

  tearDown(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(channel, codec), null);
  });

  test('iOS forwards the identifier and returns the native verdict', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    mockReply(true);
    expect(await BleShieldNativeDarwinCentral.configureRestoration('app.bg'),
        kIsWeb ? isFalse : isTrue);
    mockReply(false);
    expect(await BleShieldNativeDarwinCentral.configureRestoration('app.bg'),
        isFalse);
    expect(calls, kIsWeb ? isEmpty : ['app.bg', 'app.bg']);
  });

  test('other platforms never reach the native channel', () async {
    mockReply(true);
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(await BleShieldNativeDarwinCentral.configureRestoration('app.bg'),
          isFalse);
    }
    expect(calls, isEmpty);
  });

  test('empty identifier is rejected before the platform check', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await expectLater(BleShieldNativeDarwinCentral.configureRestoration('  '),
        throwsArgumentError);
  });
}
