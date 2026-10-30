// Vommet: the member list's find box (filter, highlight ranges, chips, the
// invite row) and its pinned row with the invite button.
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/molecules/member_find.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Member extends Fake implements Member {
  _Member(this.identifier, this.displayName);

  @override
  final String identifier;
  @override
  final String displayName;
}

void main() {
  final keys = [
    _Member("@pell:lantern.example", "Pell"),
    _Member("@nitro:spam.example", "Nitro Giveaway"),
    _Member("@free:spam.example", "FreeNitro2026"),
    _Member("@juni:lantern.example", "Juni"),
  ].map(MemberFindKey.new).toList();

  List<String> ids(List<MemberFindMatch> matches) =>
      matches.map((m) => m.member.identifier).toList();

  group("memberFindMatches", () {
    test("matches the name", () {
      expect(ids(memberFindMatches("pell", keys)), ["@pell:lantern.example"]);
    });

    test("matches the Matrix ID", () {
      expect(ids(memberFindMatches("@juni", keys)), ["@juni:lantern.example"]);
    });

    test("a server matches everyone on it", () {
      expect(ids(memberFindMatches(":spam.example", keys)), [
        "@nitro:spam.example",
        "@free:spam.example",
      ]);
      expect(memberFindMatches("spam", keys), hasLength(2));
    });

    test("ignores case", () {
      expect(ids(memberFindMatches("NITRO", keys)), [
        "@nitro:spam.example",
        "@free:spam.example",
      ]);
    });

    test("empty query matches nothing", () {
      expect(memberFindMatches("  ", keys), isEmpty);
    });

    test("highlight ranges in the name and the ID", () {
      final match = memberFindMatches("Nitro", keys).last;
      expect(match.member.displayName, "FreeNitro2026");
      expect(match.nameRange, const TextRange(start: 4, end: 9));
      expect(match.idRange, isNull);
      final first = memberFindMatches("nitro", keys).first;
      expect(first.nameRange, const TextRange(start: 0, end: 5));
      expect(first.idRange, const TextRange(start: 1, end: 6));
    });
  });

  test("Banned and Left chips only with the ban permission", () {
    expect(memberFindChips(canBan: false), [
      MemberMembership.joined,
      MemberMembership.invited,
    ]);
    expect(memberFindChips(canBan: true), MemberMembership.values);
  });

  test("invite row only with no Joined match and the invite permission", () {
    expect(
      memberFindOffersInvite(query: "bob", joinedMatches: 0, canInvite: true),
      isTrue,
    );
    expect(
      memberFindOffersInvite(query: "bob", joinedMatches: 1, canInvite: true),
      isFalse,
    );
    expect(
      memberFindOffersInvite(query: "bob", joinedMatches: 0, canInvite: false),
      isFalse,
    );
    expect(memberFindIsUserId("@bob:lantern.example"), isTrue);
    expect(memberFindIsUserId("bob"), isFalse);
  });

  test("labels", () {
    expect(
      MemberFindStrings.memberFindIn(MemberFindStrings.formatCount(4812)),
      "Find in 4,812 members",
    );
    expect(
      MemberFindStrings.memberFindCount("2", "4,812"),
      "2 of 4,812 · name or ID",
    );
    expect(MemberFindStrings.memberFindInviteName("bob"), 'Invite "bob"…');
  });

  group("MemberFindRow", () {
    Future<TextEditingController> pump(
      WidgetTester tester, {
      VoidCallback? onInvite,
    }) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 44)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: MemberFindHeaderDelegate(
                    MemberFindRow(
                      controller: controller,
                      focusNode: focus,
                      memberCount: 4812,
                      onInvite: onInvite,
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const SizedBox(height: 50),
                    childCount: 100,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets("invite button only with the invite permission", (
      tester,
    ) async {
      var invited = 0;
      await pump(tester, onInvite: () => invited++);
      expect(find.byKey(const ValueKey("member-panel-find")), findsOneWidget);
      expect(find.text("Find in 4,812 members"), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey("member-panel-invite-button")),
      );
      expect(invited, 1);
      expect(
        find.byKey(const ValueKey("member-panel-invite-card")),
        findsNothing,
      );

      await pump(tester);
      expect(
        find.byKey(const ValueKey("member-panel-invite-button")),
        findsNothing,
      );
    });

    testWidgets("stays pinned while the list scrolls", (tester) async {
      await pump(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();
      expect(find.byKey(const ValueKey("member-panel-find")), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey("member-panel-find"))).dy,
        lessThan(MemberFindRow.height),
      );
    });

    testWidgets("the ✕ button clears the box", (tester) async {
      final controller = await pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey("member-panel-find")),
        "spam",
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("member-panel-find-clear")));
      await tester.pump();
      expect(controller.text, isEmpty);
    });
  });
}
