// Vommet: Room State in the developer settings stays responsive for big
// rooms (a large public room's state froze the app until Android killed it).

import 'dart:convert';

import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/code_block.dart';
import 'package:commet/ui/pages/settings/categories/room/developer/room_developer_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRoom extends Fake implements Room {
  _FakeRoom(this.developerInfo);
  @override
  final String developerInfo;
}

String _bigState(int members) => const JsonEncoder.withIndent("  ").convert({
      "m.room.member": {
        for (var i = 0; i < members; i++)
          "@user$i:example.org": {
            "type": "m.room.member",
            "state_key": "@user$i:example.org",
            "content": {"membership": "join", "displayname": "User $i"},
          }
      }
    });

void main() {
  testWidgets(
      "a big room's state opens unhighlighted, trimmed, with a copy button",
      (tester) async {
    final json = _bigState(5000);
    expect(json.length, greaterThan(150000));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: RoomDeveloperSettingsView(_FakeRoom(json))))));
    await tester.tap(find.text("Room State"));
    await tester.pumpAndSettle();
    // What kept it quick, checked directly instead of a wall clock (a < 3 s
    // stopwatch failed at 3.19 s on a busy CI box): the dump isn't
    // highlighted, and at most the first 150k characters are laid out,
    // however big the state is.
    expect(find.byType(Codeblock), findsNothing);
    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(shown.data, json.substring(0, 150000));
    expect(find.text("Copy full JSON"), findsOneWidget);
    expect(find.textContaining("Large room state"), findsOneWidget);
  });
}
