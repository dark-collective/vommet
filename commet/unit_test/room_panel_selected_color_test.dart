// Vommet: the open room's row in the home column's list uses the theme's
// "Selected room" colour (Vommet issue 639) and draws no highlight without
// one. Made-up names.
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _picked = Color(0xff7a1f2b);

Future<void> _pump(WidgetTester tester, {Color? selectedColor}) =>
    tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
            body: RoomPanelView(
                displayName: "Garden", selectedColor: selectedColor))));

Iterable<Color?> _colors(WidgetTester tester) => tester
    .widgetList<Material>(find.descendant(
        of: find.byType(RoomPanelView), matching: find.byType(Material)))
    .map((m) => m.color);

void main() {
  testWidgets("the open room's row takes the theme's Selected room colour",
      (tester) async {
    await _pump(tester, selectedColor: _picked);
    expect(_colors(tester), contains(_picked));
  });

  testWidgets("no Selected room colour draws no highlight", (tester) async {
    await _pump(tester);
    expect(_colors(tester), isNot(contains(_picked)));
  });
}
