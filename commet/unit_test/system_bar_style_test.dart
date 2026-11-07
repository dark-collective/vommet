import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_changer.dart';

Future<SystemUiOverlayStyle> _styleFor(
    WidgetTester tester, Brightness themeBrightness) async {
  final theme = ThemeData(brightness: themeBrightness);
  await tester.pumpWidget(ThemeChanger(
    initialTheme: theme,
    shouldFollowSystemTheme: () => false,
    getLightTheme: () async => theme,
    getDarkTheme: () async => theme,
    materialAppBuilder: (context, theme) =>
        MaterialApp(theme: theme, home: const SizedBox()),
  ));
  return tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first)
      .value;
}

void main() {
  testWidgets("a light app theme gets dark system bar icons", (tester) async {
    final style = await _styleFor(tester, Brightness.light);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.statusBarBrightness, Brightness.light);
  });

  testWidgets("a dark app theme gets light system bar icons", (tester) async {
    final style = await _styleFor(tester, Brightness.dark);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
  });
}
