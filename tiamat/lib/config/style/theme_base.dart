import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_common.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeBase {
  // Flutter's default for buttons and toggles is the hand cursor on web only
  // (adaptiveClickable); desktop should show it too (Vommet issue 452).
  static const _click = WidgetStateMouseCursor.clickable;

  static ThemeData theme(ColorScheme scheme) => ThemeData(
        brightness: scheme.brightness,
        fontFamily: "RobotoCustom",
        fontFamilyFallback: ThemeCommon.fontFamilyFallback(),
        useMaterial3: true,
        textTheme: TextTheme(
            headlineLarge: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: "NunitoSans",
              fontSize: 48,
              fontVariations: [
                FontVariation.weight(900),
              ],
            ),
            headlineMedium: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: "NunitoSans",
              fontSize: 38,
              fontVariations: [
                FontVariation.weight(900),
              ],
            ),
            headlineSmall: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: "NunitoSans",
              fontSize: 28,
              fontVariations: [
                FontVariation.weight(900),
              ],
            ),
            titleMedium: TextStyle(
              fontFamily: "NunitoSans",
              fontSize: 20,
              fontVariations: [
                FontVariation.weight(700),
              ],
            ),
            titleSmall: TextStyle(
              fontFamily: "NunitoSans",
              fontSize: 16,
              fontVariations: [
                FontVariation.weight(700),
              ],
            ),
            titleLarge: TextStyle(fontWeight: FontWeight.w800)),
        extensions: const [
          ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
          ExtraColors(
            codeHighlight: Color(0xffc678dd),
            linkColor: Color.fromARGB(255, 120, 120, 255),
          ),
        ],
        colorScheme: scheme,
        expansionTileTheme: ExpansionTileThemeData(
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        listTileTheme: ListTileThemeData(
          // Vommet issue 695: RadioListTile/CheckboxListTile/SwitchListTile
          // rows (and ExpansionTile headers) take the row's cursor from here,
          // not from radioTheme & co.
          mouseCursor: _click,
          dense: true,
          contentPadding: EdgeInsets.fromLTRB(8, 2, 8, 0),
        ),
        canvasColor: scheme.surface,
        iconTheme: IconThemeData(color: scheme.secondary),
        shadowColor: Colors.black.withAlpha(100),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            mouseCursor: _click,
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide.none,
              ),
            ),
          ),
        ),
        dividerTheme: DividerThemeData(color: scheme.surfaceContainerHigh),
        sliderTheme: SliderThemeData(
          inactiveTrackColor: scheme.primary.withAlpha(100),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: scheme.surface,
          shadowColor: Colors.black,
        ),
        dividerColor: scheme.outline,
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            mouseCursor: _click,
            shape: WidgetStatePropertyAll<OutlinedBorder>(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(mouseCursor: _click),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(mouseCursor: _click),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(mouseCursor: _click),
        ),
        menuButtonTheme: MenuButtonThemeData(
          style: ButtonStyle(mouseCursor: _click),
        ),
        popupMenuTheme: PopupMenuThemeData(mouseCursor: _click),
        tabBarTheme: TabBarThemeData(mouseCursor: _click),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(mouseCursor: _click),
        ),
        floatingActionButtonTheme:
            FloatingActionButtonThemeData(mouseCursor: _click),
        checkboxTheme: CheckboxThemeData(mouseCursor: _click),
        radioTheme: RadioThemeData(mouseCursor: _click),
        switchTheme: SwitchThemeData(mouseCursor: _click),
      );
}
