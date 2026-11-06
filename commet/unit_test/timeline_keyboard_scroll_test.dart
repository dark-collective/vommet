import 'package:commet/ui/molecules/room_timeline_widget/timeline_keyboard_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 481: Page Up/Down, Home/End scroll the timeline.
void main() {
  late ScrollController scroll;
  late TextEditingController text;
  late FocusNode textFocus;
  var jumpedToLatest = 0;

  Future<void> pump(WidgetTester tester, {bool withJumpToLatest = false}) {
    scroll = ScrollController();
    text = TextEditingController();
    textFocus = FocusNode();
    jumpedToLatest = 0;
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TimelineKeyboardScroll(
          child: Builder(builder: (context) {
            TimelineKeyboardScroll.maybeOf(context)?.attach(
                () => scroll, withJumpToLatest ? () => jumpedToLatest++ : null);
            return Column(children: [
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  reverse: true,
                  itemCount: 200,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 50, child: Text("message $i")),
                ),
              ),
              TextField(controller: text, focusNode: textFocus),
            ]);
          }),
        ),
      ),
    ));
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets("Page Up and Page Down scroll from the message box",
      (tester) async {
    await pump(tester);
    textFocus.requestFocus();
    await tester.pump();

    final page = scroll.position.viewportDimension * 0.9;

    await press(tester, LogicalKeyboardKey.pageUp);
    expect(scroll.offset, closeTo(page, 0.01));

    await press(tester, LogicalKeyboardKey.pageUp);
    expect(scroll.offset, closeTo(page * 2, 0.01));

    await press(tester, LogicalKeyboardKey.pageDown);
    expect(scroll.offset, closeTo(page, 0.01));

    await press(tester, LogicalKeyboardKey.pageDown);
    await press(tester, LogicalKeyboardKey.pageDown);
    expect(scroll.offset, scroll.position.minScrollExtent);
  });

  testWidgets("Page Up scrolls even when the message box has text",
      (tester) async {
    await pump(tester);
    textFocus.requestFocus();
    await tester.enterText(find.byType(TextField), "hello");
    await tester.pump();

    await press(tester, LogicalKeyboardKey.pageUp);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets("Home and End jump when the message box is empty",
      (tester) async {
    await pump(tester);
    textFocus.requestFocus();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.home);
    expect(scroll.offset, scroll.position.maxScrollExtent);

    await press(tester, LogicalKeyboardKey.end);
    expect(scroll.offset, scroll.position.minScrollExtent);
  });

  testWidgets("End uses the timeline's jump to latest when it has one",
      (tester) async {
    await pump(tester, withJumpToLatest: true);
    textFocus.requestFocus();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.end);
    expect(jumpedToLatest, 1);
  });

  testWidgets("Home and End move the text cursor when the box has text",
      (tester) async {
    await pump(tester);
    textFocus.requestFocus();
    await tester.enterText(find.byType(TextField), "hello");
    await tester.pump();

    await press(tester, LogicalKeyboardKey.home);
    expect(scroll.offset, 0);
    expect(text.selection.baseOffset, 0);

    await press(tester, LogicalKeyboardKey.end);
    expect(text.selection.baseOffset, 5);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets("keys with modifiers are left alone", (tester) async {
    await pump(tester);
    textFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await press(tester, LogicalKeyboardKey.pageUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(scroll.offset, 0);
  });
}
