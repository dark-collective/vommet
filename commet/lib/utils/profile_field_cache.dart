import 'dart:async';
import 'dart:collection';

typedef ProfileFieldFetcher = Future<Map<String, dynamic>> Function(
    String userId);

/// Vommet: in-memory cache for profile lookups (`GET /profile/{userId}`).
///
/// - A fresh entry is returned without touching the network.
/// - A stale entry is returned immediately and refreshed in the background.
/// - Concurrent lookups of the same user share one request.
/// - At most [maxConcurrent] requests run at once; the rest queue.
/// - A failed lookup is not retried for [failureBackoff], so an unreachable
///   server isn't asked again on every rebuild.
/// - At most [maxEntries] users are kept (least recently used is dropped).
class ProfileFieldCache {
  final ProfileFieldFetcher _fetch;
  final Duration freshFor;
  final Duration failureBackoff;
  final int maxConcurrent;
  final int maxEntries;
  final DateTime Function() _now;

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();
  final Map<String, Future<Map<String, dynamic>?>> _inFlight = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;

  final StreamController<String> _onUpdated = StreamController.broadcast();

  /// Emits a user id whenever a fetch changed that user's cached fields.
  Stream<String> get onUpdated => _onUpdated.stream;

  ProfileFieldCache(
    this._fetch, {
    this.freshFor = const Duration(minutes: 10),
    this.failureBackoff = const Duration(minutes: 2),
    this.maxConcurrent = 4,
    this.maxEntries = 2000,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Returns the user's profile fields, or null when they have never been
  /// fetched successfully. [forceRefresh] waits for a new request (still
  /// shared with one already running).
  Future<Map<String, dynamic>?> get(String userId,
      {bool forceRefresh = false}) {
    final entry = _touch(userId);
    final now = _now();

    if (!forceRefresh && entry != null) {
      final fresh = entry.fetchedAt != null &&
          now.difference(entry.fetchedAt!) < freshFor;
      final backingOff = entry.failedAt != null &&
          now.difference(entry.failedAt!) < failureBackoff;

      if (fresh || backingOff) return Future.value(entry.fields);

      if (entry.fields != null) {
        // Stale: answer now, refresh behind the caller's back.
        unawaited(_refresh(userId));
        return Future.value(entry.fields);
      }
    }

    return _refresh(userId);
  }

  /// The cached fields without any network access.
  Map<String, dynamic>? peek(String userId) => _entries[userId]?.fields;

  /// Forget a user, e.g. after they changed their profile.
  void invalidate(String userId) {
    _entries.remove(userId);
  }

  void clear() => _entries.clear();

  Future<Map<String, dynamic>?> _refresh(String userId) {
    final running = _inFlight[userId];
    if (running != null) return running;

    final future = _run(userId);
    _inFlight[userId] = future;
    // The caller handles any error. This branch only clears the entry, and
    // must not leave an unhandled copy of the error behind (a block body, so
    // whenComplete doesn't wait on the future that remove() hands back).
    future.then((_) {}, onError: (_) {}).whenComplete(() {
      _inFlight.remove(userId);
    });
    return future;
  }

  Future<Map<String, dynamic>?> _run(String userId) async {
    await _acquire();
    try {
      final fields = await _fetch(userId);
      final old = _entries[userId]?.fields;
      _store(userId, _Entry(fields: fields, fetchedAt: _now()));
      if (old != null && !_sameFields(old, fields)) {
        _onUpdated.add(userId);
      }
      return fields;
    } catch (_) {
      final old = _entries[userId];
      _store(
          userId,
          _Entry(
              fields: old?.fields,
              fetchedAt: old?.fetchedAt,
              failedAt: _now()));
      if (old?.fields == null) rethrow;
      return old!.fields;
    } finally {
      _release();
    }
  }

  _Entry? _touch(String userId) {
    final entry = _entries.remove(userId);
    if (entry != null) _entries[userId] = entry;
    return entry;
  }

  void _store(String userId, _Entry entry) {
    _entries.remove(userId);
    _entries[userId] = entry;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  Future<void> _acquire() {
    if (_running < maxConcurrent) {
      _running++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // Hand the slot straight to the next waiter.
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  static bool _sameFields(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key].toString() != b[key].toString()) {
        return false;
      }
    }
    return true;
  }
}

class _Entry {
  final Map<String, dynamic>? fields;
  final DateTime? fetchedAt;
  final DateTime? failedAt;

  _Entry({this.fields, this.fetchedAt, this.failedAt});
}
