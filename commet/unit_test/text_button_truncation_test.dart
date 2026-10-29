import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Sidebar room names stay on one line; a name cut off with "…" shows in full
// on hover, a name that fits shows no tooltip.
void main() {
  Widget harness(String name) => MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 37,
              child: tiamat.TextButton(name,
                  icon: Icons.tag, tooltipWhenTruncated: true, onTap: () {}),
            ),
          ),
        ),
      );

  Future<int> hoverAndCount(WidgetTester tester, String name) async {
    await tester.pumpWidget(harness(name));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(tiamat.TextButton)));
    await tester.pumpAndSettle();
    // The label itself, plus a second copy if the tooltip opened.
    return find.text(name).evaluate().length;
  }

  testWidgets('a cut-off name shows in full on hover', (tester) async {
    expect(
        await hoverAndCount(
            tester, "Rules and Official Community Announcements Archive"),
        2);
  });

  testWidgets('a name that fits shows no tooltip', (tester) async {
    expect(await hoverAndCount(tester, "Lobby"), 1);
  });
}
