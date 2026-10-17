import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

const name = "Somebody With A Fairly Long Display Name";
const shortTime = "3:30 PM";
const detailedTime = "October 15, 2026 3:30:44 PM";

Widget message(double width, String timestamp) {
  return MaterialApp(
    theme: ThemeDark.theme,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: TimelineEventLayoutMessage(
            senderName: name,
            senderColor: Colors.purple,
            timestamp: timestamp,
            formattedContent: const Text("hello"),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets("the sender name stays on one line beside the timestamp",
      (tester) async {
    await tester.pumpWidget(message(900, shortTime));
    final shortHeight = tester.getSize(find.byType(TimelineEventLayoutMessage));
    final nameMiddle = tester.getCenter(find.text(name)).dy;
    expect(tester.getCenter(find.text(shortTime)).dy, nameMiddle);

    // Hovering switches to the detailed timestamp; the height must not change
    await tester.pumpWidget(message(900, detailedTime));
    expect(
        tester.getSize(find.byType(TimelineEventLayoutMessage)), shortHeight);
    expect(tester.getCenter(find.text(detailedTime)).dy, nameMiddle);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a narrow pane puts the timestamp under the name",
      (tester) async {
    await tester.pumpWidget(message(240, detailedTime));
    final nameRect = tester.getRect(find.text(name));
    final timeRect = tester.getRect(find.text(detailedTime));
    expect(timeRect.top, greaterThanOrEqualTo(nameRect.bottom));

    // The name is a single 15 px line, not one letter per line
    expect(nameRect.height, lessThan(40));
    expect(tester.takeException(), isNull);
  });
}
