import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/client/components/space_component.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/rail_menu.dart';
import 'package:commet/ui/molecules/space_group_widget.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 478: a space icon in the sidebar opens the space header's
// menu (right-click, or a long-press let go in place on touch). Inside a
// folder that menu also has "Remove from folder", instead of a separate
// folder-only menu.

class _Client implements Client {
  @override
  String get identifier => "client";
  @override
  Profile? get self => null;
  @override
  T? getComponent<T extends Component>() => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Permissions implements Permissions {
  @override
  dynamic noSuchMethod(Invocation i) => false;
}

class _Space implements Space {
  _Space(this.identifier);
  @override
  final String identifier;
  @override
  final Client client = _Client();
  @override
  final Permissions permissions = _Permissions();
  @override
  List<Room> get roomsWithChildren => const [];
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
  int get notificationCount => 0;
  @override
  int get highlightedNotificationCount => 0;
  @override
  int get badgeCount => 0;
  @override
  bool get badgeNoisy => false;
  @override
  T? getComponent<T extends SpaceComponent>() => null;
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

  Future<void> pumpOpenFolder(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: railWidth,
            child: Column(children: [
              SpaceGroupWidget(
                spaces: [SpaceSidebarEntry(_Space("a"), order: "0")],
                folderId: "folder",
                width: railWidth,
                initiallyOpen: true,
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // The member sits in the folder's second row, under the folder icon.
  Offset member(WidgetTester tester) =>
      tester.getTopLeft(find.byType(SpaceGroupWidget)) +
      const Offset(railWidth / 2, railWidth * 1.5);

  void expectSpaceMenuInFolder() {
    expect(find.text(SpaceMenu.spaceMenuSettings), findsOneWidget);
    expect(find.text(SpaceMenu.spaceMenuBrowseRooms), findsOneWidget);
    expect(find.text(SpaceMenu.spaceMenuLeave), findsOneWidget);
    expect(find.text(RailMenu.railFolderRemoveMember), findsOneWidget);
  }

  testWidgets("right-clicking a space in a folder opens its space menu",
      (tester) async {
    await pumpOpenFolder(tester);

    await tester.tapAt(member(tester), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expectSpaceMenuInFolder();
  });

  testWidgets("a long-press let go in place opens the same menu",
      (tester) async {
    await pumpOpenFolder(tester);

    await tester.longPressAt(member(tester));
    await tester.pumpAndSettle();

    expectSpaceMenuInFolder();
  });

  test("a long-press that moves is a drag, not a menu", () {
    final press = RailPressTracker()..start();
    press.update(DragUpdateDetails(globalPosition: const Offset(10, 10)));
    press.update(DragUpdateDetails(globalPosition: const Offset(14, 12)));
    expect(press.stayedPut, isTrue);

    press.update(DragUpdateDetails(globalPosition: const Offset(10, 40)));
    expect(press.stayedPut, isFalse);
  });
}
