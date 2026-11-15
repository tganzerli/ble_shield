import 'dart:async';

/// Auto disposable StreamController
class BleShieldNativeStreamController<T> {
  Future<T> Function()? initialEvent;
  BleShieldNativeStreamController({this.initialEvent});

  StreamController<T>? _streamController;

  Stream<T> get stream {
    _setupStreamIfRequired();
    return _streamController!.stream;
  }

  bool get isClosed => _streamController?.isClosed ?? true;

  void add(T data) => _streamController?.add(data);

  void addError(Object error) => _streamController?.addError(error);

  void close() {
    _streamController?.close();
    _streamController = null;
  }

  void _setupStreamIfRequired() {
    if (_streamController != null) return;

    _streamController = StreamController.broadcast(
      onListen: () async {
        try {
          T? event = await initialEvent?.call();
          if (event != null) add(event);
        } catch (_) {}
      },
      onCancel: close,
    );
  }
}
