import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/space_call_badge.dart';
import 'package:commet/utils/image_or_icon.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ClientManager implements ClientManager {
  _ClientManager() {
    callManager = CallManager(this);
  }
  @override
  late CallManager callManager;
  @override
  final NotifyingList<Client> clients = NotifyingList.empty(growable: true);
  @override
  StreamController<int> onClientAdded = StreamController.broadcast();
  @override
  StreamController<StalePeerInfo> onClientRemoved =
      StreamController.broadcast();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Client implements Client {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Voip implements VoipRoomComponent {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Activities implements ActivitiesComponent {
  List<RoomActivitySession> sessions = [];
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  List<RoomActivitySession> getSessions() => sessions;
  @override
  Stream<void> get onSessionsChanged => changes.stream;
  void people(int n) {
    sessions = [
      if (n > 0)
        RoomActivitySession(
            participants: {for (var i = 0; i < n; i++) "@p$i:x"},
            application: "call",
            thirdparty: false,
            icon: ImageOrIcon(icon: Icons.call)),
    ];
    changes.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Room implements Room {
  _Room(this.identifier);
  @override
  final String identifier;
  final voip = _Voip();
  final activities = _Activities();
  @override
  T? getComponent<T extends RoomComponent>() {
    if (voip is T) return voip as T;
    if (activities is T) return activities as T;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Space implements Space {
  _Space(this.client, this.roomsWithChildren);
  @override
  final Client client;
  @override
  final List<Room> roomsWithChildren;
  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Screen implements VoipStream {
  @override
  VoipStreamType get type => VoipStreamType.screenshare;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Call implements VoipSession {
  _Call(this.client, this.roomId);
  @override
  final Client client;
  @override
  final String roomId;
  @override
  VoipState get state => VoipState.connected;
  @override
  String get sessionId => "call-$roomId";
  @override
  List<VoipStream> streams = [];
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get onStateChanged => changes.stream;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _Client client;
  late _Room lounge, notes;
  late _Space space;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.experimentSidebarSubspaceGuides.set(true);
    clientManager = _ClientManager();
    client = _Client();
    lounge = _Room("!lounge:x");
    notes = _Room("!notes:x");
    space = _Space(client, [lounge, notes]);
  });

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(home: Material(child: Center(child: SpaceCallBadge(space)))));

  testWidgets("nothing while nobody's in a call", (tester) async {
    await show(tester);
    expect(find.byIcon(Icons.headphones), findsNothing);
    expect(find.text("LIVE"), findsNothing);
  });

  testWidgets("headphones while people are in a call there", (tester) async {
    await show(tester);
    lounge.activities.people(2);
    await tester.pump();
    expect(find.byIcon(Icons.headphones), findsOneWidget);
    lounge.activities.people(0);
    await tester.pump();
    expect(find.byIcon(Icons.headphones), findsNothing);
  });

  testWidgets("LIVE while someone shares a screen in your call there",
      (tester) async {
    lounge.activities.people(2);
    final call = _Call(client, lounge.identifier);
    clientManager!.callManager.currentSessions.add(call);
    await show(tester);
    expect(find.byIcon(Icons.headphones), findsOneWidget);
    call.streams.add(_Screen());
    call.changes.add(null);
    await tester.pump();
    expect(find.text("LIVE"), findsOneWidget);
    expect(find.byIcon(Icons.headphones), findsNothing);
  });

  testWidgets("a call in another space doesn't count", (tester) async {
    final elsewhere = _Call(client, "!other:x")..streams.add(_Screen());
    clientManager!.callManager.currentSessions.add(elsewhere);
    await show(tester);
    expect(find.text("LIVE"), findsNothing);
  });

  testWidgets("nothing with the experiment off", (tester) async {
    await preferences.experimentSidebarSubspaceGuides.set(false);
    lounge.activities.people(2);
    await show(tester);
    expect(find.byIcon(Icons.headphones), findsNothing);
  });
}
