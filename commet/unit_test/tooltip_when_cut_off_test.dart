import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 546: names in the left-panel chat lists show their full text
// in a tooltip on hover, but only when they're cut off.
void main() {
  Future<bool> cutOff(WidgetTester tester, String name,
      {int maxLines = 1}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            child: tiamat.TooltipWhenCutOff(
              text: name,
              child: Text(name,
                  maxLines: maxLines, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    ));
    final object = tester.renderObject(find.byType(tiamat.TooltipWhenCutOff));
    return tiamat.TooltipWhenCutOff.isCutOff(object);
  }

  testWidgets("a name that fits is not cut off", (tester) async {
    expect(await cutOff(tester, "General"), isFalse);
  });

  testWidgets("a long name on one line is cut off", (tester) async {
    expect(
        await cutOff(tester,
            "A very long room name that cannot possibly fit in the list"),
        isTrue);
  });

  testWidgets("two-line names count only when they pass the second line",
      (tester) async {
    expect(await cutOff(tester, "Two words", maxLines: 2), isFalse);
    expect(
        await cutOff(
            tester,
            "A very long room name that cannot possibly fit even on two "
            "lines of the room list, however it wraps",
            maxLines: 2),
        isTrue);
  });
}
