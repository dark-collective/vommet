// Vommet: the encryption marker must survive long names on a phone-width
// header, and the topic must move to its own line.
import 'package:commet/ui/atoms/room_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Widget _header({required String name, String? topic, double fontScale = 1}) =>
    MaterialApp(
      theme: ThemeDark.theme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(fontScale)),
          child: child!),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 50,
            child: HeaderView(
              text: name,
              topic: topic,
              showBurger: false,
              topicBelow: true,
              marker: const Icon(Icons.no_encryption_outlined,
                  key: ValueKey("marker"), size: 17),
              menu: const SizedBox(width: 72, height: 30),
            ),
          ),
        ),
      ),
    );

void main() {
  const longName = "Bartholomew Featherstonehaugh-Montgomery (he/him) "
      "late-night-art-share-and-critique";
  const longTopic = "Post your works in progress. Be kind, be specific, "
      "credit your references, and use spoilers.";

  testWidgets("marker stays visible after a truncated name", (tester) async {
    await tester.pumpWidget(_header(name: longName));
    expect(tester.takeException(), isNull);
    final header = tester.getRect(find.byType(HeaderView));
    final marker = tester.getRect(find.byKey(const ValueKey("marker")));
    // Fully inside the header, before the 72 px menu and the 8 px gap.
    expect(marker.left, greaterThan(header.left));
    expect(marker.right, lessThanOrEqualTo(header.right - 72 - 8));
    expect(marker.width, greaterThan(0));
  });

  testWidgets("topic goes on its own line below the name", (tester) async {
    await tester.pumpWidget(_header(name: longName, topic: longTopic));
    expect(tester.takeException(), isNull);
    final name = tester.getRect(find.text(longName));
    final topic = tester.getRect(find.text(longTopic));
    expect(topic.top, greaterThanOrEqualTo(name.bottom - 1));
    expect(find.byKey(const ValueKey("marker")), findsOneWidget);
  });

  // Vommet issue 495: at a large font scale two lines don't fit in 50 px;
  // the topic goes after the name on one line instead of being cut in half.
  testWidgets("topic joins the name's line when two lines don't fit",
      (tester) async {
    await tester
        .pumpWidget(_header(name: "Art share", topic: longTopic, fontScale: 2));
    expect(tester.takeException(), isNull);
    final name = tester.getRect(find.text("Art share"));
    final topic = tester.getRect(find.text(longTopic));
    expect(topic.left, greaterThan(name.right));
    expect(find.text("—"), findsOneWidget);
    expect(find.byKey(const ValueKey("marker")), findsOneWidget);
  });
}
