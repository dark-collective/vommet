// Vommet issue 1176: one bounded, session-local self-profile status cache.
// The SDK's persistent presence cache has no freshness information. Never use
// its old text as a fallback after a clear, failed lookup or app restart.
import 'dart:async';
import 'dart:math';

import 'package:matrix/matrix.dart';

class MatrixSelfStatus {
  final Client sdk;
  final DateTime Function() now;
  final double Function() _random;
  final _changes = StreamController<CachedPresence>.broadcast();
  late final StreamSubscription<CachedPresence> _subscription;
  CachedPresence? _value;
  Future<CachedPresence?>? _pending;
  DateTime? _nextRead, _retryAt;
  Future<GetPresenceResponse>? _transport;
  Object? _permanentError, _rateLimitError;
  int _failures = 0;
  bool _probeFailureSeen = false;
  late (String?, String?) _session;
  int _revision = 0;
  int _writes = 0;
  Future<void> _writeTail = Future.value();
  bool _closed = false;

  MatrixSelfStatus(this.sdk,
      {DateTime Function()? now, double Function()? random})
      : now = now ?? DateTime.now,
        _random = random ?? Random().nextDouble {
    _session = (sdk.userID, sdk.bearerToken);
    _subscription = sdk.onPresenceChanged.stream.listen((value) {
      _checkSession();
      if (_closed || _writes > 0 || value.userid != sdk.userID) return;
      _revision++;
      _accept(value);
    });
  }

  CachedPresence? get cached {
    _checkSession();
    return _value;
  }

  void _checkSession() {
    final next = (sdk.userID, sdk.bearerToken);
    if (_closed ||
        next == _session ||
        next.$1 == null ||
        (next.$2 == null || next.$2!.isEmpty)) return;
    _session = next;
    _revision++;
    _value = null;
    _pending = null;
    _transport = null;
    _nextRead = _retryAt = null;
    _permanentError = _rateLimitError = null;
    _failures = 0;
    _probeFailureSeen = false;
  }

  void _failed(Object error) {
    if (_closed) return;
    final matrix = error is MatrixException ? error : null;
    final status = matrix?.response?.statusCode;
    final limited =
        status == 429 || matrix?.error == MatrixError.M_LIMIT_EXCEEDED;
    final denied = [
      MatrixError.M_FORBIDDEN,
      MatrixError.M_UNKNOWN_TOKEN,
      MatrixError.M_UNAUTHORIZED,
      MatrixError.M_NOT_FOUND,
      MatrixError.M_UNRECOGNIZED
    ].contains(matrix?.error);
    if (!limited &&
        (denied || (status != null && status >= 400 && status < 500))) {
      _permanentError = error;
      return;
    }
    final seconds = min(900, 60 * (1 << _failures));
    _failures = min(_failures + 1, 4);
    final jittered =
        min(900000, (seconds * 1000 * (1 + _random() / 4)).round());
    final wait = max(jittered, limited ? matrix?.retryAfterMs ?? 0 : 0);
    final retry = now().add(Duration(milliseconds: wait));
    if (_retryAt == null || retry.isAfter(_retryAt!)) _retryAt = retry;
    if (limited) _rateLimitError = error;
  }

  void _succeeded() {
    _failures = 0;
    if (_rateLimitError != null &&
        _retryAt != null &&
        now().isBefore(_retryAt!)) return;
    _retryAt = null;
    _rateLimitError = null;
  }

  Stream<CachedPresence> get changes => _changes.stream;

  void _accept(CachedPresence value) {
    final old = _value;
    _value = value;
    _nextRead = now().add(const Duration(seconds: 30));
    if (old?.presence != value.presence ||
        old?.statusMsg != value.statusMsg ||
        old?.lastActiveTimestamp != value.lastActiveTimestamp) {
      _changes.add(value);
    }
  }

  void _seedProbeFailure(Object? error) {
    if (_probeFailureSeen || error == null) return;
    _probeFailureSeen = true;
    _failed(error);
  }

  /// Only called when this account's own profile is deliberately opened.
  /// Coalesced, 30 s freshness; recovery is user-driven, never a retry timer.
  Future<CachedPresence?> read({Object? probeFailure}) {
    _checkSession();
    _seedProbeFailure(probeFailure);
    if (_closed || _writes > 0 || _permanentError != null)
      return Future.value(_value);
    if (_pending case final pending?) return pending;
    if (_transport != null || (_retryAt != null && now().isBefore(_retryAt!))) {
      return Future.value(_value);
    }
    if (_nextRead != null && now().isBefore(_nextRead!)) {
      return Future.value(_value);
    }
    final future = _read(_revision);
    _pending = future;
    future.whenComplete(() {
      if (identical(_pending, future)) _pending = null;
    });
    return future;
  }

  Future<CachedPresence?> _read(int revision) async {
    final session = _session;
    var expired = false;
    try {
      final self = sdk.userID;
      if (self == null) return null;
      final request = sdk
          .request(RequestType.GET,
              '/client/v3/presence/${Uri.encodeComponent(self)}/status')
          .then(GetPresenceResponse.fromJson);
      _transport = request;
      // The SDK times the response body, not waiting for headers. Keep the
      // underlying request single-flight even after the UI deadline expires.
      request.then<void>((_) {
        _checkSession();
        if (identical(_transport, request)) _transport = null;
      }, onError: (Object error) {
        _checkSession();
        if (identical(_transport, request)) _transport = null;
        if (expired && session == _session) _failed(error);
      });
      final response = await request.timeout(const Duration(seconds: 5));
      _checkSession();
      if (!_closed && session == _session) {
        _succeeded();
        if (revision == _revision)
          _accept(CachedPresence.fromPresenceResponse(response, self));
      }
    } catch (error) {
      _checkSession();
      expired = error is TimeoutException;
      if (session == _session) _failed(error);
    }
    return _value;
  }

  Future<void> write(String? message, Future<void> Function() send,
      {Object? probeFailure}) {
    _checkSession();
    if (_closed) return Future.value();
    _seedProbeFailure(probeFailure);
    final session = _session;
    final revision = ++_revision;
    _writes++;
    // A clear is an immediate barrier, including while an older save is pending.
    if (message == null || message.isEmpty) _setMessage(null);
    final operation = _writeTail.then((_) async {
      try {
        _checkSession();
        if (_closed || session != _session) return;
        if (_permanentError case final error?) throw error;
        if (_rateLimitError != null &&
            _retryAt != null &&
            now().isBefore(_retryAt!)) throw _rateLimitError!;
        await send();
        _checkSession();
        if (!_closed && session == _session) {
          _succeeded();
          if (revision == _revision) _setMessage(message);
        }
      } catch (error) {
        if (session == _session &&
            !identical(error, _permanentError) &&
            !identical(error, _rateLimitError)) _failed(error);
        rethrow;
      } finally {
        _writes--;
        if (!_closed && session == _session) {
          _nextRead = now().add(const Duration(minutes: 1));
        }
      }
    });
    // Preserve local intent order on the wire; a failed save must not block clear.
    _writeTail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  void _setMessage(String? message) {
    final self = sdk.userID;
    if (self == null) return;
    _accept(CachedPresence.fromJson({
      ...?(_value?.toJson()),
      'user_id': self,
      'presence': _value?.presence.name ?? 'offline',
      'status_msg': message,
    }));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _revision++;
    _value = null;
    await _subscription.cancel();
    await _changes.close();
  }
}
