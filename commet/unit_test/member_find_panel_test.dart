// Vommet: the member list's find row is pinned at the top of the list both
// with the member panel's tabs on (under the tab strip) and off (under the
// "Room members" label), and offers to invite when nobody matches.
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/role.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/organisms/room_members_list/room_members_list.dart';
import 'package:flutter/material.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Permissions extends Permissions {
  _Permissions({this.canBan = false});
  @override
  final bool canBan;
}

class _Presence extends Fake implements UserPresenceComponent {
  @override
  Stream<(String, UserPresence)> get onPresenceChanged => const Stream.empty();
  @override
  UserPresence? cachedPresence(String userId) =>
      UserPresence(UserPresenceStatus.online);
  @override
  Future<UserPresence> getUserPresence(String userId) async =>
      UserPresence(UserPresenceStatus.online);
}

class _Self extends Fake implements Profile {
  @override
  String get identifier => "@me:lantern.example";
}

class _Client extends Fake implements Client {
  _Client(this.presence);
  final _Presence? presence;
  @override
  T? getComponent<T extends Component>() =>
      presence is T ? presence as T : null;
  @override
  Profile? get self => _Self();
}

class _FindMember implements Member {
  _FindMember(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  String get userName => identifier;
  @override
  String? get detail => null;
  @override
  String? get avatarId => null;
  @override
  ImageProvider? get avatar => null;
  @override
  ImageProvider? get largeAvatar => null;
  @override
  Color get defaultColor => Colors.teal;
}

class _Room extends Fake implements Room {
  _Room(
      {this.members = const [],
      this.banned = const [],
      _Presence? presence,
      bool canBan = false})
      : client = _Client(presence),
        permissions = _Permissions(canBan: canBan);
  final List<Member> members;
  final List<Member> banned;
  @override
  final Client client;
  @override
  final Permissions permissions;
  @override
  List<Member> membersList() => [...members];
  @override
  List<(Member, Role)> importantMembers() => [];
  @override
  List<Member> membersWithMembership(MemberMembership membership) =>
      membership == MemberMembership.banned ? banned : [];
  @override
  bool get isMembersListComplete => true;
  @override
  int get memberCount => 4812;
  @override
  bool memberHasLeft(String identifier) => false;
  @override
  Stream<void> get onMembersChanged => const Stream.empty();
  @override
  T? getComponent<T extends RoomComponent>() => null;
}

class _Strip extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;
  @override
  Widget build(context, shrinkOffset, overlapsContent) =>
      const SizedBox(key: ValueKey("strip"), height: 44);
  @override
  bool shouldRebuild(_) => false;
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  Future<List<String?>> pump(WidgetTester tester,
      {required bool tabs,
      bool findBox = true,
      _Room? room,
      RedactionSettings redaction = const RedactionSettings()}) async {
    final invites = <String?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RedactionScope.withSettings(
          settings: redaction,
          child: RoomMemberList(
            room ?? _Room(),
            directMessage: false,
            findBox: findBox,
            onInvite: invites.add,
            leading: [
              const SliverToBoxAdapter(child: SizedBox(height: 300)),
              if (tabs)
                SliverPersistentHeader(pinned: true, delegate: _Strip())
              else
                const SliverToBoxAdapter(child: Text("Room members")),
            ],
            trailing: const [
              SliverToBoxAdapter(child: SizedBox(height: 3000)),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    return invites;
  }

  for (final tabs in [true, false]) {
    testWidgets("pinned find row, tabs ${tabs ? "on" : "off"}", (tester) async {
      await pump(tester, tabs: tabs);
      final header = find.byKey(const ValueKey("member-panel-find-header"));
      expect(header, findsOneWidget);
      expect(find.byKey(const ValueKey("member-panel-invite-button")),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey("member-panel-invite-card")), findsNothing);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
      await tester.pump();
      final top =
          tester.getTopLeft(find.byKey(const ValueKey("member-panel-find"))).dy;
      expect(top, lessThan(tabs ? 44 + 56 : 56));
    });
  }

  testWidgets("no match: invite row with the query", (tester) async {
    final invites = await pump(tester, tabs: true);
    await tester.enterText(find.byKey(const ValueKey("member-panel-find")),
        "@bob:lantern.example");
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("0 of 4,812 · name or ID"), findsOneWidget);
    expect(find.text("Invite @bob:lantern.example"), findsOneWidget);
    expect(find.byKey(const ValueKey("member-panel-find-chip-banned")),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey("member-panel-find-invite")));
    expect(invites, ["@bob:lantern.example"]);
  });

  test("find box: Members tab with tabs on, any remembered tab with tabs off",
      () {
    for (final tab in MemberPanelTab.values) {
      expect(
          MemberPanelTab.showsFindBox(
              directMessage: false, tabs: true, tab: tab),
          tab == MemberPanelTab.members);
      expect(
          MemberPanelTab.showsFindBox(
              directMessage: false, tabs: false, tab: tab),
          isTrue);
      expect(
          MemberPanelTab.showsFindBox(
              directMessage: true, tabs: false, tab: tab),
          isFalse);
    }
  });

  testWidgets("tabs off, remembered Media tab: box and invite button",
      (tester) async {
    await pump(tester,
        tabs: false,
        findBox: MemberPanelTab.showsFindBox(
            directMessage: false, tabs: false, tab: MemberPanelTab.media));
    expect(find.byKey(const ValueKey("member-panel-find")), findsOneWidget);
    expect(find.byKey(const ValueKey("member-panel-invite-button")),
        findsOneWidget);
  });

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
        find.byKey(const ValueKey("member-panel-find")), query);
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets("redacted names: only the shown name matches", (tester) async {
    const settings = RedactionSettings(names: NameRedaction.hide);
    final shown =
        RedactionPolicy(settings).name("Pell", "@pell:lantern.example");
    await pump(tester,
        tabs: true,
        redaction: settings,
        room: _Room(members: [_FindMember("@pell:lantern.example", "Pell")]));
    const row = ValueKey("member-panel-find-result-@pell:lantern.example");
    for (final query in ["Pell", "@pell:lantern.example", "lantern"]) {
      await search(tester, query);
      expect(find.byKey(row), findsNothing, reason: query);
      expect(find.text("0 of 4,812 · name or ID"), findsOneWidget);
    }
    await search(tester, shown);
    expect(find.byKey(row), findsOneWidget);
    expect(find.text("1 of 4,812 · name or ID"), findsOneWidget);
    expect(
        find.byKey(const ValueKey("member-panel-find-invite")), findsNothing);
  });

  testWidgets("result rows: presence dot, none for banned", (tester) async {
    final room = _Room(
        presence: _Presence(),
        members: [_FindMember("@pell:lantern.example", "Pell")],
        banned: [_FindMember("@nitro:spam.example", "Nitro")],
        canBan: true);
    await pump(tester, tabs: true, room: room);
    await search(tester, "e");
    expect(
        find.byKey(
            const ValueKey("member-panel-find-presence-@pell:lantern.example")),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey("member-panel-find-chip-banned")));
    await tester.pump();
    expect(
        find.byKey(
            const ValueKey("member-panel-find-result-@nitro:spam.example")),
        findsOneWidget);
    expect(
        find.byKey(
            const ValueKey("member-panel-find-presence-@nitro:spam.example")),
        findsNothing);
  });
}
