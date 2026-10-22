// Vommet issue 580: the People button under Home and the list of every
// direct message it opens.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/direct_messages/direct_message_aggregator.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/people/people_list.dart';
import 'package:commet/ui/organisms/people/people_model.dart';
import 'package:commet/ui/organisms/people/people_strings.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Member extends Fake implements Member {
  _Member(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.teal;
}

class _Self extends Fake implements Profile {
  _Self(this.identifier);
  @override
  final String identifier;
}

class _Dms extends Fake implements DirectMessagesComponent {
  final partners = <String, String>{};
  @override
  String? getDirectMessagePartnerId(Room room) => partners[room.identifier];
  @override
  bool isRoomDirectMessage(Room room) => true;
}

class _Invites extends Fake implements InvitationComponent {
  @override
  final NotifyingList<Invitation> invitations =
      NotifyingList.empty(growable: true);
  final accepted = <String>[];
  @override
  Future<void> acceptInvitation(Invitation invitation) async =>
      accepted.add(invitation.roomId);
}

class _Client extends Fake implements Client {
  _Client(this.identifier);
  @override
  final String identifier;
  final dms = _Dms();
  final invites = _Invites();
  @override
  Profile? get self => _Self("@me:$identifier");
  @override
  T? getComponent<T extends Component>() {
    if (dms is T) return dms as T;
    if (invites is T) return invites as T;
    return null;
  }
}

class _Permissions implements Permissions {
  @override
  dynamic noSuchMethod(Invocation i) => false;
}

class _Room extends Fake implements Room {
  _Room(this.client, this.identifier, this.displayName,
      {int minutesAgo = 0,
      this.notificationCount = 0,
      String? partner,
      List<String> others = const []}) {
    lastEventTimestamp =
        DateTime(2026, 10, 22, 12).subtract(Duration(minutes: minutesAgo));
    if (partner != null) {
      client.dms.partners[identifier] = partner;
      members[partner] = _Member(partner, displayName);
    }
    for (final id in [if (partner != null) partner, ...others]) {
      members.putIfAbsent(id, () => _Member(id, id.substring(1, 2)));
    }
  }

  @override
  final _Client client;
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  late final DateTime lastEventTimestamp;
  @override
  int notificationCount;
  final members = <String, Member>{};
  bool failRead = false;
  int reads = 0;

  @override
  String get localId => "${client.identifier}:$identifier";
  @override
  Iterable<String> get memberIds => [client.self!.identifier, ...members.keys];
  @override
  Member getMemberOrFallback(String id) => members[id] ?? _Member(id, id);
  @override
  PushRule get pushRule => PushRule.notify;
  @override
  Future<void> markAsRead() async {
    reads++;
    if (failRead) throw Exception("offline");
    notificationCount = 0;
  }

  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  TimelineEvent? get lastMessage => null;
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.orange;
  @override
  bool get isFavorite => false;
  @override
  bool get isSpecialRoomType => false;
  @override
  bool get isE2EE => true;
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  Permissions get permissions => _Permissions();
}

class _Aggregator extends Fake implements DirectMessagesAggregator {
  _Aggregator(List<Room> rooms)
      : directMessageRooms = NotifyingList.from(rooms, growable: true);
  @override
  INotifyingList<Room> directMessageRooms;
  @override
  final StreamController<void> onEventReceived = StreamController.broadcast();
}

class _ClientManager extends Fake implements ClientManager {
  _ClientManager(List<Client> clients, List<Room> dms)
      : clients = NotifyingList.from(clients, growable: true),
        directMessages = _Aggregator(dms);
  @override
  final NotifyingList<Client> clients;
  @override
  final DirectMessagesAggregator directMessages;
  @override
  final StreamController<int> onClientAdded = StreamController.broadcast();
  @override
  final StreamController<StalePeerInfo> onClientRemoved =
      StreamController.broadcast();
}

void main() {
  late _Client home;
  late _Client work;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    home = _Client("home.example");
    work = _Client("work.example");
  });

  group("PeopleModel", () {
    test("on by default, and hideable", () async {
      expect(PeopleModel.enabled, isTrue);
      await preferences.peopleInRail.set(false);
      expect(PeopleModel.enabled, isFalse);
    });

    test("lists DMs newest first, filtered by account and search", () {
      final pell = _Room(home, "!a", "Pell", minutesAgo: 30, partner: "@pell");
      final juni = _Room(home, "!b", "Juni", minutesAgo: 5, partner: "@juni");
      final quill =
          _Room(work, "!c", "Quill", minutesAgo: 60, partner: "@quill");

      expect(PeopleModel.rooms([pell, quill, juni]), [juni, pell, quill]);
      expect(
          PeopleModel.rooms([pell, quill, juni], client: home), [juni, pell]);
      expect(PeopleModel.rooms([pell, quill, juni], query: "qui"), [quill]);
      // By the other person's Matrix ID too, as on Home.
      expect(PeopleModel.rooms([pell, quill, juni], query: "@juni"), [juni]);
      expect(PeopleModel.rooms([pell, quill, juni], query: "nobody"), isEmpty);
    });

    test("the badge counts unread DM messages", () {
      final rooms = [
        _Room(home, "!a", "Pell", notificationCount: 2),
        _Room(home, "!b", "Juni", notificationCount: 1),
        _Room(work, "!c", "Quill", notificationCount: 4),
      ];
      expect(PeopleModel.unreadCount(rooms), 7);
      expect(PeopleModel.unreadCount(rooms, client: home), 3);
      expect(PeopleModel.unreadCount(const []), 0);
    });

    test("only direct invitations, per account", () {
      home.invites.invitations.addAll([
        Invitation(roomId: "!dm", senderId: "@sorrel", isDirect: true),
        Invitation(roomId: "!room", senderId: "@sorrel"),
      ]);
      work.invites.invitations
          .add(Invitation(roomId: "!dm2", senderId: "@wren", isDirect: true));

      final all = PeopleModel.directInvitations([home, work]);
      expect(all.map((e) => e.$2.roomId), ["!dm", "!dm2"]);
      expect(all.first.$1, same(home.invites));
      expect(
          PeopleModel.directInvitations([home, work], client: work)
              .map((e) => e.$2.roomId),
          ["!dm2"]);
    });

    test("a group DM has more than one other person", () {
      final one = _Room(home, "!a", "Pell", partner: "@pell");
      final group =
          _Room(home, "!g", "Mossy, Sorrel", others: ["@mossy", "@sorrel"]);
      expect(PeopleModel.isGroup(one), isFalse);
      expect(PeopleModel.isGroup(group), isTrue);
      expect(PeopleModel.groupMemberIds(group), ["@mossy", "@sorrel"]);
    });

    test("mark all as read skips read DMs and survives a failure", () async {
      final a = _Room(home, "!a", "Pell", notificationCount: 2)
        ..failRead = true;
      final b = _Room(home, "!b", "Juni", notificationCount: 1);
      final c = _Room(home, "!c", "Quill");
      await PeopleModel.markAllRead([a, b, c]);
      expect(a.reads, 1);
      expect(b.reads, 1);
      expect(b.notificationCount, 0);
      expect(c.reads, 0);
    });
  });

  group("PeopleList", () {
    late _Room pell;
    late _Room juni;
    late _Room group;
    Room? opened;
    var newMessage = 0;

    Future<void> pump(WidgetTester tester) async {
      opened = null;
      newMessage = 0;
      pell = _Room(home, "!a", "Pell",
          minutesAgo: 30, notificationCount: 2, partner: "@pell");
      juni = _Room(home, "!b", "Juni", minutesAgo: 5, partner: "@juni");
      group = _Room(home, "!g", "Mossy, Sorrel",
          minutesAgo: 90, others: ["@mossy", "@sorrel"]);
      home.invites.invitations.add(Invitation(
          roomId: "!dm",
          displayName: "Tansy",
          senderId: "@tansy",
          isDirect: true));

      final manager = _ClientManager([home], [pell, group, juni]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          // As narrow as the room list column goes.
          body: SizedBox(
            width: 240,
            child: PeopleList(
              clientManager: manager,
              onSelectRoom: (room) => opened = room,
              onNewMessage: () => newMessage++,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets("header, search, invites, then every DM newest first",
        (tester) async {
      await pump(tester);

      expect(find.text(PeopleStrings.labelPeople), findsOneWidget);
      expect(find.text(PeopleStrings.peopleSearchHint), findsOneWidget);
      expect(find.text(PeopleStrings.peopleInvitesHeader(1)), findsOneWidget);
      expect(find.text("Tansy"), findsOneWidget);
      expect(find.text(PeopleStrings.peopleDirectMessagesHeader(3)),
          findsOneWidget);

      final rows = tester
          .widgetList<PeopleRow>(find.byType(PeopleRow))
          .map((r) => r.room.displayName)
          .toList();
      expect(rows, ["Juni", "Pell", "Mossy, Sorrel"]);

      // The unread count is on Pell's row.
      expect(
          find.descendant(
              of: find.widgetWithText(PeopleRow, "Pell"),
              matching: find.text("2")),
          findsOneWidget);
    });

    testWidgets("tapping a DM opens it; pencil and accept work",
        (tester) async {
      await pump(tester);

      await tester.tap(find.text("Juni"));
      expect(opened, same(juni));

      await tester.tap(find.byIcon(Icons.edit_square));
      expect(newMessage, 1);

      // Invitations accept from their row.
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(home.invites.accepted, ["!dm"]);
    });

    testWidgets("search filters people and says when no one matches",
        (tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(PeopleList.searchKey), "pel");
      await tester.pumpAndSettle();
      expect(find.byType(PeopleRow), findsOneWidget);
      expect(find.text("Pell"), findsOneWidget);
      // Invitations step aside while searching.
      expect(find.text("Tansy"), findsNothing);

      await tester.enterText(find.byKey(PeopleList.searchKey), "zz");
      await tester.pumpAndSettle();
      expect(find.byType(PeopleRow), findsNothing);
      expect(
          find.text(PeopleStrings.peopleSearchNoResults("zz")), findsOneWidget);
    });
  });
}
