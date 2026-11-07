// Vommet issue 889: the "Share to…" picker gets the "Forward to…" filter
// chips. All keeps the issue 794 order; a space chip lists its rooms
// newest first, and the picker remembers the filter.

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/space.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/share_target/share_target_dialog.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/share_intake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ClientManager implements ClientManager {
  _ClientManager(List<Room> rooms) : rooms = NotifyingList<Room>.from(rooms);
  @override
  final NotifyingList<Room> rooms;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Client implements Client {
  @override
  String get identifier => "client";
  @override
  T? getComponent<T extends Component>() => null;
  @override
  List<Space> spaces = [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Space implements Space {
  _Space(this.identifier, this.displayName, this.rooms,
      {this.subspaces = const [], this.isTopLevel = true});
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  final List<Room> rooms;
  @override
  final List<Space> subspaces;
  @override
  final bool isTopLevel;
  @override
  List<Room> get roomsWithChildren =>
      [...rooms, for (final s in subspaces) ...s.roomsWithChildren];
  @override
  ImageProvider? get avatar => null;
  @override
  Color get color => Colors.indigo;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Permissions implements Permissions {
  @override
  bool get canSendMessage => true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Room implements Room {
  _Room(this.client, this.identifier, this.displayName, this.age);
  @override
  final Client client;
  @override
  final String identifier;
  @override
  final String displayName;
  final int age;
  @override
  Permissions get permissions => _Permissions();
  @override
  DateTime get lastEventTimestamp =>
      DateTime(2026).subtract(Duration(minutes: age));
  @override
  ImageProvider? get avatar => null;
  @override
  bool get isFavorite => false;
  @override
  Color get defaultColor => Colors.teal;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  final client = _Client();
  // Bakery is the most recent; Alpine and Cinema sit in the space, Cinema
  // in its subspace.
  final alpine = _Room(client, "!a", "Alpine", 5);
  final bakery = _Room(client, "!b", "Bakery", 1);
  final cinema = _Room(client, "!c", "Cinema", 3);
  final lounge = _Space("!lounge", "Movie Lounge", [cinema], isTopLevel: false);
  client.spaces = [
    _Space("!club", "Lantern Club", [alpine], subspaces: [lounge]),
    lounge,
  ];

  late List<Room>? picked;

  Future<void> open(WidgetTester tester) async {
    clientManager = _ClientManager([alpine, bakery, cinema]);
    picked = null;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<List<Room>>(
                    MaterialPageRoute(
                        builder: (_) => Scaffold(
                            body: ShareTargetDialog(
                                payload: SharePayload(
                                    files: const [], text: "hi")))));
              },
              child: const Text("open"),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
  }

  double top(String text) => find.text(text).evaluate().isEmpty
      ? -1
      : (find.text(text).evaluate().first.renderObject as RenderBox)
          .localToGlobal(Offset.zero)
          .dy;

  testWidgets("space chip filters newest first; the filter is remembered",
      (tester) async {
    await open(tester);
    // All: every room, most recent first (issue 794 order), no DMs chip.
    expect(find.widgetWithText(ChoiceChip, "All"), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, "Direct messages"), findsNothing);
    expect(top("Bakery") < top("Cinema"), isTrue);
    expect(top("Cinema") < top("Alpine"), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, "Lantern Club"));
    await tester.pumpAndSettle();
    expect(find.text("Bakery"), findsNothing);
    // The subspace row, then the space's rooms newest first.
    expect(find.text("Movie Lounge"), findsOneWidget);
    expect(top("Cinema") < top("Alpine"), isTrue);

    await tester.tap(find.text("Movie Lounge"));
    await tester.pumpAndSettle();
    expect(find.text("Alpine"), findsNothing);
    expect(find.text("Cinema"), findsOneWidget);

    await tester.tap(find.text("Cinema"));
    await tester.pumpAndSettle();
    expect(picked?.map((r) => r.identifier), ["!c"]);

    // Reopened: still inside Lantern Club › Movie Lounge.
    await open(tester);
    expect(find.text("Alpine"), findsNothing);
    expect(find.text("Bakery"), findsNothing);
    expect(find.text("Cinema"), findsOneWidget);

    // The breadcrumb goes back up; All shows everything again.
    await tester.tap(find.widgetWithText(TextButton, "Lantern Club"));
    await tester.pumpAndSettle();
    expect(find.text("Alpine"), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, "All"));
    await tester.pumpAndSettle();
    expect(find.text("Bakery"), findsOneWidget);
  });
}
