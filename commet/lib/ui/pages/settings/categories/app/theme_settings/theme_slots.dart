// Vommet: with Theme mode "Follow system", one theme for when the system is
// light and one for when it is dark. Pick a slot, then any theme card.
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ThemeSlotStrings {
  static String get labelWhenSystemLight =>
      Intl.message("When the system is light",
          name: "labelWhenSystemLight",
          desc: "Theme settings: the slot for the theme used in light mode");

  static String get labelWhenSystemDark =>
      Intl.message("When the system is dark",
          name: "labelWhenSystemDark",
          desc: "Theme settings: the slot for the theme used in dark mode");

  static String get labelPickForLight =>
      Intl.message("Tap a theme below to use it when the system is light.",
          name: "labelPickForLight",
          desc: "Theme settings hint while the light slot is selected");

  static String get labelPickForDark =>
      Intl.message("Tap a theme below to use it when the system is dark.",
          name: "labelPickForDark",
          desc: "Theme settings hint while the dark slot is selected");

  static String get badgeLight => Intl.message("Light",
      name: "badgeThemeSlotLight",
      desc: "Badge on a theme card: used when the system is light");

  static String get badgeDark => Intl.message("Dark",
      name: "badgeThemeSlotDark",
      desc: "Badge on a theme card: used when the system is dark");

  static String get badgeBoth => Intl.message("Light and dark",
      name: "badgeThemeSlotBoth",
      desc: "Badge on a theme card: used in both light and dark mode");
}

class ThemeSlots extends StatelessWidget {
  const ThemeSlots({required this.nameOf, super.key});

  final String Function(String id) nameOf;

  Widget slot(BuildContext context, Brightness brightness, bool selected) {
    var colors = Theme.of(context).colorScheme;
    var light = brightness == Brightness.light;
    var id = light ? preferences.lightThemeId : preferences.darkThemeId;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(10),
        onTap: () => preferences.themeSlot.value = brightness,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colors.primary.withAlpha(30) : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color:
                    selected ? colors.primary : colors.secondary.withAlpha(60),
                width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Icon(light ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: colors.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelLow(light
                      ? ThemeSlotStrings.labelWhenSystemLight
                      : ThemeSlotStrings.labelWhenSystemDark),
                  Text(nameOf(id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: preferences.themeSlot,
      builder: (context, current, _) {
        var light =
            slot(context, Brightness.light, current == Brightness.light);
        var dark = slot(context, Brightness.dark, current == Brightness.dark);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth < 480) {
                  return Column(
                      spacing: 8,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [light, dark]);
                }
                return Row(spacing: 8, children: [
                  Expanded(child: light),
                  Expanded(child: dark),
                ]);
              }),
              const SizedBox(height: 8),
              tiamat.Text.labelLow(current == Brightness.light
                  ? ThemeSlotStrings.labelPickForLight
                  : ThemeSlotStrings.labelPickForDark),
            ],
          ),
        );
      },
    );
  }
}

/// Marks a theme card with the slot(s) it fills. [id] null = not following
/// the system, no badge.
Widget slotBadge(BuildContext context, String? id, Widget card) {
  if (id == null) return card;
  var light = preferences.lightThemeId == id;
  var dark = preferences.darkThemeId == id;
  if (!light && !dark) return card;

  var colors = Theme.of(context).colorScheme;
  var text = light && dark
      ? ThemeSlotStrings.badgeBoth
      : light
          ? ThemeSlotStrings.badgeLight
          : ThemeSlotStrings.badgeDark;
  return Stack(clipBehavior: Clip.none, children: [
    card,
    Positioned(
      top: -6,
      right: -2,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: colors.primary, borderRadius: BorderRadius.circular(10)),
          child: Text(text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onPrimary, fontWeight: FontWeight.w700)),
        ),
      ),
    ),
  ]);
}
