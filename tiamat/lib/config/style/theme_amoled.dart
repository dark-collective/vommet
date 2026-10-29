import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_common.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'dart:io' show Platform;

class ThemeAmoledColors {
  static const Color surfaceHigh1 = Color.fromARGB(255, 30, 30, 30);
  static const Color secondary = Color.fromARGB(255, 200, 200, 200);
  static const Color primary = Colors.white;
  static const Color surface = Colors.black;
  static const Color surfaceLow1 = Color.fromARGB(255, 10, 10, 10);
  static const Color surfaceLow2 = Color.fromARGB(255, 15, 15, 15);
  static const Color surfaceLow3 = Color.fromARGB(255, 20, 20, 20);
  static const Color surfaceLow4 = Color.fromARGB(255, 25, 25, 25);
  static const Color onSurface = Colors.white;
  static const Color highlightColor = Colors.white10;
  static const Color outlineColor = Color.fromARGB(255, 30, 34, 37);

  // Vommet: the default hover overlays (4-8% white) barely show on pure
  // black, so AMOLED uses stronger ones: hovering black reads as
  // [surfaceHigh1], fainter than a selected row's secondaryContainer.
  static const Color hover = Color.fromARGB(30, 255, 255, 255);
  static const Color pressed = Color.fromARGB(50, 255, 255, 255);
}

class ThemeAmoled {
  static ThemeData get theme {
    final base = ThemeBase.theme(const ColorScheme(
            primary: Colors.white,
            secondary: ThemeAmoledColors.secondary,
            secondaryContainer: Color.fromARGB(255, 40, 40, 40),
            surface: ThemeAmoledColors.surface,
            error: Color.fromARGB(255, 255, 124, 124),
            onPrimary: Colors.black,
            onSecondary: ThemeAmoledColors.onSurface,
            onSurface: Colors.white,
            onError: Colors.white,
            tertiaryContainer: Colors.black,
            brightness: Brightness.dark,
            outline: ThemeAmoledColors.surfaceHigh1))
        .copyWith(extensions: [
      const ExtraColors(
          codeHighlight: Color(0xffc678dd),
          linkColor: Color.fromARGB(255, 120, 120, 255)),
      const ThemeSettings(caulkBorders: true, caulkStrokeThickness: 1)
    ]);
    return base.copyWith(
      hoverColor: ThemeAmoledColors.hover,
      focusColor: ThemeAmoledColors.hover,
      // Vommet issue 599: tap ripples match the pressed overlay.
      splashColor: ThemeAmoledColors.pressed,
      // Vommet issue 863: the default selected segment colour
      // (secondaryContainer) is lost on black, so the selected segment is
      // filled white with black text.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: base.segmentedButtonTheme.style?.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? ThemeAmoledColors.primary
                  : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? ThemeAmoledColors.surface
                  : ThemeAmoledColors.onSurface),
          side: const WidgetStatePropertyAll(
              BorderSide(color: ThemeAmoledColors.secondary)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: base.textButtonTheme.style?.copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return ThemeAmoledColors.pressed;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return ThemeAmoledColors.hover;
            }
            return null;
          }),
        ),
      ),
    );
  }
}
