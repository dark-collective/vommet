import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Vommet issue 981: Send while the previous send is processing (as the
// phone media sheet does) goes out once processing ends, not never.
void main() {
  late List<String> sent;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    sent = [];
  });

  Future<void> pumpComposer(WidgetTester tester, bool processing) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(
              client: FakeClient(),
              availibleEmoticons: const [],
              isProcessing: processing,
              onSendMessage: (message, {overrideClient}) {
                sent.add(message);
                return MessageInputSendResult.success;
              },
            ),
          ),
        ),
      ));

  const debounce = Duration(milliseconds: 50);

  testWidgets('Send while processing is sent when processing ends',
      (tester) async {
    await pumpComposer(tester, false);
    await tester.enterText(find.byType(TextField), 'later');
    await pumpComposer(tester, true);
    tester.state<MessageInputState>(find.byType(MessageInput)).sendMessage();
    await tester.pump(debounce);
    expect(sent, isEmpty);

    await pumpComposer(tester, false);
    await tester.pump(debounce);
    expect(sent, ['later']);
  });
}
