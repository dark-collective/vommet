import 'package:matrix/matrix.dart';

/// Vommet issue 584: media that just failed with a definite answer from the
/// server, so it isn't requested again for a while.
///
/// A picture that can't be loaded (deleted, on a server that's gone or not
/// answering, a media repository error) was asked for again and again: each
/// failure is retried while the picture is shown, and every later
/// appearance (scrolling, reopening a room, the rail rebuilding) started
/// over, while successful loads are cached. Most thumbnail requests ended up
/// being repeats of the same few failures. Within [ttl] the failure is
/// thrown again without a request, so the existing retries cost nothing.
///
/// Only server answers that won't change in a moment are kept: not rate
/// limiting, sign-in errors or "not yet uploaded", and never network errors
/// or proxy error pages (those keep their retries, Vommet issue 337).
class MatrixMediaFailures {
  MatrixMediaFailures({
    this.ttl = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The app-wide record used by [MatrixMxcImage].
  static MatrixMediaFailures instance = MatrixMediaFailures();

  final Duration ttl;
  final DateTime Function() _now;

  final Map<String, (DateTime, MatrixException)> _failures = {};
  final Expando<bool> _replayed = Expando("replayed media failure");

  static const _transientErrcodes = {
    "M_LIMIT_EXCEEDED",
    "M_UNKNOWN_TOKEN",
    "M_MISSING_TOKEN",
    "M_NOT_YET_UPLOADED",
    "FI.MAU.MSC2246_NOT_YET_UPLOADED",
  };

  /// Whether [error] is a lasting answer worth remembering.
  static bool isLasting(Object error) =>
      error is MatrixException &&
      !_transientErrcodes.contains(error.errcode.toUpperCase());

  /// Runs [load] for the media [key] unless it failed lastingly within
  /// [ttl], in which case that failure is thrown again without a request.
  Future<T> guard<T>(String key, Future<T> Function() load) async {
    final known = _failures[key];
    if (known != null) {
      if (_now().difference(known.$1) < ttl) {
        _replayed[known.$2] = true;
        throw known.$2;
      }
      _failures.remove(key);
    }
    try {
      return await load();
    } catch (error) {
      if (isLasting(error)) {
        if (_failures.length >= 2000) _failures.clear();
        _failures[key] = (_now(), error as MatrixException);
      }
      rethrow;
    }
  }

  /// Whether [error] was thrown from the record rather than by the server
  /// (already logged when it first happened).
  bool isReplay(Object error) => _replayed[error] == true;

  void clear() => _failures.clear();
}
