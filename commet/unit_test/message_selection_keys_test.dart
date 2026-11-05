import 'package:commet/ui/organisms/message_selection/message_selection_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

SelectionKeyAction? _press(LogicalKeyboardKey key,
        {bool ctrl = false, bool typing = false, bool textSelected = false}) =>
    selectionKeyAction(key,
        ctrlOrMeta: ctrl, typing: typing, textSelected: textSelected);

void main() {
  test("Esc stops selecting", () {
    expect(_press(LogicalKeyboardKey.escape), SelectionKeyAction.exit);
    expect(_press(LogicalKeyboardKey.escape, typing: true),
        SelectionKeyAction.exit);
  });

  test("Ctrl+C copies unless a text field has text selected", () {
    expect(
        _press(LogicalKeyboardKey.keyC, ctrl: true), SelectionKeyAction.copy);
    expect(_press(LogicalKeyboardKey.keyC, ctrl: true, typing: true),
        SelectionKeyAction.copy);
    expect(
        _press(LogicalKeyboardKey.keyC,
            ctrl: true, typing: true, textSelected: true),
        isNull);
    expect(_press(LogicalKeyboardKey.keyC), isNull);
  });

  test("Delete asks to delete unless typing", () {
    expect(_press(LogicalKeyboardKey.delete), SelectionKeyAction.delete);
    expect(_press(LogicalKeyboardKey.delete, typing: true), isNull);
    expect(_press(LogicalKeyboardKey.delete, ctrl: true), isNull);
    expect(_press(LogicalKeyboardKey.backspace), isNull);
  });
}
