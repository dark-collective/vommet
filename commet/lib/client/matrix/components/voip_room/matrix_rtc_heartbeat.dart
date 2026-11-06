import 'dart:async';
import 'dart:convert';

import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership_writer.dart';
import 'package:commet/debug/log.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite.dart';

/// Keeps the server's delayed leave alive independently of LiveKit media.
/// One-shot timers serialize work: a stalled isolate cannot queue up ticks.
class MatrixRtcHeartbeat {
  MatrixRtcHeartbeat({
    required this.client,
    required this.roomId,
    required this.stateKey,
    required this.eventType,
    required this.writer,
    required this.isActive,
    this.sync,
    this.now = DateTime.now,
  });

  /// Uses the account's HTTP transport and current credentials, while
  /// aborting timed-out management requests rather than leaving them running.
  static MatrixApi boundedClient(MatrixApi source) => _HeartbeatApi(source);

  // matrix-js-sdk MembershipManager uses 8 s / 5 s with a 2 s local timeout.
  // Keep our 30 s delay, but ping every 5 s for stalls and several retries.
  static const requestedDelay = Duration(seconds: 30);
  static const requestTimeout = Duration(seconds: 2);
  static const retryInterval = Duration(seconds: 1);
  final MatrixApi client;
  final String roomId, stateKey, eventType;
  final MatrixRtcMembershipWriter writer;
  final bool Function() isActive;
  final Stream<SyncUpdate>? sync;
  StreamSubscription<SyncUpdate>? _syncSubscription;
  final DateTime Function() now;
  DateTime? _lastRestart, _lastDebug;
  Completer<void>? _restartWait;
  Completer<GetVersionsResponse>? _versionsWait;
  bool _logNextRestart = true;
  Duration _delay = requestedDelay;
  Timer? _timer;
  String? _delayId;
  bool _stopped = false;
  bool _supported = false;
  bool _needsRejoin = false;
  Future<void>? _work;
  Future<void>? _recovery;

  bool get supportsDelayedEvents => _supported;

  bool get _active => !_stopped && isActive();
  Duration get _period =>
      Duration(milliseconds: (_delay.inMilliseconds ~/ 6).clamp(1, 5000));

  static bool _notFound(Object e) =>
      e is MatrixException &&
      (e.errcode == 'M_NOT_FOUND' || e.response?.statusCode == 404);

  Future<void> start() async {
    if (!_active) return;
    _syncSubscription ??= sync?.listen((update) {
      final room = update.rooms?.join?[roomId];
      MatrixEvent? latest;
      for (final event in [...?room?.state, ...?room?.timeline?.events]) {
        if (event.type == eventType && event.stateKey == stateKey) {
          latest = event;
        }
      }
      if (latest?.content.isEmpty == true && _active) {
        Log.w('Call heartbeat: sync removed our own membership; recovering');
        if (_supported) {
          unawaited(recover());
        } else {
          _needsRejoin = true;
        }
      }
    });
    try {
      final versions = await _versions();
      if (!_active) return;
      _supported = versions.unstableFeatures?['org.matrix.msc4140'] == true;
      if (!_supported) {
        writer.onMembershipLost = null;
        Log.w('Call heartbeat: homeserver does not support delayed events');
        return;
      }
      writer.onMembershipLost = () => unawaited(recover());
      await _run();
    } catch (e) {
      Log.w('Call heartbeat: startup failed, retrying: $e');
      if (_active) _timer = Timer(retryInterval, start);
    }
  }

  Future<GetVersionsResponse> _versions() async {
    final done = Completer<GetVersionsResponse>();
    _versionsWait = done;
    final timeout = Timer(requestTimeout, () {
      if (!done.isCompleted)
        done.completeError(TimeoutException('Call heartbeat capabilities'));
    });
    try {
      client.getVersions().then((versions) {
        if (!done.isCompleted) done.complete(versions);
      }, onError: (Object e, StackTrace s) {
        if (!done.isCompleted) done.completeError(e, s);
      });
      return await done.future;
    } finally {
      timeout.cancel();
      _versionsWait = null;
    }
  }

  void _schedule(Duration wait) {
    _timer?.cancel();
    if (_active) _timer = Timer(wait, _run);
  }

  Future<void> _run() {
    if (!_active || !_supported) return Future.value();
    return _work ??= _tick().whenComplete(() => _work = null);
  }

  Future<void> _tick() async {
    try {
      if (_delayId == null) await _create();
      if (!_active || _delayId == null) return;
      // Posting state can invalidate a delayed event on some servers. Always
      // check the new id immediately after recovery, before waiting a period.
      if (_needsRejoin) {
        Log.w('Call heartbeat: re-posting membership after delayed leave');
        final written = await writer.update((_) {}, recover: true);
        if (!_active) return;
        if (!written) {
          stop();
          return;
        }
        _needsRejoin = false;
      }
      final sentAt = now();
      final gap = _lastRestart == null
          ? null
          : sentAt.difference(_lastRestart!).inMilliseconds;
      await _action(_delayId!, 'restart');
      final receivedAt = now();
      if (_active) {
        if (_logNextRestart ||
            _lastDebug == null ||
            receivedAt.difference(_lastDebug!) >= const Duration(minutes: 1)) {
          // Log.d is compiled out of release builds. Keep debug entries in
          // the normal exportable log even on tester release builds.
          Log.add(LogEntry(
              LogType.debug,
              'Call heartbeat: restart succeeded, gap_ms=$gap, '
              'request_ms=${receivedAt.difference(sentAt).inMilliseconds}, '
              'delay_ms=${_delay.inMilliseconds}, period_ms=${_period.inMilliseconds}'));
          _lastDebug = receivedAt;
          _logNextRestart = false;
        }
        _lastRestart = sentAt;
        _schedule(_period);
      }
    } catch (e) {
      if (!_active) return;
      _logNextRestart = true;
      if (_notFound(e)) {
        Log.w('Call heartbeat: delayed leave already fired; rejoining');
        _delayId = null;
        _needsRejoin = true;
      } else {
        Log.w('Call heartbeat: request failed; retrying in 1 s: $e');
      }
      // Even several 2 s timeouts plus 1 s retry gaps fit in the 25 s slack.
      _schedule(retryInterval);
    }
  }

  Future<void> _create() async {
    while (_active) {
      try {
        final result = await client.request(RequestType.PUT,
            '/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/${Uri.encodeComponent(eventType)}/${Uri.encodeComponent(stateKey)}',
            data: '{}',
            query: {
              'org.matrix.msc4140.delay': _delay.inMilliseconds.toString(),
            });
        final id = result['delay_id'] as String;
        _delayId = id;
        if (!_active) await cancel();
        return;
      } on MatrixException catch (e) {
        final max = e.raw['org.matrix.msc4140.max_delay'];
        if (e.raw['org.matrix.msc4140.errcode'] == 'M_MAX_DELAY_EXCEEDED' &&
            max is int &&
            max > 0 &&
            max < _delay.inMilliseconds) {
          _delay = Duration(milliseconds: max);
          Log.w('Call heartbeat: using homeserver maximum delay of $max ms');
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _action(String id, String action) async {
    final done = Completer<void>();
    if (action == 'restart') _restartWait = done;
    final timeout = Timer(requestTimeout, () {
      if (!done.isCompleted) {
        done.completeError(
            TimeoutException('Call heartbeat $action', requestTimeout));
      }
    });
    try {
      client
          .request(RequestType.POST,
              '/client/unstable/org.matrix.msc4140/delayed_events/${Uri.encodeComponent(id)}',
              data: jsonEncode({'action': action}))
          .then((_) {
        if (!done.isCompleted) done.complete();
      }, onError: (Object e, StackTrace s) {
        if (!done.isCompleted) done.completeError(e, s);
      });
      await done.future;
    } finally {
      timeout.cancel();
      if (identical(_restartWait, done)) _restartWait = null;
    }
  }

  /// Coalesces membership-writer and restart failures into one recovery.
  Future<void> recover() =>
      _recovery ??= _recover().whenComplete(() => _recovery = null);

  Future<void> _recover() async {
    if (!_active || !_supported) return;
    _timer?.cancel();
    // An existing id may still be scheduled. Cancel it before replacing it,
    // so an abandoned leave cannot erase the recovered membership later.
    final running = _work;
    if (running != null) await running;
    if (!_active) return;
    _timer?.cancel();
    _needsRejoin = true;
    // Run cancellation inside the same serialized work as restart/create.
    _work = _replace().whenComplete(() => _work = null);
    await _work;
  }

  Future<void> _replace() async {
    try {
      final id = _delayId;
      if (id != null) {
        try {
          await _action(id, 'cancel');
        } catch (e) {
          if (!_notFound(e)) rethrow;
        }
        _delayId = null;
      }
      if (_active) await _tick();
    } catch (e) {
      Log.w('Call heartbeat: recovery failed, retrying: $e');
      if (_active) _timer = Timer(retryInterval, recover);
    }
  }

  /// Synchronous: no restart/recovery may start once hangup begins.
  void stop() {
    _stopped = true;
    writer.onMembershipLost = null;
    _timer?.cancel();
    _timer = null;
    final versions = _versionsWait;
    if (versions != null && !versions.isCompleted) {
      versions.complete(GetVersionsResponse(versions: []));
    }
    final restart = _restartWait;
    if (restart != null && !restart.isCompleted) restart.complete();
    final api = client;
    if (api is _HeartbeatApi) api.abort();
    unawaited(_syncSubscription?.cancel());
    _syncSubscription = null;
  }

  Future<void> cancel() async {
    stop();
    final id = _delayId;
    _delayId = null;
    if (id == null) return;
    try {
      await _action(id, 'cancel');
    } catch (e) {
      if (!_notFound(e)) rethrow;
      Log.i('Call heartbeat: leave already fired before hangup');
    }
  }
}

/// MatrixApi.request has no per-request timeout. Preserve the account's
/// transport (including any proxy) but abort individual POSTs at the deadline.
/// Creation is deliberately awaited: losing its response would orphan a
/// delayed leave that could later erase a recovered membership.
class _HeartbeatApi extends MatrixApi {
  _HeartbeatApi(this.source) : super(httpClient: source.httpClient);
  final MatrixApi source;
  final Map<Completer<void>, Timer> _pending = {};

  void abort() {
    for (final entry in _pending.entries) {
      entry.value.cancel();
      if (!entry.key.isCompleted) entry.key.complete();
    }
  }

  @override
  Future<GetVersionsResponse> getVersions() => source.getVersions();

  @override
  Future<Map<String, Object?>> request(RequestType type, String action,
      {dynamic data = '',
      String contentType = 'application/json',
      Map<String, Object?>? query}) async {
    if (type != RequestType.POST) {
      return source.request(type, action,
          data: data, contentType: contentType, query: query);
    }
    // IOClient cannot abort a DNS/connect operation until openUrl returns.
    // Bound those outstanding operations too, without waiting 30 s to retry.
    if (_pending.length >= 3) {
      throw StateError('Call heartbeat: three aborted requests still draining');
    }
    final abort = Completer<void>();
    final request = http.AbortableRequest(
        'POST',
        source.homeserver!
            .resolveUri(Uri(path: '_matrix$action', queryParameters: query)),
        abortTrigger: abort.future);
    request.headers['Content-Type'] = contentType;
    final token = source.accessToken;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.body = data is String ? data : jsonEncode(data);
    final timer = Timer(MatrixRtcHeartbeat.requestTimeout, abort.complete);
    _pending[abort] = timer;
    try {
      final response =
          await http.Response.fromStream(await source.httpClient.send(request));
      if (response.statusCode >= 400) throw MatrixException(response);
      return jsonDecode(response.body) as Map<String, Object?>;
    } finally {
      timer.cancel();
      _pending.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }
}
