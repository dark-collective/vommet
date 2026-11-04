// Vommet network marks: the mark after the sender name on messages.
import 'package:commet/ui/atoms/bridged_user_marker.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:commet/utils/bridged_user_rules.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

const longName = "Wren Featherstonehaugh-Montgomery of the Very Long Names "
    "(@telegram_5550124:spoof.example)";

Widget message(Widget mark, {double width = 900, String name = "Wren"}) =>
    MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: TimelineEventLayoutMessage(
              senderName: name,
              senderId: "@telegram_5550124:spoof.example",
              senderColor: Colors.purple,
              timestamp: "3:30 PM",
              nameTrailing: mark,
              formattedContent: const Text("hello"),
            ),
          ),
        ),
      ),
    );

void main() {
  final marks = <String, Widget>{
    "solid": const BridgeNetworkIcon(BridgeNetwork.telegram),
    "dashed": const UnverifiedNetworkIcon(BridgeNetwork.telegram),
    "matrix": const MatrixMark(),
  };

  for (final entry in marks.entries) {
    testWidgets("${entry.key} mark follows the sender name", (tester) async {
      await tester.pumpWidget(message(entry.value));
      final mark = find.byWidget(entry.value);
      expect(mark, findsOneWidget);
      expect(tester.getTopLeft(mark).dx,
          greaterThanOrEqualTo(tester.getTopRight(find.text("Wren")).dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets("${entry.key} mark stays visible after a long name",
        (tester) async {
      await tester.pumpWidget(message(entry.value, width: 360, name: longName));
      final mark = find.byWidget(entry.value);
      expect(mark, findsOneWidget);
      final rect = tester.getRect(mark);
      expect(rect.width, greaterThan(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("no mark while names are redacted", (tester) async {
    const mark = MatrixMark();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RedactionScope(
          policy: RedactionPolicy(const RedactionSettings(
              names: NameRedaction.hide, avatars: true, distinguishable: true)),
          child: const TimelineEventLayoutMessage(
            senderName: "Wren",
            senderColor: Colors.purple,
            nameTrailing: mark,
          ),
        ),
      ),
    ));
    expect(find.byWidget(mark), findsNothing);
  });
}
