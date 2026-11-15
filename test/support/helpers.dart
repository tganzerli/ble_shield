import 'dart:async';

import 'package:ble_shield/ble_shield.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets queued microtasks and zero-delay timers run.
Future<void> settle([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

Matcher shieldError(ShieldErrorCode code) =>
    isA<ShieldError>().having((e) => e.code, 'code', code);

/// Runs [body] in a guarded zone and returns every error that reached it.
Future<List<Object>> zoneErrors(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  final guarded = runZonedGuarded(() async {
    try {
      await body();
    } finally {
      done.complete();
    }
  }, (e, _) => errors.add(e));
  unawaited(guarded);
  await done.future;
  await settle();
  return errors;
}

const android = TargetPlatform.android;
const iOS = TargetPlatform.iOS;
