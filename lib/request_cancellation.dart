import 'dart:async';

/// Cooperative cancellation handle for an in-flight SDK request.
///
/// Web adapters translate this handle to an `AbortSignal`. Other backends may
/// ignore it when their transport cannot cancel safely. Calling [cancel] more
/// than once is idempotent and never throws.
class InappifyRequestCancellation {
  final StreamController<void> _controller = StreamController<void>.broadcast(
    sync: true,
  );
  bool _isCancelled = false;

  /// Whether cancellation has already been requested.
  bool get isCancelled => _isCancelled;

  /// Notification consumed by platform adapters that support cancellation.
  Stream<void> get whenCancelled => _controller.stream;

  /// Requests cancellation of the associated operation.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _controller.add(null);
  }
}
