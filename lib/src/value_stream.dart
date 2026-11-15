import 'dart:async';

/// Holds a current value and exposes a stream that delivers it to every new
/// subscriber, then only changes.
class ValueStream<T> {
  ValueStream(this._value, {this.distinct = true});

  T _value;

  /// When true, [set] ignores values equal to the current one.
  final bool distinct;

  final StreamController<T> _changes = StreamController<T>.broadcast();

  T get value => _value;

  bool get isClosed => _changes.isClosed;

  void set(T value) {
    if (distinct && value == _value) return;
    _value = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  Stream<T> get stream => Stream<T>.multi((controller) {
        controller.add(_value);
        if (_changes.isClosed) {
          controller.close();
          return;
        }
        final sub = _changes.stream.listen(
          controller.add,
          onDone: controller.close,
        );
        controller.onCancel = sub.cancel;
      });

  Future<void> close() => _changes.close();
}
