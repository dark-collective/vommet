import 'dart:typed_data';

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/space_icon.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 308: screen readers read every sidebar icon as just "Button".
// Spaces, DMs and pinned rooms are pictures, the Home, Rooms, Add Space and
// Explore buttons are icons, and the red badges drew "9+" for any count.

// A 1x1 transparent PNG, so the icon shows a picture and no initial letter.
final _avatar = MemoryImage(Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]));

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(
          body: Center(child: SizedBox(width: 70, height: 70, child: child))),
    );

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets("a space with a picture is read by its name, as a button",
      (tester) async {
    final handle = tester.ensureSemantics();
    var tapped = 0;
    await tester.pumpWidget(_app(SpaceIcon(
      spaceId: "!garden:example.org",
      clientId: "client",
      displayName: "Gardening",
      avatar: _avatar,
      onTap: () => tapped++,
    )));

    expect(tester.getSemantics(find.bySemanticsLabel("Gardening")),
        isSemantics(label: "Gardening", isButton: true, hasTapAction: true));

    await tester.tap(find.bySemanticsLabel("Gardening"));
    expect(tapped, 1);
    handle.dispose();
  });

  testWidgets("a space without a picture says its name, not its initial",
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(SpaceIcon(
      spaceId: "!garden:example.org",
      clientId: "client",
      displayName: "Gardening",
      placeholderColor: Colors.green,
      onTap: () {},
    )));

    expect(find.bySemanticsLabel("Gardening"), findsOneWidget);
    expect(find.bySemanticsLabel("G"), findsNothing);
    handle.dispose();
  });

  testWidgets("a DM's or pinned room's picture button says the room's name",
      (tester) async {
    // DMs on the rail are SpaceIcons; pinned rooms use the same ImageButton.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(tiamat.ImageButton(
      size: 70,
      image: _avatar,
      placeholderText: "Alice",
      onTap: () {},
    )));

    expect(tester.getSemantics(find.bySemanticsLabel("Alice")),
        isSemantics(label: "Alice", isButton: true, hasTapAction: true));
    handle.dispose();
  });

  testWidgets("an explicit label wins over the placeholder text",
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(tiamat.ImageButton(
      size: 70,
      icon: Icons.settings,
      semanticsLabel: "Settings",
      onTap: () {},
    )));

    expect(find.bySemanticsLabel("Settings"), findsOneWidget);
    handle.dispose();
  });

  testWidgets("a picture that can't be tapped isn't announced as a button",
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(tiamat.ImageButton(
      size: 70,
      image: _avatar,
      placeholderText: "Alice",
    )));

    expect(tester.getSemantics(find.bySemanticsLabel("Alice")),
        isSemantics(label: "Alice", isButton: false, isImage: true));
    handle.dispose();
  });

  testWidgets("the badge says the real count, not 9+", (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const NotificationBadge(12)));

    expect(find.bySemanticsLabel("12 unread notifications"), findsOneWidget);
    expect(find.bySemanticsLabel("9+"), findsNothing);

    await tester.pumpWidget(_app(const NotificationBadge(1)));
    expect(find.bySemanticsLabel("1 unread notification"), findsOneWidget);
    handle.dispose();
  });

  testWidgets("a space's mention badge is read with the space", (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(SpaceIcon(
      spaceId: "!garden:example.org",
      clientId: "client",
      displayName: "Gardening",
      avatar: _avatar,
      highlightedNotificationCount: 3,
      onTap: () {},
    )));

    expect(find.bySemanticsLabel("Gardening"), findsOneWidget);
    expect(find.bySemanticsLabel("3 unread notifications"), findsOneWidget);
    handle.dispose();
  });

  for (final layout in ["mobile", "desktop"]) {
    testWidgets("Home and its badge read as one labelled button ($layout)",
        (tester) async {
      await preferences.layoutOverride.set(layout);
      final handle = tester.ensureSemantics();
      var tapped = 0;
      await tester.pumpWidget(_app(Builder(
          builder: (context) => SideNavigationBar.tooltip(
              "Home",
              Stack(children: [
                tiamat.ImageButton(
                    size: 70, icon: Icons.home, onTap: () => tapped++),
                const Align(
                    alignment: Alignment.topRight, child: NotificationBadge(4)),
              ]),
              context))));

      final home = find.bySemanticsLabel(RegExp(r"^Home\b"));
      expect(home, findsOneWidget);
      final node = tester.getSemantics(home);
      expect(node.label, contains("4 unread notifications"));
      expect(node, isSemantics(isButton: true, hasTapAction: true));

      await tester.tap(home);
      expect(tapped, 1);
      handle.dispose();
    });

    testWidgets("Add Space without a badge is labelled ($layout)",
        (tester) async {
      await preferences.layoutOverride.set(layout);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(Builder(
          builder: (context) => SideNavigationBar.tooltip(
              "Add Space",
              tiamat.ImageButton(size: 70, icon: Icons.add, onTap: () {}),
              context))));

      expect(tester.getSemantics(find.bySemanticsLabel("Add Space")),
          isSemantics(label: "Add Space", isButton: true, hasTapAction: true));
      handle.dispose();
    });
  }
}
