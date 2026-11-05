// Vommet issues 795, 807: long-press in the "Share to…" picker ticks
// several rooms; a plain tap still picks one.

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
  List<Space> get spaces => const [];
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
  _Room(this.identifier, this.displayName, this.age);
  @override
  final String identifier;
  @override
  final String displayName;
  final int age;
  @override
  final Client client = _Client();
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
  late List<Room>? picked;

  Future<void> open(WidgetTester tester) async {
    clientManager = _ClientManager([
      _Room("!a", "Alpine", 1),
      _Room("!b", "Bakery", 2),
      _Room("!c", "Cinema", 3),
    ]);
    picked = null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
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
          ),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
  }

  testWidgets("a tap picks one room", (tester) async {
    await open(tester);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text("Bakery"));
    await tester.pumpAndSettle();
    expect(picked?.map((r) => r.identifier), ["!b"]);
  });

  testWidgets("long-press ticks; ticks survive a search and sit on top",
      (tester) async {
    await open(tester);
    await tester.longPress(find.text("Cinema"));
    await tester.pump();
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.text("Share to 1 room"), findsOneWidget);
    expect(find.text("Selected · 1"), findsOneWidget);

    // Search, tick the only match with Enter, then clear the search.
    await tester.enterText(find.byType(TextField), "alp");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text("Cinema"), findsNothing);
    await tester.enterText(find.byType(TextField), "");
    await tester.pump();

    expect(find.text("Selected · 2"), findsOneWidget);
    // Each room shows once: ticked ones on top, then the rest.
    expect(find.text("Cinema"), findsOneWidget);
    expect(find.text("Alpine"), findsOneWidget);
    expect(
        tester.getTopLeft(find.text("Alpine")).dy <
            tester.getTopLeft(find.text("Bakery")).dy,
        isTrue);

    // A tap now ticks instead of sharing.
    await tester.tap(find.text("Bakery"));
    await tester.pump();
    expect(picked, isNull);
    await tester.tap(find.text("Share to 3 rooms"));
    await tester.pumpAndSettle();
    expect(picked?.map((r) => r.identifier), ["!c", "!a", "!b"]);
  });
}
