// Vommet: round buttons (e.g. the mobile settings back button) use the
// theme's tap ripple, which on AMOLED is the soft pressed overlay instead of
// opaque white over the icon (Vommet issue 599).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/atoms/circle_button.dart';
import 'package:tiamat/config/style/theme_amoled.dart';

void main() {
  test("AMOLED's tap ripple is the translucent pressed overlay", () {
    final splash = ThemeAmoled.theme.splashColor;
    expect(splash, ThemeAmoledColors.pressed);
    expect(splash.a, lessThan(0.5));
  });

  testWidgets("CircleButton leaves the ripple colour to the theme",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeAmoled.theme,
        home: Scaffold(
            body: CircleButton(icon: Icons.arrow_back, onPressed: () {}))));
    expect(tester.widget<InkWell>(find.byType(InkWell)).splashColor, isNull);
  });
}
