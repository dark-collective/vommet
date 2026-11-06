// Vommet: room and space settings can publish to / remove from the server's
// room directory (Vommet issue 479).
import 'dart:async';

import 'package:commet/ui/pages/matrix/room_address_settings/matrix_room_address_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester,
    {bool? published = false,
    bool canChange = true,
    bool publiclyJoinable = true,
    bool isSpace = false,
    Future<bool> Function(bool publish)? onSet}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: MatrixRoomAddressSettingsView(
    const [],
    publishedAliases: const [],
    userHomeserver: "example.org",
    mainAliasChangedStream: const Stream.empty(),
    isAliasAvailable: (_) async => true,
    canChangeMainAlias: canChange,
    canAddLocalAlias: true,
    createAlias: (_) async => null,
    deleteAlias: (_) async => true,
    setMainAlias: (_) async => true,
    publishAlias: (_) async {},
    unpublishAlias: (_) async {},
    publishedToDirectory: published,
    canChangeDirectoryListing: canChange,
    isPubliclyJoinable: publiclyJoinable,
    isSpace: isSpace,
    serverName: "example.org",
    setPublishedToDirectory: onSet ?? (_) async => true,
  )))));
  await tester.pump();
}

bool _switchValue(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch)).value;

void main() {
  testWidgets("the switch publishes and unpublishes", (tester) async {
    final calls = <bool>[];
    await _pump(tester, onSet: (publish) async {
      calls.add(publish);
      return true;
    });
    expect(find.text("Publish to room directory"), findsOneWidget);
    expect(find.text("List this room in Explore rooms on example.org"),
        findsOneWidget);
    expect(_switchValue(tester), isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(_switchValue(tester), isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(_switchValue(tester), isFalse);
    expect(calls, [true, false]);
  });

  testWidgets("spaces say space", (tester) async {
    await _pump(tester, isSpace: true);
    expect(find.text("List this space in Explore rooms on example.org"),
        findsOneWidget);
  });

  testWidgets("without permission the switch is disabled", (tester) async {
    await _pump(tester, canChange: false);
    expect(find.text("You need permission to change this room's addresses"),
        findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets("a refused change flips back and shows the error",
      (tester) async {
    await _pump(tester, onSet: (_) async => false);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(_switchValue(tester), isFalse);
    expect(
        find.text("The server refused to publish this to the room directory"),
        findsOneWidget);
  });

  testWidgets("a listed room people can't join shows a warning",
      (tester) async {
    await _pump(tester, published: true, publiclyJoinable: false);
    expect(find.textContaining("people can see it but can't join"),
        findsOneWidget);

    await _pump(tester, published: true, publiclyJoinable: true);
    expect(
        find.textContaining("people can see it but can't join"), findsNothing);
  });

  testWidgets("unknown directory state hides the switch", (tester) async {
    await _pump(tester, published: null);
    expect(find.text("Publish to room directory"), findsNothing);
  });
}
