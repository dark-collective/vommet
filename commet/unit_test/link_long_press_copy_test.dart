import 'package:commet/ui/atoms/rich_text/spans/link.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 690: a touch long-press on a link copies its target; a
// long-press elsewhere on the message still reaches the message.

const _fontSize = 20.0;
const _style = TextStyle(fontSize: _fontSize, height: 1);

/// A message row: [link] then plain text, inside an InkWell whose long-press
/// stands in for the message's own (select / open the menu).
Widget _message(InlineSpan Function(BuildContext) link,
    {required VoidCallback onMessageLongPress}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: InkWell(
          onLongPress: onMessageLongPress,
          child: Builder(
            builder: (context) => Text.rich(
              TextSpan(style: _style, children: [
                link(context),
                const TextSpan(text: " and some more text"),
              ]),
              key: const Key("message"),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A point on the first character (the link) or the last (plain text).
Offset _onLink(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const Key("message"))) +
    const Offset(_fontSize / 2, _fontSize / 2);

Offset _offLink(WidgetTester tester) =>
    tester.getTopRight(find.byKey(const Key("message"))) +
    const Offset(-_fontSize / 2, _fontSize / 2);

void main() {
  late List<String> copied;

  setUp(() {
    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == "Clipboard.setData") {
        copied.add((call.arguments as Map)["text"] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  InlineSpan linkSpan(BuildContext context) => LinkSpan.create("link",
      context: context,
      clientId: "client",
      destination: Uri.parse("https://example.com/target?x=1"));

  testWidgets("long-press on a link copies its target, not the message's",
      (tester) async {
    var messageLongPresses = 0;
    await tester.pumpWidget(
        _message(linkSpan, onMessageLongPress: () => messageLongPresses++));

    await tester.longPressAt(_onLink(tester));
    await tester.pumpAndSettle();

    expect(copied, ["https://example.com/target?x=1"]);
    expect(messageLongPresses, 0);
  });

  testWidgets("long-press off the link still reaches the message",
      (tester) async {
    var messageLongPresses = 0;
    await tester.pumpWidget(
        _message(linkSpan, onMessageLongPress: () => messageLongPresses++));

    await tester.longPressAt(_offLink(tester));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    expect(messageLongPresses, 1);
  });

  testWidgets("mouse long-press on a link is unchanged", (tester) async {
    var messageLongPresses = 0;
    await tester.pumpWidget(
        _message(linkSpan, onMessageLongPress: () => messageLongPresses++));

    await tester.longPressAt(_onLink(tester), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    expect(messageLongPresses, 1);
  });

  testWidgets("tap on a link still opens it, long-press doesn't",
      (tester) async {
    var taps = 0;
    var longPresses = 0;
    var messageLongPresses = 0;
    await tester.pumpWidget(_message(
        (_) => TextSpan(
            text: "link",
            recognizer: LinkGestureRecognizer()
              ..onTap = (() => taps++)
              ..onLongPress = (() => longPresses++)),
        onMessageLongPress: () => messageLongPresses++));

    await tester.tapAt(_onLink(tester));
    await tester.pumpAndSettle();
    expect((taps, longPresses, messageLongPresses), (1, 0, 0));

    await tester.longPressAt(_onLink(tester));
    await tester.pumpAndSettle();
    expect((taps, longPresses, messageLongPresses), (1, 1, 0));
  });
}
