// Vommet: during a call on a phone, the call view gives way to a slim bar
// while the keyboard is open, so the chat stays visible.

import 'package:commet/ui/molecules/compact_call_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("KeyboardOpenBuilder follows the keyboard below a Scaffold",
      (tester) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KeyboardOpenBuilder(
            builder: (context, open) => Text(open ? "open" : "closed")),
      ),
    ));
    expect(find.text("closed"), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await tester.pumpAndSettle();
    expect(find.text("open"), findsOneWidget);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.text("closed"), findsOneWidget);
  });
}
