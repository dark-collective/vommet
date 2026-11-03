import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issues 1074 and 1072: Ctrl+F / Cmd+F opens the open chat's
// search; Esc that nothing focused took shuts it, keeping the query.

class _Client implements Client {
  @override
  String get identifier => 'client';

  // No search component: the room can't be searched.
  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  _Room(this.identifier);

  @override
  final String identifier;

  @override
  final Client client = _Client();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(InChatSearch.reset);

  /// The main page's two key paths, around a focused non-text widget.
  Future<List<bool>> pumpKeys(WidgetTester tester, Room? room) async {
    final opened = <bool>[];
    bool onKey(KeyEvent event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyF) {
        opened.add(InChatSearch.isOpenShortcut(event));
      }
      return InChatSearch.handleOpenKey(event, room);
    }

    KeyEventResult onUnhandled(KeyEvent event) =>
        InChatSearch.handleUnhandledEscape(event, room)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

    ServicesBinding.instance.keyboard.addHandler(onKey);
    FocusManager.instance.addLateKeyEventHandler(onUnhandled);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(onKey);
      FocusManager.instance.removeLateKeyEventHandler(onUnhandled);
    });
    await tester.pumpWidget(
      const MaterialApp(home: Focus(autofocus: true, child: SizedBox.expand())),
    );
    await tester.pump();
    return opened;
  }

  testWidgets('Ctrl+F and Cmd+F are the shortcut, Ctrl+Shift+F is not', (
    tester,
  ) async {
    final opened = await pumpKeys(tester, null);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);

    expect(opened, [true, false, true, false]);
  });

  testWidgets('Ctrl+F leaves a room that cannot be searched alone', (
    tester,
  ) async {
    final room = _Room('!a');
    await pumpKeys(tester, room);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(InChatSearch.existing(room), isNull);
  });

  testWidgets('Esc shuts the open search without the field focused', (
    tester,
  ) async {
    final room = _Room('!b');
    await pumpKeys(tester, room);
    final search = InChatSearch.of(room)..open();
    search.text.text = 'moss';
    await tester.pump();
    expect(search.focus.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(search.isOpen, isFalse);
    // Kept, as with the close button: reopening shows the old results.
    expect(search.text.text, 'moss');
  });

  testWidgets('Esc does nothing to a search that is not open', (tester) async {
    final room = _Room('!c');
    await pumpKeys(tester, room);
    final search = InChatSearch.of(room);
    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(handled, isFalse);
    expect(search.isOpen, isFalse);
  });
}
