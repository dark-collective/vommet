import 'package:commet/utils/app_focus_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a text field counts as a text field, a button does not',
      (tester) async {
    final fieldFocus = FocusNode();
    final buttonFocus = FocusNode();
    addTearDown(fieldFocus.dispose);
    addTearDown(buttonFocus.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TextField(focusNode: fieldFocus),
          TextButton(
              focusNode: buttonFocus, onPressed: () {}, child: Text("Button")),
        ]),
      ),
    ));

    expect(focusIsOnTextField(fieldFocus), isTrue);
    expect(focusIsOnTextField(buttonFocus), isFalse);
    expect(focusIsOnTextField(null), isFalse);
  });
}
