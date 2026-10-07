import 'dart:async';

final class CancellationToken {
  CancellationToken._(this._cancellation);

  final Completer<void> _cancellation;

  bool get isCancelled => _cancellation.isCompleted;

  Future<void> get whenCancelled => _cancellation.future;
}

final class CancellationController {
  final Completer<void> _cancellation = Completer<void>();

  late final CancellationToken token = CancellationToken._(_cancellation);

  void cancel() {
    if (!_cancellation.isCompleted) {
      _cancellation.complete();
    }
  }
}
