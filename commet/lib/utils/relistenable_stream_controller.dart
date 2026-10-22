import 'dart:async';

/// Vommet issue 485: a stream for the message box that a new message box can
/// listen to again. A banned or blocked-DM footer replaces the composer, and
/// when the composer comes back its fresh state listens once more; a plain
/// single-subscription [StreamController] throws "Stream has already been
/// listened to" there, which greyed out the whole chat.
///
/// Like a single-subscription stream, events added while nobody listens are
/// held and delivered to the next listener.
class RelistenableStreamController<T> {
  RelistenableStreamController({void Function()? onListen, this.onCancel})
      : _onListen = onListen;

  final void Function()? _onListen;
  final void Function()? onCancel;
  final List<T> _pending = [];

  late final StreamController<T> _controller = StreamController<T>.broadcast(
      onListen: () {
        _onListen?.call();
        final pending = List<T>.of(_pending);
        _pending.clear();
        pending.forEach(_controller.add);
      },
      onCancel: onCancel);

  Stream<T> get stream => _controller.stream;

  bool get hasListener => _controller.hasListener;

  void add(T event) {
    if (_controller.hasListener) {
      _controller.add(event);
    } else {
      _pending.add(event);
    }
  }

  Future<void> close() => _controller.close();
}
