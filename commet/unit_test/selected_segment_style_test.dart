// Vommet: settings' segmented buttons fill the selected segment with the
// theme's accent colour, so it stays visible on OLED/black themes
// (Vommet issue 594).
import 'package:commet/ui/atoms/selected_segment_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scheme = ColorScheme.dark(
      primary: Colors.white,
      onPrimary: Colors.black,
      secondaryContainer: Colors.black);
  final style = selectedSegmentStyle(scheme);

  test("the selected segment uses the accent colour", () {
    const selected = {WidgetState.selected};
    expect(style.backgroundColor!.resolve(selected), Colors.white);
    expect(style.foregroundColor!.resolve(selected), Colors.black);
  });

  test("unselected and disabled segments keep the defaults", () {
    for (final states in [
      <WidgetState>{},
      {WidgetState.selected, WidgetState.disabled},
    ]) {
      expect(style.backgroundColor!.resolve(states), isNull);
      expect(style.foregroundColor!.resolve(states), isNull);
    }
  });
}
