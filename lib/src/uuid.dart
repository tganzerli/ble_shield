import 'errors.dart';
import 'native/native.dart';

/// Canonical form used across the whole API: 128-bit, lower case, hyphenated.
///
/// Accepts 16-bit (`180d`, `0x180D`), 32-bit (`0000180d`) and 128-bit input,
/// with or without hyphens. Throws [ShieldError] with
/// [ShieldErrorCode.invalidArgument] for anything else.
String canonicalUuid(String input) {
  final parsed = BleUuidParser.stringOrNull(input);
  if (parsed == null) {
    throw ShieldError(
      ShieldErrorCode.invalidArgument,
      'invalid UUID "$input"',
    );
  }
  return parsed;
}
