import 'dart:async';

import 'package:ble_shield/ble_shield.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

/// Lets queued microtasks and zero-delay timers run.
Future<void> settle([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Runs [body] under fake time: timers fire in deadline order, whatever the
/// wall clock does, so a stalled test process cannot reorder them. Use it when
/// an assertion depends on the order between a timer's effect and a short
/// `wait`/`settle` (reconnect delays, scan windows, short timeouts with more
/// than one timer in play).
///
/// Build the [BleShield] inside [body]: its GATT lock holds a completed future
/// whose callbacks run in the zone that created it, and fake time never drains
/// a zone outside its own. Code that reads `DateTime.now()` (the scan's
/// `removeIfGone`) does not follow fake time: keep those tests on `test`.
@isTest
void fakeTest(String description, Future<void> Function() body,
    {Timeout? timeout}) {
  test(description, () {
    fakeAsync((async) {
      Object? error;
      StackTrace? trace;
      var done = false;
      body().then<void>((_) {
        done = true;
      }, onError: (Object e, StackTrace s) {
        error = e;
        trace = s;
      });
      const step = Duration(milliseconds: 10);
      var elapsed = Duration.zero;
      while (!done && error == null) {
        if (elapsed > const Duration(minutes: 5)) {
          fail('fake time ran 5 min without the test finishing');
        }
        async.elapse(step);
        elapsed += step;
      }
      if (error != null) Error.throwWithStackTrace(error!, trace!);
    });
  }, timeout: timeout);
}

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
const macOS = TargetPlatform.macOS;
