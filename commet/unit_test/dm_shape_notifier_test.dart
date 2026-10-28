// Vommet ("New room info page"): DmShapes / DmShapeNotifier, the room-level
// side of the live direct-chat rules (the rules themselves: dm_shape_test).
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/direct_messages/dm_shape_notifier.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/utils/dm_shape.dart';
import 'package:flutter_test/flutter_test.dart';

const juniper = "@juniper:example.org";

class _FakeDms extends Fake implements DirectMessagesComponent<Client> {
  bool direct = true;
  final List<bool> set = [];

  @override
  bool isRoomDirectMessage(Room room) => direct;

  @override
  String? getDirectMessagePartnerId(Room room) => direct ? juniper : null;

  @override
  Future<void> setDirectMessage(Room room, bool isDirectMessage) async {
    set.add(isDirectMessage);
    direct = isDirectMessage;
  }
}

class _FakeInvitations extends Fake implements InvitationComponent<Client> {
  final List<(String, String)> invited = [];

  @override
  Future<void> inviteUserToRoom(
      {required String userId, required String roomId}) async {
    invited.add((userId, roomId));
  }
}

class _FakeClient extends Fake implements Client {
  final dms = _FakeDms();
  final invitations = _FakeInvitations();

  @override
  T? getComponent<T extends Component>() {
    if (dms is T) return dms as T;
    if (invitations is T) return invitations as T;
    return null;
  }
}

class _FakeRoom extends Fake implements Room {
  _FakeRoom(this.client);

  @override
  final _FakeClient client;

  final updates = StreamController<void>.broadcast();
  final members = StreamController<void>.broadcast();
  String? name;

  @override
  String get identifier => "!dm:example.org";

  @override
  Stream<void> get onUpdate => updates.stream;

  @override
  Stream<void> get onMembersChanged => members.stream;

  @override
  Future<void> setDisplayName(String newName) async => name = newName;
}

void main() {
  late _FakeRoom room;

  setUp(() => room = _FakeRoom(_FakeClient()));

  test("with the experiment off, m.direct alone decides", () {
    expect(DmShapes.of(room),
        const DmShape(DmShapeKind.person, partnerId: juniper));
    expect(DmShapes.showsPerson(room), isTrue);
    room.client.dms.direct = false;
    expect(DmShapes.of(room), DmShape.room);
    expect(DmShapes.showsPerson(room), isFalse);
  });

  test("the notifier follows the room and only listens while listened to",
      () async {
    final notifier = DmShapeNotifier.of(room);
    expect(identical(notifier, DmShapeNotifier.of(room)), isTrue);
    expect(room.updates.hasListener, isFalse);

    var calls = 0;
    void listener() => calls++;
    notifier.addListener(listener);
    expect(room.updates.hasListener, isTrue);
    expect(notifier.value.isPerson, isTrue);

    room.client.dms.direct = false;
    room.updates.add(null);
    await pumpEventQueue();
    expect(calls, 1);
    expect(notifier.value, DmShape.room);

    // Nothing changed: no notification.
    room.members.add(null);
    await pumpEventQueue();
    expect(calls, 1);

    notifier.removeListener(listener);
    expect(room.updates.hasListener, isFalse);
    expect(room.members.hasListener, isFalse);
  });

  test("Move to Rooms clears m.direct, and only that", () async {
    await DmShapes.moveToRooms(room);
    expect(room.client.dms.set, [false]);
  });

  test("Name this group sets the room's name", () async {
    await DmShapes.nameGroup(room, "  Weekend plans ");
    expect(room.name, "Weekend plans");
    expect(room.client.dms.set, isEmpty);
  });

  test("Invite back invites the partner", () async {
    await DmShapes.inviteBack(room);
    expect(room.client.invitations.invited, [(juniper, "!dm:example.org")]);
  });
}
