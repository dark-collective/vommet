import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_amoled.dart';

// Vommet issue 863: on AMOLED the selected segment must stand out from black.
void main() {
  final style = ThemeAmoled.theme.segmentedButtonTheme.style!;

  test('selected segment is filled with primary', () {
    expect(
        style.backgroundColor!.resolve({WidgetState.selected}), Colors.white);
    expect(
        style.foregroundColor!.resolve({WidgetState.selected}), Colors.black);
  });

  test('unselected and disabled segments keep the defaults', () {
    expect(style.backgroundColor!.resolve({}), isNull);
    expect(
        style.backgroundColor!
            .resolve({WidgetState.selected, WidgetState.disabled}),
        isNull);
  });

  test('keeps the hand cursor from the base theme', () {
    expect(style.mouseCursor, isNotNull);
  });
}
