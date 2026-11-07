import 'dart:async';
import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership_writer.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as mx;
import 'package:matrix/src/utils/cached_stream_controller.dart';

import 'stream_watching_session_test.dart' as fixture;

const _eventType = 'org.matrix.msc3401.call.member';
const _stateKey = '_@me:x_ME_m.call';
const _roomId = '!heartbeat:x';
final _joinContent = <String, dynamic>{
  'application': 'm.call',
  'scope': 'm.room',
  'device_id': 'ME',
  'expires': MatrixRtcMembership.expiresMs,
  'focus_active': {'type': 'livekit', 'focus_selection': 'oldest_membership'},
  'foci_preferred': [
    {'type': 'livekit', 'livekit_service_url': 'https://bridge.example.org'}
  ],
};

class _MatrixClient extends Fake implements mx.Client {
  _MatrixClient({required this.supported}) {
    httpClient = MockClient((request) async => http.Response(
        jsonEncode(await handle(request.method, request.body)), 200));
  }
  final bool supported;
  @override
  late final http.Client httpClient;
  @override
  Uri get homeserver => Uri.parse('https://matrix.example.org');
  @override
  String? get accessToken => null;
  @override
  String? get deviceID => 'ME';
  @override
  final onSync = CachedStreamController<mx.SyncUpdate>();
  int creates = 0;
  final actions = <String>[];
  final memberships = <Map<String, Object?>>[];
  Completer<void>? creating, reading, leaving;

  @override
  Future<mx.GetVersionsResponse> getVersions(
          {Duration cacheLifetime = const Duration(days: 3),
          bool throwOnUpdateFailure = false}) async =>
      mx.GetVersionsResponse(
          versions: ['v1.1'],
          unstableFeatures: {'org.matrix.msc4140': supported});

  Future<Map<String, Object?>> handle(String method, dynamic data) async {
    if (method == 'PUT') {
      creates++;
      if (creating != null) await creating!.future;
      return {'delay_id': 'delay-$creates'};
    }
    actions.add((jsonDecode(data as String) as Map)['action'] as String);
    return {};
  }

  @override
  Future<Map<String, Object?>> request(mx.RequestType type, String action,
          {dynamic data = '',
          String contentType = 'application/json',
          Map<String, Object?>? query}) =>
      handle(type.name, data);

  @override
  Future<mx.MatrixEvent> getOneRoomEvent(String roomId, String eventId) async {
    if (reading != null) await reading!.future;
    return mx.MatrixEvent.fromJson({
      'type': _eventType,
      'event_id': 'join',
      'state_key': _stateKey,
      'sender': '@me:x',
      'origin_server_ts': 1000,
      'content': _joinContent,
    });
  }

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    expect((roomId, eventType, stateKey), (_roomId, _eventType, _stateKey));
    memberships.add(Map.from(body));
    if (body.isEmpty && leaving != null) await leaving!.future;
    // The real SDK's sync echo may lag behind successful writes. Deliberately
    // do not change the room cache here; the production watermark must cope.
    return 'write-${memberships.length}';
  }
}

class _SdkRoom extends Fake implements mx.Room {
  _SdkRoom(this.client);
  @override
  final _MatrixClient client;
  @override
  String get id => _roomId;
  @override
  final Map<String, Map<String, mx.StrippedStateEvent>> states = {};

  void setMembership(Map<String, dynamic> content, int timestamp) {
    states[_eventType] = {
      _stateKey: mx.Event(
        room: this,
        type: _eventType,
        stateKey: _stateKey,
        senderId: '@me:x',
        eventId: 'sync-$timestamp',
        content: content,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(timestamp),
      )
    };
  }
}

class _Me extends Fake implements Profile {
  @override
  String get identifier => '@me:x';
}

class _Client extends Fake implements Client {
  @override
  Profile get self => _Me();
  @override
  Room? getRoom(String identifier) => null;
}

class _Room extends Fake implements MatrixRoom {
  _Room(this.matrixRoom);
  @override
  final _SdkRoom matrixRoom;
  @override
  String get identifier => _roomId;
  @override
  final Client client = _Client();
}

class _Local extends fixture.FakeLocalParticipant {
  _Local() : super(grant: false);
  @override
  bool isMicrophoneEnabled() => false;
}

class _Livekit extends fixture.FakeLivekitRoom {
  _Livekit() : super(_Local());
  int disconnects = 0;
  @override
  Future<void> disconnect() async {
    disconnects++;
    emit(lk.RoomDisconnectedEvent(reason: lk.DisconnectReason.clientInitiated));
  }
}

/// All lifecycle operations and writer predicates below are production code.
/// Only Matrix transport/cache and LiveKit media are fixtures.
class _Session {
  _Session(
      {bool supported = true,
      Completer<void>? creating,
      Completer<void>? reading}) {
    client = _MatrixClient(supported: supported)
      ..creating = creating
      ..reading = reading;
    sdkRoom = _SdkRoom(client)..setMembership(_joinContent, 1000);
    writer = MatrixLivekitBackend.membershipWriterFor(_Room(sdkRoom), 'join');
    session = MatrixLivekitVoipSession(_Room(sdkRoom), livekit,
        membershipWriter: writer);
  }
  late final _MatrixClient client;
  late final _SdkRoom sdkRoom;
  late final MatrixRtcMembershipWriter writer;
  final livekit = _Livekit();
  late final MatrixLivekitVoipSession session;
}

void _hourlyRefresh(FakeAsync clock) {
  clock.elapseBlocking(Duration(
      milliseconds:
          MatrixRtcMembership.refreshEveryMs - MatrixRtcMembership.headroomMs));
  clock.elapse(Duration.zero);
  clock.flushMicrotasks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(fixture.setUpWatchingPreferences);

  test('real hangUpCall cancels late creation and never restarts or re-posts',
      () {
    fakeAsync((clock) {
      final creating = Completer<void>();
      final call = _Session(creating: creating);
      clock.flushMicrotasks();
      expect(call.client.creates, 1);
      var hungUp = false;
      unawaited(call.session.hangUpCall().then((_) => hungUp = true));
      clock.flushMicrotasks();
      expect(hungUp, isTrue);
      expect(call.session.state, VoipState.ended);
      expect(call.livekit.disconnects, 1);
      creating.complete();
      clock.flushMicrotasks();
      // Cancel the newly returned resource once; it must not install a timer.
      final requests = (
        call.client.creates,
        call.client.actions.length,
        call.client.memberships.length
      );
      clock.elapse(const Duration(minutes: 2));
      expect((
        call.client.creates,
        call.client.actions.length,
        call.client.memberships.length
      ), requests);
      expect(call.client.actions, ['cancel']);
      expect(call.client.memberships.single, isEmpty);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('real endLocally prevents an in-flight refresh read from posting', () {
    fakeAsync((clock) {
      final reading = Completer<void>();
      final call = _Session(reading: reading);
      clock.flushMicrotasks();
      _hourlyRefresh(clock);
      expect(call.client.memberships, isEmpty);
      call.session.endLocally();
      clock.flushMicrotasks();
      expect(call.session.state, VoipState.ended);
      final requests = (call.client.creates, call.client.actions.length);
      reading.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(hours: 2));
      expect(call.client.memberships, isEmpty);
      expect((call.client.creates, call.client.actions.length), requests);
      expect(call.livekit.disconnects, 1);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
      'real hourly refresh recovers, retries in a minute and uses backend sync watermarks',
      () {
    fakeAsync((clock) {
      final call = _Session();
      clock.flushMicrotasks();
      // No sync notification: only the production writer/refresh path sees it.
      call.sdkRoom.setMembership({}, 2000);
      _hourlyRefresh(clock);
      expect(call.client.creates, 2);
      expect(call.client.memberships, hasLength(1));
      final recovered = call.client.memberships.single;
      expect(recovered['created_ts'], 1000);
      expect(recovered['expires'], MatrixRtcMembership.expiresMs * 2);
      expect(recovered['focus_active'], _joinContent['focus_active']);
      expect(recovered['foci_preferred'], _joinContent['foci_preferred']);
      clock.elapse(const Duration(seconds: 59));
      expect(call.client.memberships, hasLength(1));
      clock.elapse(const Duration(seconds: 1));
      expect(call.client.memberships, hasLength(2));
      // Cache still shows {}, timestamp 2000; acknowledged by production
      // currentOriginServerTs so it cannot repeatedly close the recovered join.
      expect(call.client.creates, 2);
      expect(call.client.memberships.last['created_ts'], 1000);
      call.sdkRoom.setMembership({}, 3000);
      unawaited(call.writer.update((_) {}));
      clock.flushMicrotasks();
      expect(
          call.client.creates, 3); // a newer empty state does trigger recovery
      expect(call.client.memberships.last['created_ts'], 1000);
      unawaited(call.session.hangUpCall());
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 100));
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('real unsupported server closes lost membership without minute retries',
      () {
    fakeAsync((clock) {
      final call = _Session(supported: false);
      clock.flushMicrotasks();
      call.sdkRoom.setMembership({}, 2000);
      _hourlyRefresh(clock);
      clock.elapse(const Duration(minutes: 3));
      expect(call.client.creates, 0);
      expect(call.client.actions, isEmpty);
      expect(call.client.memberships, isEmpty);
      expect(clock.nonPeriodicTimerCount, 0);
      // Restoring the cache cannot resurrect a permanently closed writer.
      call.sdkRoom.setMembership(_joinContent, 3000);
      bool? written;
      unawaited(call.writer.update((_) {}).then((value) => written = value));
      clock.flushMicrotasks();
      expect(written, isFalse);
      unawaited(call.session.hangUpCall());
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 100));
      expect(clock.pendingTimers, isEmpty);
    });
  });
}
