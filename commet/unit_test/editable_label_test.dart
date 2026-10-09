// Vommet: a long room or space name in the appearance settings wrapped off
// the screen on phones and pushed the edit button out of reach.

import 'package:commet/ui/molecules/editable_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

void main() {
  const name = "Dominos Discount Deals And Other Very Long Space Names "
      "That Keep Going Well Past The Edge Of A Phone Screen";

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: EditableLabel(
                initialText: name, type: tiamat.TextType.largeTitle),
          ),
        ),
      ),
    ));
  }

  void expectEditButtonInside(WidgetTester tester, IconData icon) {
    final box = tester.getRect(find.byType(EditableLabel));
    final button = tester.getRect(find.byIcon(icon));
    expect(button.right, lessThanOrEqualTo(box.right + 0.5),
        reason: "the button stays inside the label's width");
  }

  testWidgets("long name wraps and keeps the edit button reachable",
      (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull, reason: "no overflow");
    expectEditButtonInside(tester, Icons.edit);

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: "no overflow while editing");
    expectEditButtonInside(tester, Icons.check);
  });
}
