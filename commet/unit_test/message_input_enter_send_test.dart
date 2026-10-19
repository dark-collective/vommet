import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Vommet issue 333: Enter sends once per key press, not once per key event
// seen while Enter is held.
void main() {
  late List<String> sent;

  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    sent = [];
  });

  Future<void> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInput(
            client: FakeClient(),
            availibleEmoticons: const [],
            onSendMessage: (message, {overrideClient}) {
              sent.add(message);
              return MessageInputSendResult.success;
            },
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  const debounce = Duration(milliseconds: 50);

  testWidgets('keys arriving while Enter is held do not send again',
      (tester) async {
    await pumpComposer(tester);
    final field = find.byType(TextField);

    await tester.enterText(field, 'hi');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(debounce);
    expect(sent, ['hi']);

    // The next message is typed before Enter is released.
    await tester.enterText(field, 'hello');
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pump(debounce);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.pump(debounce);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump(debounce);
    expect(sent, ['hi']);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(debounce);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump(debounce);
    expect(sent, ['hi', 'hello']);
  });
}
