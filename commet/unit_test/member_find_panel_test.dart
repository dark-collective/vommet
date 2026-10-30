// Vommet: the member list's find row is pinned at the top of the list both
// with the member panel's tabs on (under the tab strip) and off (under the
// "Room members" label), and offers to invite when nobody matches.
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/role.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Permissions extends Permissions {}

class _Client extends Fake implements Client {
  @override
  T? getComponent<T extends Component>() => null;
}

class _Room extends Fake implements Room {
  @override
  final Client client = _Client();
  @override
  final Permissions permissions = _Permissions();
  @override
  List<Member> membersList() => [];
  @override
  List<(Member, Role)> importantMembers() => [];
  @override
  List<Member> membersWithMembership(MemberMembership membership) => [];
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

  Future<List<String?>> pump(WidgetTester tester, {required bool tabs}) async {
    final invites = <String?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoomMemberList(
          _Room(),
          directMessage: false,
          findBox: true,
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
}
