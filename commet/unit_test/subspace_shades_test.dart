// Vommet: nested subspace cards on the space page stay visible in every
// theme, including AMOLED, which defines no container shades of its own.

import 'package:commet/ui/organisms/space_summary/space_summary_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';

void main() {
  for (final (name, theme) in [
    ("dark", ThemeDark.theme),
    ("light", ThemeLight.theme),
    ("amoled", ThemeAmoled.theme),
  ]) {
    test("$name: each nesting level is a different, visible shade", () {
      final scheme = theme.colorScheme;
      final shades = SpaceSummaryViewState.subspaceShades(scheme);
      expect(shades.toSet().length, 3, reason: "three distinct levels");
      expect(shades.skip(1).every((c) => c != scheme.surface), isTrue,
          reason: "nested cards don't vanish into the background");
    });
  }
}
