import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_amoled.dart';

// Vommet issue 863: the selected segment must stand out on AMOLED's black.
void main() {
  testWidgets("AMOLED selected segment is filled", (tester) async {
    final theme = ThemeAmoled.theme;
    await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
            body: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text("Off")),
            ButtonSegment(value: 1, label: Text("On")),
          ],
          selected: const {1},
          onSelectionChanged: (_) {},
        ))));
    Material materialOf(String label) => tester.widget<Material>(find
        .ancestor(of: find.text(label), matching: find.byType(Material))
        .first);
    final selected = materialOf("On");
    final unselected = materialOf("Off");
    expect(selected.color, theme.colorScheme.primary);
    expect(unselected.color, isNot(theme.colorScheme.primary));
    expect(selected.textStyle?.color, theme.colorScheme.onPrimary);
    expect(unselected.textStyle?.color, theme.colorScheme.onSurface);
  });

  test("AMOLED keeps the base segment cursor", () {
    expect(
        ThemeAmoled.theme.segmentedButtonTheme.style!.mouseCursor, isNotNull);
  });
}
