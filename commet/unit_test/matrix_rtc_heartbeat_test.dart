import 'dart:async';
import 'dart:convert';

import 'package:commet/client/matrix/components/voip_room/matrix_rtc_heartbeat.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership_writer.dart';
import 'package:commet/debug/log.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite.dart';

MatrixException missing() =>
    MatrixException.fromJson({'errcode': 'M_NOT_FOUND'});

/// Server time advances even when the client's main isolate is blocked.
class _Client extends Fake implements MatrixApi {
  _Client(this.clock);
  final FakeAsync clock;
  final Map<String, Duration> deadlines = {};
  int creates = 0, restarts = 0, expiries = 0, posts = 0;
  int throwRestarts = 0, timeoutRestarts = 0;
  int versionsAttempts = 0, createAttempts = 0, cancelAttempts = 0;
  Object? versionsError, createError, restartError, cancelError;
  final versionTimes = <Duration>[],
      createTimes = <Duration>[],
      cancelTimes = <Duration>[];
  Duration delivery = Duration.zero;
  int? maxDelay;
  Completer<void>? blockedCreate;
  Completer<GetVersionsResponse>? blockedVersions;
  Map<String, dynamic> membership = {'present': true};
  Duration delay = const Duration(seconds: 30);

  void expire() {
    for (final id in deadlines.keys.toList()) {
      if (clock.elapsed >= deadlines[id]!) {
        deadlines.remove(id);
        membership = {};
        expiries++;
      }
    }
  }

  @override
  Future<GetVersionsResponse> getVersions() async {
    versionsAttempts++;
    versionTimes.add(clock.elapsed);
    if (versionsError != null) throw versionsError!;
    if (blockedVersions != null) return await blockedVersions!.future;
    return GetVersionsResponse(
        versions: ['v1.1'], unstableFeatures: {'org.matrix.msc4140': true});
  }

  @override
  Future<Map<String, Object?>> request(RequestType type, String action,
      {dynamic data = '',
      String contentType = 'application/json',
      Map<String, Object?>? query}) async {
    if (type == RequestType.PUT) {
      createAttempts++;
      createTimes.add(clock.elapsed);
      if (createError != null) throw createError!;
      final requested = int.parse(query!['org.matrix.msc4140.delay'] as String);
      if (maxDelay != null && requested > maxDelay!) {
        throw MatrixException.fromJson({
          'errcode': 'M_UNKNOWN',
          'org.matrix.msc4140.errcode': 'M_MAX_DELAY_EXCEEDED',
          'org.matrix.msc4140.max_delay': maxDelay,
        });
      }
      final blocker = blockedCreate;
      if (blocker != null) await blocker.future;
      delay = Duration(milliseconds: requested);
      final id = '${++creates}';
      deadlines[id] = clock.elapsed + delay;
      return {'delay_id': id};
    }
    final id = Uri.decodeComponent(action.split('/').last);
    final verb = (jsonDecode(data as String) as Map)['action'];
    if (verb == 'restart') {
      restarts++;
      if (restartError != null) throw restartError!;
      if (throwRestarts > 0) {
        throwRestarts--;
        throw StateError('transient network failure');
      }
      if (timeoutRestarts > 0) {
        timeoutRestarts--;
        return Completer<Map<String, Object?>>().future;
      }
      if (delivery > Duration.zero) await Future<void>.delayed(delivery);
      expire();
      if (!deadlines.containsKey(id)) throw missing();
      deadlines[id] = clock.elapsed + delay;
    } else {
      cancelAttempts++;
      cancelTimes.add(clock.elapsed);
      if (cancelError != null) throw cancelError!;
      expire();
      if (deadlines.remove(id) == null) throw missing();
    }
    return {};
  }
}

class _Call {
  _Call(FakeAsync clock) : client = _Client(clock) {
    writer = MatrixRtcMembershipWriter(
      readInitial: () async => (
        content: {
          'application': 'm.call',
          'scope': 'm.room',
          'device_id': 'DEVICE',
          'expires': 14400000,
          'focus_active': {
            'type': 'livekit',
            'focus_selection': 'oldest_membership'
          },
          'foci_preferred': [
            {
              'type': 'livekit',
              'livekit_service_url': 'https://sfu.example.org'
            }
          ],
        },
        originServerTs: 1000,
      ),
      isCurrent: (_) => client.membership.isNotEmpty,
      send: (content) async {
        if (content.isNotEmpty) expect(client.deadlines, isNotEmpty);
        client.posts++;
        client.membership = Map.from(content);
      },
    );
    heartbeat = MatrixRtcHeartbeat(
        client: client,
        sync: sync.stream,
        now: clock.getClock(DateTime.utc(2026)).now,
        roomId: '!room:example.org',
        stateKey: '_@me:example.org_DEVICE_m.call',
        eventType: 'org.matrix.msc3401.call.member',
        writer: writer,
        isActive: () => active);
    writer.onMembershipLost = () => unawaited(heartbeat.recover());
  }
  final _Client client;
  final sync = StreamController<SyncUpdate>.broadcast();
  late final MatrixRtcMembershipWriter writer;
  late final MatrixRtcHeartbeat heartbeat;
  bool active = true;

  void hangup() {
    active = false;
    heartbeat.stop();
    unawaited(writer.clear());
    unawaited(heartbeat.cancel());
  }
}

class _StalledTransport extends http.BaseClient {
  int outstanding = 0, peak = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    outstanding++;
    if (outstanding > peak) peak = outstanding;
    try {
      await (request as http.AbortableRequest).abortTrigger;
      throw http.RequestAbortedException(request.url);
    } finally {
      outstanding--;
    }
  }
}

class _ConnectingTransport extends http.BaseClient {
  int sends = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sends++;
    return Completer<http.StreamedResponse>().future;
  }
}

void main() {
  group('round 2 retry policy', () {
    MatrixException limited({bool statusOnly = false}) => statusOnly
        ? MatrixException(http.Response(
            jsonEncode({'errcode': 'M_UNKNOWN', 'retry_after_ms': 12000}), 429))
        : MatrixException.fromJson(
            {'errcode': 'M_LIMIT_EXCEEDED', 'retry_after_ms': 12000});
    MatrixException forbidden({bool statusOnly = false}) => statusOnly
        ? MatrixException(http.Response('{"errcode":"M_UNKNOWN"}', 403))
        : MatrixException.fromJson({'errcode': 'M_FORBIDDEN'});

    for (final operation in ['create', 'restart', 'startup', 'recovery']) {
      test('$operation rate limit honors retry_after_ms and cannot be bypassed',
          () {
        fakeAsync((clock) {
          final call = _Call(clock);
          final error = limited(statusOnly: operation == 'restart');
          int attempts() => switch (operation) {
                'create' => call.client.createAttempts,
                'restart' => call.client.restarts,
                'startup' => call.client.versionsAttempts,
                _ => call.client.cancelAttempts,
              };
          if (operation == 'create') call.client.createError = error;
          if (operation == 'startup') call.client.versionsError = error;
          unawaited(call.heartbeat.start());
          clock.flushMicrotasks();
          if (operation == 'restart') {
            call.client.restartError = error;
            clock.elapse(const Duration(seconds: 5));
          }
          if (operation == 'recovery') {
            call.client.cancelError = error;
            unawaited(call.heartbeat.recover());
            clock.flushMicrotasks();
          }
          final failedAt = clock.elapsed;
          final before = attempts();
          clock.elapse(const Duration(milliseconds: 11999));
          expect(attempts(), before);
          // Model an own-membership sync/writer callback during the limit.
          if (operation != 'startup') {
            unawaited(call.heartbeat.recover());
            clock.flushMicrotasks();
            expect(attempts(), before);
          }
          call.client.versionsError = call.client.createError =
              call.client.restartError = call.client.cancelError = null;
          clock.elapse(const Duration(milliseconds: 1));
          expect(clock.elapsed - failedAt, const Duration(seconds: 12));
          expect(attempts(), before + 1);
          call.hangup();
          clock.flushMicrotasks();
          expect(clock.pendingTimers, isEmpty);
        });
      });

      test('$operation forbidden stops requests without a 1 s loop', () {
        fakeAsync((clock) {
          final call = _Call(clock);
          if (operation == 'create') call.client.createError = forbidden();
          if (operation == 'startup') call.client.versionsError = forbidden();
          unawaited(call.heartbeat.start());
          clock.flushMicrotasks();
          if (operation == 'restart') {
            call.client.restartError = forbidden(statusOnly: true);
            clock.elapse(const Duration(seconds: 5));
          }
          if (operation == 'recovery') {
            call.client.cancelError = forbidden();
            unawaited(call.heartbeat.recover());
            clock.flushMicrotasks();
          }
          final counts = (
            call.client.versionsAttempts,
            call.client.createAttempts,
            call.client.restarts,
            call.client.cancelAttempts,
            call.client.posts
          );
          clock.elapse(const Duration(minutes: 2));
          unawaited(call.heartbeat.recover());
          clock.flushMicrotasks();
          expect((
            call.client.versionsAttempts,
            call.client.createAttempts,
            call.client.restarts,
            call.client.cancelAttempts,
            call.client.posts
          ), counts);
          expect(clock.pendingTimers, isEmpty);
          expect(call.sync.hasListener, isFalse);
          call.client.cancelError = null;
          call.hangup();
          clock.flushMicrotasks();
        });
      });
    }

    test('zero retry_after_ms still backs off recurring rate limits', () {
      fakeAsync((clock) {
        final call = _Call(clock);
        call.client.createError = MatrixException.fromJson({
          'errcode': 'M_LIMIT_EXCEEDED',
          'retry_after_ms': 0,
        });
        unawaited(call.heartbeat.start());
        clock.elapse(const Duration(seconds: 200));
        expect(call.client.createAttempts, lessThan(15));
        final times = call.client.createTimes;
        expect([for (var i = 1; i < times.length; i++) times[i] - times[i - 1]],
            contains(const Duration(seconds: 60)));
        call.hangup();
        clock.flushMicrotasks();
        expect(clock.pendingTimers, isEmpty);
      });
    });

    for (final operation in ['startup', 'recovery', 'create']) {
      test('$operation repeated transient errors use capped backoff', () {
        fakeAsync((clock) {
          final call = _Call(clock);
          if (operation == 'startup')
            call.client.versionsError = StateError('offline');
          if (operation == 'create')
            call.client.createError = StateError('offline');
          unawaited(call.heartbeat.start());
          clock.flushMicrotasks();
          if (operation == 'recovery') {
            call.client.cancelError = StateError('offline');
            unawaited(call.heartbeat.recover());
            clock.flushMicrotasks();
          }
          clock.elapse(const Duration(seconds: 200));
          final times = switch (operation) {
            'startup' => call.client.versionTimes,
            'create' => call.client.createTimes,
            _ => call.client.cancelTimes,
          };
          expect(times.length, lessThan(15));
          final gaps = [
            for (var i = 1; i < times.length; i++) times[i] - times[i - 1]
          ];
          expect(gaps, contains(const Duration(seconds: 60)));
          expect(
              gaps.every((gap) => gap <= const Duration(seconds: 60)), isTrue);
          call.client.cancelError = null;
          call.hangup();
          clock.flushMicrotasks();
          final count = times.length;
          clock.elapse(const Duration(minutes: 2));
          expect(times.length, count);
          expect(clock.pendingTimers, isEmpty);
        });
      });
    }
  });

  test('platform connects that ignore abort cannot pile up without a bound',
      () {
    fakeAsync((clock) {
      final transport = _ConnectingTransport();
      final api = MatrixRtcHeartbeat.boundedClient(MatrixApi(
          homeserver: Uri.parse('https://matrix.example.org'),
          httpClient: transport));
      var rejected = 0;
      for (var attempt = 0; attempt < 4; attempt++) {
        unawaited(api
            .request(RequestType.POST,
                '/client/unstable/org.matrix.msc4140/delayed_events/id',
                data: '{"action":"restart"}')
            .then<void>((_) {}, onError: (Object _) {
          rejected++;
        }));
        clock.elapse(const Duration(seconds: 3));
      }
      expect(transport.sends, 3);
      expect(rejected, 1);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('hangup during capability lookup cancels startup work', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      final blocked = Completer<GetVersionsResponse>();
      call.client.blockedVersions = blocked;
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      call.hangup();
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
      blocked.complete(GetVersionsResponse(
          versions: ['v1.1'], unstableFeatures: {'org.matrix.msc4140': true}));
      clock.elapse(const Duration(minutes: 1));
      expect(call.client.creates, 0);
      expect(call.client.restarts, 0);
      expect(call.client.posts, 1);
    });
  });

  test('a focus migration discovering loss is included in the recovery write',
      () {
    fakeAsync((clock) {
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      call.client.membership = {};
      unawaited(call.writer.update((content) {
        content['foci_preferred'] = [
          {
            'type': 'livekit',
            'livekit_service_url': 'https://bridge.example.org'
          }
        ];
      }));
      clock.flushMicrotasks();
      expect(call.client.creates, 2);
      expect((call.client.membership['foci_preferred'] as List).single, {
        'type': 'livekit',
        'livekit_service_url': 'https://bridge.example.org'
      });
      expect(call.client.membership['created_ts'], 1000);
      call.hangup();
      clock.flushMicrotasks();
    });
  });

  test('debug restart timings are exported once a minute and after failures',
      () {
    fakeAsync((clock) {
      Log.log.clear();
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.elapse(const Duration(seconds: 61));
      List<String> entries() => Log.log
          .where((e) => e.type == LogType.debug)
          .map((e) => e.rawContent)
          .where((s) => s.contains('Call heartbeat: restart succeeded'))
          .toList();
      expect(entries().length, 2);
      expect(entries().last, contains('gap_ms=5000'));
      expect(entries().last, contains('request_ms=0'));
      call.client.throwRestarts = 1;
      clock.elapse(const Duration(seconds: 5));
      expect(entries().length, 3);
      call.hangup();
      clock.flushMicrotasks();
    });
  });

  test('hangup stops a restart still waiting on its short timeout', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      call.client.timeoutRestarts = 1;
      clock.elapse(const Duration(seconds: 5));
      call.hangup();
      clock.flushMicrotasks();
      final count = call.client.restarts;
      expect(clock.pendingTimers, isEmpty);
      clock.elapse(const Duration(minutes: 1));
      expect(call.client.restarts, count);
      expect(call.client.membership, isEmpty);
    });
  });

  test('a stall beyond the delay recovers the expired membership', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      clock.elapseBlocking(const Duration(seconds: 40));
      clock.elapse(const Duration(seconds: 2));
      expect(call.client.expiries, 1);
      expect(call.client.creates, 2);
      expect(call.client.membership['created_ts'], 1000);
      call.hangup();
      clock.flushMicrotasks();
    });
  });

  test('HTTP restart requests abort at 2 s instead of piling up', () {
    fakeAsync((clock) {
      final transport = _StalledTransport();
      final api = MatrixRtcHeartbeat.boundedClient(MatrixApi(
          homeserver: Uri.parse('https://matrix.example.org'),
          httpClient: transport));
      var failures = 0;
      Future<void> restart() async {
        try {
          await api.request(RequestType.POST,
              '/client/unstable/org.matrix.msc4140/delayed_events/id',
              data: '{"action":"restart"}');
        } on http.RequestAbortedException {
          failures++;
        }
      }

      unawaited(restart());
      clock.elapse(const Duration(seconds: 2));
      expect(failures, 1);
      expect(transport.outstanding, 0);
      unawaited(restart());
      clock.elapse(const Duration(seconds: 2));
      expect(failures, 2);
      expect(transport.peak, 1);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('sync of our empty membership re-joins before the next heartbeat', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      call.client.membership = {};
      call.sync.add(SyncUpdate.fromJson({
        'next_batch': 'next',
        'rooms': {
          'join': {
            '!room:example.org': {
              'timeline': {
                'events': [
                  {
                    'type': 'org.matrix.msc3401.call.member',
                    'state_key': '_@me:example.org_DEVICE_m.call',
                    'sender': '@me:example.org',
                    'content': <String, Object?>{},
                    'event_id': 'leave',
                    'origin_server_ts': 2000,
                  }
                ]
              }
            }
          }
        }
      }));
      clock.flushMicrotasks();
      expect(clock.elapsed, Duration.zero);
      expect(call.client.creates, 2);
      expect(call.client.membership['created_ts'], 1000);
      expect(call.client.deadlines.length, 1);
      call.hangup();
      clock.flushMicrotasks();
      expect(call.sync.hasListener, isFalse);
    });
  });

  for (final timeout in [false, true]) {
    test('a restart ${timeout ? 'timeout' : 'exception'} retries before expiry',
        () {
      fakeAsync((clock) {
        final call = _Call(clock);
        unawaited(call.heartbeat.start());
        clock.flushMicrotasks();
        if (timeout) {
          call.client.timeoutRestarts = 1;
        } else {
          call.client.throwRestarts = 1;
        }
        clock.elapse(const Duration(seconds: 9));
        expect(call.client.restarts, 3); // initial, failed, successful retry
        expect(call.client.deadlines.values.single,
            greaterThan(const Duration(seconds: 30)));
        call.client.expire();
        expect(call.client.expiries, 0);
        expect(call.client.creates, 1);
        call.hangup();
        clock.flushMicrotasks();
        expect(clock.pendingTimers, isEmpty);
      });
    });
  }

  test('404 schedules a new delayed leave and re-posts the full membership',
      () {
    fakeAsync((clock) {
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      // A multi-SFU migration already changed the writer's retained content.
      unawaited(call.writer.update((c) {
        c['foci_preferred'] = [
          {
            'type': 'livekit',
            'livekit_service_url': 'https://bridge.example.org'
          }
        ];
      }));
      clock.flushMicrotasks();
      call.client.deadlines.clear();
      call.client.membership = {};
      clock.elapse(const Duration(seconds: 26));
      expect(call.client.creates, 2);
      expect(call.client.membership['created_ts'], 1000);
      expect(call.client.membership['device_id'], 'DEVICE');
      expect(call.client.membership['focus_active'],
          {'type': 'livekit', 'focus_selection': 'oldest_membership'});
      expect((call.client.membership['foci_preferred'] as List).single, {
        'type': 'livekit',
        'livekit_service_url': 'https://bridge.example.org'
      });
      expect(call.client.posts, 2);
      call.hangup();
      clock.flushMicrotasks();
    });
  });

  test('4 s main-isolate stall and 1.5 s delivery do not expire membership',
      () {
    fakeAsync((clock) {
      final call = _Call(clock);
      call.client.delivery = const Duration(milliseconds: 1500);
      unawaited(call.heartbeat.start());
      clock.elapse(const Duration(milliseconds: 24500));
      clock.elapseBlocking(const Duration(seconds: 4));
      clock.elapse(const Duration(seconds: 5));
      call.client.expire();
      expect(call.client.restarts, greaterThan(2));
      expect(call.client.expiries, 0);
      expect(call.client.creates, 1);
      call.hangup();
      clock.flushMicrotasks();
    });
  });

  test('writer-detected loss recovers without closing future updates', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      call.client.membership = {};
      unawaited(call.writer.update((c) => c['expires'] = 28800000));
      clock.flushMicrotasks();
      expect(call.client.creates, 2);
      expect(call.client.deadlines.length, 1); // old id cancelled
      expect(call.client.membership['created_ts'], 1000);
      unawaited(call.writer.update((c) => c['expires'] = 28800000));
      clock.flushMicrotasks();
      expect(call.client.membership['expires'], 28800000);
      call.hangup();
      clock.flushMicrotasks();
    });
  });

  test('hangup after a failed restart cancels retries and recovery', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      call.client.throwRestarts = 1;
      clock.elapse(const Duration(seconds: 5));
      call.hangup();
      clock.flushMicrotasks();
      final restarts = call.client.restarts;
      final posts = call.client.posts;
      unawaited(call.heartbeat.recover());
      unawaited(call.writer.update((_) {}, recover: true));
      clock.elapse(const Duration(minutes: 10));
      expect(call.client.restarts, restarts);
      expect(call.client.posts, posts);
      expect(call.client.membership, isEmpty);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('hangup cancels a delayed event whose creation finishes late', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      final blocked = Completer<void>();
      call.client.blockedCreate = blocked;
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      call.hangup();
      clock.flushMicrotasks();
      blocked.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 1));
      expect(call.client.deadlines, isEmpty);
      expect(call.client.restarts, 0);
      expect(call.client.posts, 1); // only the empty leave
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('hangup succeeds when delayed leave has already fired', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      unawaited(call.heartbeat.start());
      clock.flushMicrotasks();
      call.client.deadlines.clear();
      call.hangup();
      clock.flushMicrotasks();
      expect(call.client.membership, isEmpty);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('Synapse maximum delay is honored with proportionally early pings', () {
    fakeAsync((clock) {
      final call = _Call(clock);
      call.client.maxDelay = 10000;
      unawaited(call.heartbeat.start());
      clock.elapse(const Duration(seconds: 60));
      call.client.expire();
      expect(call.client.delay, const Duration(seconds: 10));
      expect(call.client.restarts, greaterThan(20));
      expect(call.client.expiries, 0);
      call.hangup();
      clock.flushMicrotasks();
    });
  });
}
