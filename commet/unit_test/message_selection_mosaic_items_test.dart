import 'package:commet/client/client.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 786: single pictures of a media mosaic can be ticked.

class _FakeClient implements Client {
  @override
  String get identifier => "client";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  final _client = _FakeClient();

  @override
  Client get client => _client;

  @override
  String get identifier => "!room";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("a mosaic can be ticked in part, and unticked whole", () {
    final selection = MessageSelection(_FakeRoom());
    const group = ["p1", "p2", "p3"];

    selection.start(group);
    expect(selection.isTicked(group), isTrue);

    selection.toggle(["p2"]);
    expect(selection.ticked.ids, unorderedEquals(["p1", "p3"]));
    expect(selection.isTicked(group), isFalse);
    expect(selection.isAnyTicked(group), isTrue);

    // A tap beside the mosaic ticks all of it again.
    selection.toggle(group);
    expect(selection.isTicked(group), isTrue);

    selection.toggle(["p1"]);
    selection.untick(group);
    expect(selection.active, isFalse);
    expect(selection.isAnyTicked(group), isFalse);
    selection.dispose();
  });

  testWidgets("tileAt finds the picture under the pointer", (tester) async {
    final selection = MessageSelection(_FakeRoom());
    selection.start(["a", "b"]);
    final keyA = GlobalKey();
    final keyB = GlobalKey();

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(key: keyA, width: 100, height: 100),
          SizedBox(key: keyB, width: 100, height: 100),
        ]),
      ),
    ));
    selection.tiles[keyA] = (keyA.currentContext!, "a");
    selection.tiles[keyB] = (keyB.currentContext!, "b");

    expect(selection.tileAt(["a", "b"], const Offset(50, 50)), "a");
    expect(selection.tileAt(["a", "b"], const Offset(150, 50)), "b");
    // Beside the mosaic: none, so the whole mosaic toggles.
    expect(selection.tileAt(["a", "b"], const Offset(250, 50)), isNull);
    // Another mosaic's pictures don't count.
    expect(selection.tileAt(["c"], const Offset(50, 50)), isNull);
    selection.dispose();
  });
}
