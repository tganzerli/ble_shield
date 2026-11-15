import 'package:flutter_test/flutter_test.dart';
import 'package:ble_shield/src/native/utils/ble_shield_native_stream_controller.dart';

void main() {
  group("Test BleShieldNativeStreamController", () {
    test('Auto Dispose Stream', () {
      var streamController = BleShieldNativeStreamController<int>();
      expect(true, streamController.isClosed);

      // Stream should auto initialize on first subscription
      var subscription = streamController.stream.listen((data) {});
      expect(false, streamController.isClosed);

      streamController.add(1);

      // Should auto close on cancelling last subscription
      subscription.cancel();
      expect(true, streamController.isClosed);
    });

    test('Get InitialEvent on listen', () async {
      var streamController = BleShieldNativeStreamController<int>(
        initialEvent: () async => 1,
      );
      expect(true, streamController.isClosed);

      var firstValue = await streamController.stream.first;
      expect(true, streamController.isClosed);
      expect(1, firstValue);
    });
  });
}
