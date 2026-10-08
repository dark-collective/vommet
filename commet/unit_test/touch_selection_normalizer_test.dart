import 'package:commet/ui/atoms/touch_selection_normalizer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _text = "alpha beta gamma delta";

Future<TextEditingController> _pump(WidgetTester tester,
    {required bool normalize}) async {
  final controller = TextEditingController(text: _text);
  Widget field = TextField(controller: controller, maxLines: null);
  if (normalize) {
    field = TouchSelectionNormalizer(controller: controller, child: field);
  }

  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 600, child: field)))));
  return controller;
}

RenderEditable _editable(WidgetTester tester) =>
    tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

Offset _offsetOf(WidgetTester tester, int index) {
  final editable = _editable(tester);
  final caret = editable.getLocalRectForCaret(TextPosition(offset: index));
  return editable.localToGlobal(caret.center);
}

/// Long-presses the last word and drags back to "beta", like selecting
/// the end of a message from the end towards the start.
Future<void> _selectBackwards(WidgetTester tester) async {
  final gesture = await tester.startGesture(_offsetOf(tester, _text.length - 2),
      kind: PointerDeviceKind.touch);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveTo(_offsetOf(tester, _text.indexOf("beta") + 1));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Drags the selection's end handle (the one at the right) back to the
/// middle of "gamma". Same geometry as Flutter's own text field tests: the
/// handle's corner sits on the selection endpoint.
Future<void> _dragEndHandle(
    WidgetTester tester, TextSelection selection) async {
  final editable = _editable(tester);
  final endpoints = editable.getEndpointsForSelection(selection);
  final handle =
      editable.localToGlobal(endpoints.last.point) + const Offset(1, 1);

  final gesture = await tester.startGesture(handle);
  await tester.pump();
  // Move past the touch slop first, as a finger does, so the handle's drag
  // starts before the real move.
  await gesture.moveBy(const Offset(-20, 0));
  await tester.pump();
  await gesture.moveTo(_offsetOf(tester, _text.indexOf("gamma") + 3));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets("backward selection pins the end handle without the fix",
      (tester) async {
    final controller = await _pump(tester, normalize: false);
    await _selectBackwards(tester);

    final selected = controller.selection;
    expect(selected.baseOffset, greaterThan(selected.extentOffset),
        reason: "a backward long-press drag leaves the base at the end");

    await _dragEndHandle(tester, selected);
    expect(controller.selection.end, selected.end,
        reason: "Flutter refuses to move the end handle");
  }, variant: android);

  testWidgets("normalizer frees the end handle", (tester) async {
    final controller = await _pump(tester, normalize: true);
    await _selectBackwards(tester);

    final selected = controller.selection;
    expect(selected.baseOffset, lessThan(selected.extentOffset));
    expect(selected.textInside(_text), contains("beta"));
    expect(selected.end, _text.length);

    await _dragEndHandle(tester, selected);
    expect(controller.selection.start, selected.start);
    expect(controller.selection.end, lessThan(_text.length));
  }, variant: android);

  testWidgets("hardware keyboard selections keep their direction",
      (tester) async {
    final controller = await _pump(tester, normalize: true);
    controller.selection =
        const TextSelection(baseOffset: _text.length, extentOffset: 6);

    final gesture =
        await tester.startGesture(Offset.zero, kind: PointerDeviceKind.mouse);
    await gesture.up();
    await tester.pump();

    expect(controller.selection.baseOffset, _text.length);
  }, variant: android);
}
