// Vommet issue 322: with the Telegram-style chat list on, revealing a panel
// keeps the focus already inside it (Reply in Thread's cursor in the thread's
// box) and only drops focus left elsewhere.
import 'package:commet/ui/organisms/unified_chat_list/unified_main_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("focusIsWithin tells which panel holds the focus",
      (tester) async {
    final leftKey = GlobalKey();
    final rightKey = GlobalKey();
    final mainBox = FocusNode();
    final threadBox = FocusNode();
    addTearDown(mainBox.dispose);
    addTearDown(threadBox.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Column(children: [
          KeyedSubtree(key: leftKey, child: const Text("chats")),
          TextField(focusNode: mainBox),
          KeyedSubtree(
              key: rightKey,
              child: Column(children: [TextField(focusNode: threadBox)])),
        ]),
      ),
    ));

    threadBox.requestFocus();
    await tester.pump();
    expect(focusIsWithin(rightKey.currentContext), isTrue);
    expect(focusIsWithin(leftKey.currentContext), isFalse);

    mainBox.requestFocus();
    await tester.pump();
    expect(focusIsWithin(rightKey.currentContext), isFalse);
    expect(focusIsWithin(rightKey.currentContext, threadBox), isTrue);

    expect(focusIsWithin(null), isFalse);
  });
}
