// Vommet issue 1176: shared real-SDK/profile/widget fixture; synthetic HTTP only.
import 'dart:async';
import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/components/profile/matrix_self_status.dart';
import 'package:commet/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as mx;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const selfStatusId = '@synthetic:example.invalid';
const legacyStatus = 'LEGACY PROFILE';

// A dependency clock driver; the subject and its HTTP/SDK path remain real.
class SelfStatusClock {
  final clock = FakeAsync();
  late final MatrixSelfStatus status;
  SelfStatusClock(SelfStatusSdk sdk,
      {MatrixSelfStatus Function(DateTime Function())? build}) {
    DateTime now() => DateTime.utc(2026).add(clock.elapsed);
    clock.run(
        (_) => status = build?.call(now) ?? MatrixSelfStatus(sdk, now: now));
  }
  Future<void> flush() async {
    for (var turn = 0; turn < 8; turn++) {
      clock.flushMicrotasks();
      await Future<void>(() {});
    }
    clock.flushMicrotasks();
  }

  Future<mx.CachedPresence?> read() async {
    mx.CachedPresence? answer;
    var done = false;
    clock.run((_) => status.read().then((value) {
          answer = value;
          done = true;
        }));
    await flush();
    expect(done, isTrue,
        reason: 'synthetic immediate SDK response must settle');
    return answer;
  }

  void elapse(Duration duration) => clock.elapse(duration);
  Future<void> close() async {
    var done = false;
    clock.run((_) => status.close().then((_) => done = true));
    await flush();
    expect(done, isTrue, reason: 'clock-owned cache subscription closes');
  }
}

class SelfStatusFixture {
  static int _serial = 0;
  String? serverStatus = 'SERVER B';
  String? profileValue = legacyStatus;
  int? errorStatus;
  int? retryAfterMs;
  String errorCode = 'M_FORBIDDEN';
  Object? presenceFailure;
  bool failWrite = false;
  Completer<void>? delayedWrite;
  final delayedWriteStarted = Completer<void>();
  Completer<http.Response>? delayedPresence;
  final delayedReadStarted = Completer<void>();
  final requests = <http.Request>[];
  late final MatrixSdkDriftDatabase db;
  late final SelfStatusSdk sdk;
  late final SelfStatusAccount account;

  int get presenceGets => requests
      .where((r) => r.method == 'GET' && r.url.path.contains('/presence/'))
      .length;

  int get profileGets => requests
      .where((r) => r.method == 'GET' && r.url.path.contains('/profile/'))
      .length;

  Future<void> init() async {
    db =
        await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), 'synthetic');
    await db.storePresence(
        selfStatusId,
        mx.CachedPresence.fromJson({
          'user_id': selfStatusId,
          'presence': 'online',
          'status_msg': 'CACHED A',
        }));
    sdk = SelfStatusSdk(db, MockClient((request) async {
      requests.add(request);
      if (request.url.path.contains('/presence/')) {
        if (request.method == 'PUT') {
          if (failWrite) throw StateError('Synthetic write failure');
          if (delayedWrite case final pending?) {
            delayedWrite = null;
            delayedWriteStarted.complete();
            await pending.future;
          }
          serverStatus =
              (jsonDecode(request.body) as Map)['status_msg'] as String?;
          return http.Response('{}', 200);
        }
        if (presenceFailure != null) throw presenceFailure!;
        if (delayedPresence != null) {
          if (!delayedReadStarted.isCompleted) delayedReadStarted.complete();
          return delayedPresence!.future;
        }
        if (errorStatus != null)
          return http.Response(
              jsonEncode({
                'errcode': errorCode,
                'error': 'Synthetic unavailable',
                if (retryAfterMs != null) 'retry_after_ms': retryAfterMs
              }),
              errorStatus!);
        return http.Response(
            jsonEncode({
              'presence': 'online',
              if (serverStatus != null) 'status_msg': serverStatus,
            }),
            200);
      }
      if (request.url.path.endsWith('/capabilities'))
        return http.Response(
            jsonEncode({
              'capabilities': {
                'm.profile_fields': {'enabled': true}
              }
            }),
            200);
      if (request.url.path.contains('/profile/')) {
        if (request.method == 'PUT') {
          profileValue = (jsonDecode(request.body)
              as Map)[MatrixProfileComponent.statusKey] as String?;
        }
        if (request.method == 'DELETE') profileValue = null;
        return http.Response(
            jsonEncode({
              'displayname': 'Synthetic User',
              if (profileValue != null)
                MatrixProfileComponent.statusKey: profileValue,
            }),
            200);
      }
      throw StateError(
          'Unexpected request ${request.method} ${request.url.path}');
    }));
    account = SelfStatusAccount(sdk, 'self-status-${_serial++}');
  }

  Future<Profile> profile({bool refresh = true}) =>
      account.profile.getProfile(selfStatusId, forceRefresh: refresh);

  Future<void> sync(String? message) => sdk.handleSync(mx.SyncUpdate.fromJson({
        'next_batch': 'synthetic',
        'presence': {
          'events': [
            {
              'type': 'm.presence',
              'sender': selfStatusId,
              'content': {
                'presence': 'online',
                if (message != null) 'status_msg': message,
              }
            },
          ]
        },
      }));

  Future<void> close() async {
    await account.presence.onClientClosed();
    final Object profile = account.profile;
    if (profile is NeedsCloseOnClientClose) {
      await profile.onClientClosed();
    }
    await db.close();
  }
}

String? profileStatus(Profile profile) =>
    (profile as ProfileWithPresence).precence?.message?.message;

class SelfStatusSdk extends mx.Client {
  SelfStatusSdk(MatrixSdkDriftDatabase db, http.Client transport)
      : super('synthetic', database: db, httpClient: transport) {
    baseUri = Uri.parse('https://example.invalid/');
    bearerToken = 'synthetic';
  }
  @override
  String? get userID => selfStatusId;
}

class SelfStatusAccount extends Fake implements MatrixClient {
  SelfStatusAccount(this.matrixClient, this.identifier) {
    presence = MatrixUserPresenceComponent(this);
    profile = MatrixProfileComponent(this);
  }
  @override
  final SelfStatusSdk matrixClient;
  @override
  final String identifier;
  late final MatrixUserPresenceComponent presence;
  late final MatrixProfileComponent profile;
  @override
  mx.Client getMatrixClient() => matrixClient;
  bool loggedIn = true;
  @override
  bool isLoggedIn() => loggedIn;
  @override
  Profile get self => _SelfProfile(this);
  @override
  T? getComponent<T extends Component>() {
    if (presence is T) return presence as T;
    if (profile is T) return profile as T;
    return null;
  }
}

class _SelfProfile extends MatrixProfile {
  _SelfProfile(MatrixClient client)
      : super(client,
            mx.Profile(userId: selfStatusId, displayName: 'Synthetic User'));
  // Same synthetic presentation as the investigation's Before captures.
  @override
  Color get defaultColor => Colors.blueGrey;
}

class SelfStatusManager extends Fake implements ClientManager {
  SelfStatusManager(Client client)
      : clients = NotifyingList<Client>.from([client]);
  @override
  final NotifyingList<Client> clients;
}
