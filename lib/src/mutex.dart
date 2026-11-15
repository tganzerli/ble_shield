import 'dart:async';

/// FIFO async lock. One instance per [BleShield] serializes every GATT
/// operation of every device, connect included.
class GattMutex {
  Future<void> _tail = Future<void>.value();
  int _waiting = 0;

  /// Operations holding or waiting for the lock.
  int get pending => _waiting;

  Future<T> protect<T>(Future<T> Function() body) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    _waiting++;
    return previous.then((_) => body()).whenComplete(() {
      _waiting--;
      released.complete();
    });
  }
}
