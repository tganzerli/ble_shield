import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web registration hook, named by `flutter.plugin.platforms.web` in the
/// pubspec. The Web implementation is chosen by a conditional import in the
/// native layer, so there is nothing to register.
class BleShieldWeb {
  /// Called by the app's generated web plugin registrant.
  static void registerWith(Registrar registrar) {}
}
