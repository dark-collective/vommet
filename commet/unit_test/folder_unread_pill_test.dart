import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rail_pill.dart';
import 'package:commet/ui/molecules/space_group_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet: a closed sidebar folder shows the rail's unread pill when anything
// inside it is unread. The pill must land on the rail, not left of it where
// the sidebar's scroll view clips it away (tester report 10-13).

class _Client implements Client {
  @override
  String get identifier => "client";
  @override
  Profile? get self => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Room implements Room {
  _Room(this.notificationCount);
  @override
  int notificationCount;
  @override
  int get highlightedNotificationCount => 0;
  @override
  PushRule get pushRule => PushRule.notify;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Space implements Space {
  _Space(this.identifier, this.roomsWithChildren);
  @override
  final String identifier;
  @override
  final List<Room> roomsWithChildren;
  @override
  final Client client = _Client();
  @override
  String get localId => "client:$identifier";
  @override
  String get displayName => identifier;
  @override
  Color get color => Colors.blue;
  @override
  ImageProvider? get avatar => null;
  @override
  PushRule get pushRule => PushRule.notify;
  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  int get notificationCount =>
      roomsWithChildren.fold(0, (sum, room) => sum + room.notificationCount);
  @override
  int get highlightedNotificationCount => 0;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  const railWidth = 70.0;

  Future<void> pumpFolder(WidgetTester tester, List<Space> spaces,
      {bool open = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          // Like the sidebar: the rail is 70 px wide and clips what's
          // outside it.
          child: SizedBox(
            width: railWidth,
            child: ClipRect(
              child: Column(children: [
                SpaceGroupWidget(
                  spaces: [
                    for (var i = 0; i < spaces.length; i++)
                      SpaceSidebarEntry(spaces[i], order: "$i"),
                  ],
                  folderId: "folder",
                  width: railWidth,
                  initiallyOpen: open,
                ),
              ]),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder folderPill() => find.descendant(
      of: find.byType(RailSlot).first,
      matching: find.byWidgetPredicate((w) =>
          w is AnimatedContainer && w.constraints?.maxWidth == RailSlot.width));

  testWidgets("a closed folder with an unread space shows the pill on the rail",
      (tester) async {
    await pumpFolder(tester, [
      _Space("a", [_Room(0)]),
      _Space("b", [_Room(3)]),
    ]);

    final pill = tester.getRect(folderPill());
    expect(pill.height, 8);
    // On the rail's left edge, inside the clip, like a space's pill.
    expect(pill.left, 0);
    expect(pill.right, RailSlot.width);
  });

  testWidgets("a closed folder with nothing unread shows no pill",
      (tester) async {
    await pumpFolder(tester, [
      _Space("a", [_Room(0)]),
      _Space("b", [_Room(0)]),
    ]);

    expect(tester.getRect(folderPill()).height, 0);
  });

  testWidgets("an open folder leaves the pills to its spaces", (tester) async {
    await pumpFolder(
        tester,
        [
          _Space("a", [_Room(0)]),
          _Space("b", [_Room(3)]),
        ],
        open: true);

    // One RailSlot per space, none around the folder itself.
    expect(find.byType(RailSlot), findsNWidgets(2));
  });

  // Why the pill never showed: the folder spans the rail from its left
  // edge, so RailSlot's old inset (SpaceSelector.padding.left) drew the pill
  // left of the rail, where the clip removed it.
  testWidgets("the old 7 px inset put a full-width child's pill off the rail",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: railWidth,
            child: const RailSlot(
              unread: true,
              inset: 7,
              child: SizedBox(width: railWidth, height: railWidth),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final pill = tester.getRect(folderPill());
    expect(pill.height, 8);
    expect(pill.right, lessThanOrEqualTo(0));
  });
}
