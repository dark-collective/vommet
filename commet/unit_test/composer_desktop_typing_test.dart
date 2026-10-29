import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Vommet issues 848, 849, 851: typing in the composer on a computer. The box
// follows the caret, shows the caret, and a deleted selection stays deleted.
void main() {
  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  Future<void> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInput(
            client: FakeClient(),
            availibleEmoticons: const [],
            onSendMessage: (message, {overrideClient}) =>
                MessageInputSendResult.success,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.showKeyboard(find.byType(TextField));
    var value = tester.testTextInput.editingState!['text'] as String;
    for (final c in text.split('')) {
      value += c;
      tester.testTextInput.updateEditingValue(TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  EditableTextState editable(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText));

  testWidgets('the box follows the text being typed (848)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpComposer(tester);
    await type(tester, List.filled(20, 'line\n').join());

    final position = editable(tester).widget.scrollController!.position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, position.maxScrollExtent);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the caret shows while typing (849)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpComposer(tester);
    await type(tester, 'hello');
    final render = editable(tester).renderEditable;
    expect(render.showCursor.value, isTrue);
    // ignore: invalid_use_of_visible_for_testing_member
    expect(editable(tester).cursorCurrentlyVisible, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a deleted selection stays deleted (851)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpComposer(tester);
    await type(tester, 'one two three');
    editable(tester).userUpdateTextEditingValue(
        const TextEditingValue(
            text: 'one two three',
            selection: TextSelection(baseOffset: 7, extentOffset: 13)),
        SelectionChangedCause.drag);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(milliseconds: 100));
    expect(editable(tester).textEditingValue.text, 'one two');
    await type(tester, '!');
    expect(editable(tester).textEditingValue.text, 'one two!');
    debugDefaultTargetPlatformOverride = null;
  });
}
