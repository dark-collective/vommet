import 'dart:convert';

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/ui/pages/room_info/room_info_page.dart';
import 'package:commet/ui/pages/room_info/room_info_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet (New room info page): the experiment is on by default, and off
// brings back the old Room settings page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> load(Map<String, Object> stored) async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    await preferences.init();
  }

  test("on by default: phones get the page, computers the dialog", () async {
    await load({});
    expect(roomInfoPageEnabled, isTrue);
    expect(roomInfoRoute(experiment: roomInfoPageEnabled, desktop: false),
        RoomInfoRoute.page);
    expect(roomInfoRoute(experiment: roomInfoPageEnabled, desktop: true),
        RoomInfoRoute.dialog);
  });

  test("switched off: the old Room settings page, on every layout", () async {
    await load({"vommet_experiment_room_info_page": false});
    expect(roomInfoPageEnabled, isFalse);
    for (final desktop in [false, true]) {
      expect(roomInfoRoute(experiment: roomInfoPageEnabled, desktop: desktop),
          RoomInfoRoute.oldSettings);
    }
  });

  testWidgets("a locked row shows a lock and still opens", (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InfoGroup([
          InfoRow(
              icon: Icons.shield_outlined,
              title: "Privacy & access",
              value: "Invite only",
              locked: true,
              onTap: () => opened++),
        ]),
      ),
    ));
    expect(find.text("Invite only"), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await tester.tap(find.text("Privacy & access"));
    expect(opened, 1);
  });

  testWidgets("the header banner opens in the image viewer", (tester) async {
    await load({});
    // A 1×1 transparent PNG.
    final banner = MemoryImage(base64Decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InfoHeaderArt(
            banner: banner,
            image: null,
            placeholderText: "Lounge",
            placeholderColor: Colors.teal),
      ),
    ));
    // No picture: nothing to open on the placeholder.
    expect(find.byKey(const ValueKey("info-header-avatar")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("info-header-banner")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Lightbox), findsOneWidget);
  });
}
