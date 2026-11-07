// Vommet: the open chat's row in the unified chat list uses the theme's
// "Selected room" colour when the theme picks one (Vommet issue 589), and the
// default tint otherwise. Made-up names.
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const _picked = Color(0xff7a1f2b);

const _chat = ChatEntry(key: "acct:garden", roomId: "garden", name: "Garden");

Future<void> _pump(WidgetTester tester, {Color? selectedRoom}) =>
    tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [
          ExtraColors(
              codeHighlight: Colors.purple,
              linkColor: Colors.blue,
              selectedRoom: selectedRoom)
        ]),
        home: Scaffold(
            body: ChatRowTile(_chat,
                now: DateTime(2026, 10, 22), selected: true))));

Color? _rowColor(WidgetTester tester) => tester
    .widget<Material>(find
        .ancestor(of: find.byType(InkWell), matching: find.byType(Material))
        .first)
    .color;

void main() {
  testWidgets("the selected row uses the theme's Selected room colour",
      (tester) async {
    await _pump(tester, selectedRoom: _picked);
    expect(_rowColor(tester), _picked);
  });

  testWidgets("without one, the selected row keeps the default tint",
      (tester) async {
    await _pump(tester);
    final scheme = ThemeData.dark().colorScheme;
    expect(_rowColor(tester), scheme.primaryContainer.withAlpha(150));
  });
}
