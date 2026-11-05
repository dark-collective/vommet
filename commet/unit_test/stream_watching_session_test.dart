import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership_writer.dart';
import 'package:commet/client/matrix/components/voip_room/vommet_stream_watching.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 871: LivekitStreamWatching on a real MatrixLivekitVoipSession.
// Only the LiveKit room and its participants are faked; they behave like
// livekit_client: events come through the room's EventsEmitter, setAttributes
// throws when the SFU refuses or (after 5 s) never answers, publishData
// takes a topic and destination identities.

const _topic = "im.vommet.watching";

class SentData {
  SentData(this.data, this.reliable, this.topic, this.to);
  final String data;
  final bool? reliable;
  final String? topic;
  final List<String>? to;
}

class FakeLocalParticipant extends Fake implements lk.LocalParticipant {
  FakeLocalParticipant({required bool grant, this.attributeError})
      : permissions = lk.ParticipantPermissions(canUpdateMetadata: grant);

  @override
  String get identity => "@me:x:ME";
  @override
  lk.ParticipantPermissions permissions;

  /// Thrown by setAttributes (the SFU refused it, or never answered).
  Object? attributeError;
  final List<Map<String, String>> attributeCalls = [];
  final List<SentData> sent = [];

  @override
  Future<void> setAttributes(Map<String, String> attributes) async {
    attributeCalls.add(attributes);
    final error = attributeError;
    if (error != null) throw error;
  }

  @override
  Future<void> publishData(List<int> data,
      {bool? reliable,
      List<String>? destinationIdentities,
      String? topic}) async {
    sent.add(
        SentData(utf8.decode(data), reliable, topic, destinationIdentities));
  }

  @override
  Map<String, lk.LocalTrackPublication> get trackPublications => {};
  @override
  lk.LocalTrackPublication? getTrackPublicationBySource(
          lk.TrackSource source) =>
      null;
}

class FakeRemoteParticipant extends Fake implements lk.RemoteParticipant {
  FakeRemoteParticipant(this.identity);
  @override
  final String identity;
  @override
  UnmodifiableMapView<String, String> get attributes => UnmodifiableMapView({});
  @override
  final Map<String, lk.RemoteTrackPublication> trackPublications = {};
}

class _Share extends Fake
    implements lk.RemoteTrackPublication<lk.RemoteVideoTrack> {
  _Share(this.participant);
  @override
  final lk.RemoteParticipant participant;
  @override
  String get sid => "TR_share";
  @override
  String get name => "screen";
  @override
  lk.TrackType get kind => lk.TrackType.VIDEO;
  @override
  lk.TrackSource get source => lk.TrackSource.screenShareVideo;
  @override
  bool get isScreenShare => true;
  @override
  lk.RemoteVideoTrack? get track => null;
  @override
  bool get simulcasted => false;
  @override
  bool get subscribed => false;
  @override
  bool get muted => false;
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

class FakeLivekitRoom extends Fake implements lk.Room {
  FakeLivekitRoom(this.localParticipant);
  @override
  final lk.LocalParticipant localParticipant;
  final Map<String, lk.RemoteParticipant> peers = {};
  @override
  UnmodifiableMapView<String, lk.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView(peers);
  @override
  final lk.EventsEmitter<lk.RoomEvent> events = lk.EventsEmitter();
  @override
  lk.EventsListener<lk.RoomEvent> createListener({bool synchronized = false}) =>
      lk.EventsListener(events, synchronized: synchronized);

  // ignore: invalid_use_of_internal_member
  void emit(lk.RoomEvent event) => events.emit(event);

  void join(FakeRemoteParticipant peer) {
    peers[peer.identity] = peer;
    emit(lk.ParticipantConnectedEvent(participant: peer));
  }
}

class _MatrixClient extends Fake implements matrix.Client {
  // The heartbeat waits here; it isn't part of this test.
  @override
  Future<matrix.GetVersionsResponse> getVersions(
      {Duration cacheLifetime = const Duration(days: 3),
      bool throwOnUpdateFailure = false}) {
    return Completer<matrix.GetVersionsResponse>().future;
  }
}

class _MatrixRoomSdk extends Fake implements matrix.Room {
  @override
  final matrix.Client client = _MatrixClient();
  // No call memberships: identities are "@user:server:DEVICE".
  @override
  final Map<String, Map<String, matrix.StrippedStateEvent>> states = {};
}

class _Me extends Fake implements Profile {
  @override
  String get identifier => "@me:x";
}

class _Client extends Fake implements Client {
  @override
  Profile? get self => _Me();
  @override
  Room? getRoom(String identifier) => null;
}

class _MatrixRoom extends Fake implements MatrixRoom {
  @override
  String get identifier => "!call:x";
  @override
  final Client client = _Client();
  @override
  final matrix.Room matrixRoom = _MatrixRoomSdk();
}

/// A call on a real [MatrixLivekitVoipSession] (Watch stream on) where
/// "@sharer" shares their screen and "@b" is in the call too.
class WatchingCall {
  WatchingCall._(this.local, this.room, this.session, this.share);

  final FakeLocalParticipant local;
  final FakeLivekitRoom room;
  final MatrixLivekitVoipSession session;
  final MatrixLivekitVoipStream share;

  static final sharer = FakeRemoteParticipant("@sharer:x:S");
  static final b = FakeRemoteParticipant("@b:x:B");

  VoipStreamWatching get watching => VoipStreamWatching.of(session)!;

  /// What @b says it watches, as a data message.
  void receiveFromB(String value) => room.emit(lk.DataReceivedEvent(
      participant: b, data: utf8.encode(value), topic: _topic));

  void end() {
    session.state = VoipState.ended;
    session.stopMembershipRefresh();
  }
}

Future<void> setUpWatchingPreferences() async {
  // The call checks connectivity.
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (_) async => <String>['wifi'],
  );
  messenger.setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    MockStreamHandler.inline(
      onListen: (_, sink) => sink.success(<String>['wifi']),
    ),
  );
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  await LivekitStreamWatching.experiment.set(true);
  await VoipStreamWatching.showWatching.set(true);
}

// Our membership isn't part of this test.
Future<({Map<String, dynamic> content, int originServerTs})> _neverRead() =>
    Completer<({Map<String, dynamic> content, int originServerTs})>().future;

/// [grant]: the token's canUpdateOwnMetadata; [attributeError]: what
/// setAttributes throws.
Future<WatchingCall> startWatchingCall(
    {required bool grant, Object? attributeError}) async {
  final local =
      FakeLocalParticipant(grant: grant, attributeError: attributeError);
  final room = FakeLivekitRoom(local)
    ..peers[WatchingCall.sharer.identity] = WatchingCall.sharer
    ..peers[WatchingCall.b.identity] = WatchingCall.b;
  final writer =
      MatrixRtcMembershipWriter(readInitial: _neverRead, send: (_) async {});
  final session =
      MatrixLivekitVoipSession(_MatrixRoom(), room, membershipWriter: writer);
  final share =
      MatrixLivekitVoipStream(_Share(WatchingCall.sharer), "@sharer:x");
  session.streams.add(share);
  await pumpEventQueue();
  return WatchingCall._(local, room, session, share);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WatchingCall call;

  Future<void> start({required bool grant, Object? attributeError}) async {
    call =
        await startWatchingCall(grant: grant, attributeError: attributeError);
  }

  setUp(setUpWatchingPreferences);
  tearDown(() => call.end());

  test("without the grant, who we watch goes out as a data message only",
      () async {
    await start(grant: false);
    await call.watching.setWatching(call.share, true);
    await pumpEventQueue();

    expect(call.local.attributeCalls, isEmpty);
    expect(call.local.sent, hasLength(1));
    expect(call.local.sent.single.topic, _topic);
    expect(call.local.sent.single.reliable, true);
    expect(call.local.sent.single.to, isNull);
    expect(call.local.sent.single.data, '["@sharer:x"]');
  });

  test("a watcher known only from a data message is listed", () async {
    await start(grant: false);
    call.receiveFromB('["@sharer:x"]');
    await pumpEventQueue();

    expect(call.watching.viewersOf(call.share), contains("@b:x"));
  });

  test("when setting the attribute times out, data messages are used",
      () async {
    await start(grant: true, attributeError: TimeoutException("no answer"));
    await call.watching.setWatching(call.share, true);
    await pumpEventQueue();
    call.receiveFromB('["@sharer:x"]');
    await pumpEventQueue();

    // Still kept up to date: the SFU may have applied it quietly.
    expect(call.local.attributeCalls.last, {_topic: '["@sharer:x"]'});
    expect(call.local.sent.map((s) => s.data), ['["@sharer:x"]']);
    expect(call.watching.viewersOf(call.share), contains("@b:x"));
  });

  test("a newcomer, and only the newcomer, is told again", () async {
    await start(grant: false);
    await call.watching.setWatching(call.share, true);
    await pumpEventQueue();
    expect(call.local.sent, hasLength(1));

    // Joins with nothing published, so no stream changes.
    call.room.join(FakeRemoteParticipant("@c:x:C"));
    await pumpEventQueue();

    expect(call.local.sent, hasLength(2));
    expect(call.local.sent.last.to, ["@c:x:C"]);
    expect(call.local.sent.last.data, '["@sharer:x"]');
  });

  test("turning the setting off sends [] and the watcher drops out", () async {
    await start(grant: false);
    await call.watching.setWatching(call.share, true);
    call.receiveFromB('["@sharer:x"]');
    await pumpEventQueue();
    expect(call.watching.viewersOf(call.share), contains("@b:x"));

    await VoipStreamWatching.showWatching.set(false);
    await pumpEventQueue();
    expect(call.local.sent.last.data, "[]");
    expect(call.local.sent.last.to, isNull);

    call.receiveFromB("[]");
    await pumpEventQueue();
    expect(call.watching.viewersOf(call.share), isNot(contains("@b:x")));
  });
}
