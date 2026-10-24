import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// Vommet: a small text-free drawing of the app (space rail, room list, chat
/// and message box) in a theme's colors, so the theme list shows what each
/// theme looks like instead of only its name.
class ThemePreviewCard extends StatelessWidget {
  const ThemePreviewCard(
      {required this.theme,
      required this.name,
      this.selected = false,
      this.onTap,
      this.width = 120,
      super.key});

  final ThemeData theme;
  final String name;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    var colors = Theme.of(context).colorScheme;
    var label = Theme.of(context).textTheme.labelMedium;

    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: width + 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      width: 2,
                      color: selected ? colors.primary : Colors.transparent),
                ),
                child: ThemeThumbnail(theme: theme, width: width),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: label?.copyWith(
                  color: selected ? colors.onSurface : colors.secondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ThemeThumbnail extends StatelessWidget {
  const ThemeThumbnail({required this.theme, this.width = 120, super.key});

  final ThemeData theme;
  final double width;

  @override
  Widget build(BuildContext context) {
    var s = theme.colorScheme;
    var foundation = theme.extension<FoundationSettings>();
    var glass = theme.extension<GlassSettings>();
    var backdrop = foundation?.gradient;
    var image = foundation?.image;

    // Over a gradient or image the panels are see-through, as in the app.
    Color panel(Color c, double? opacity) =>
        (backdrop != null || image != null) && opacity != null
            ? c.withAlpha((opacity * 255).round())
            : c;

    Widget bar(Color c, double w, double h) => Container(
        width: w,
        height: h,
        margin: const EdgeInsets.only(bottom: 4),
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)));

    Widget dot(Color c) => Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle));

    return Container(
      width: width,
      height: width * 0.63,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: backdrop,
        image: image != null
            ? DecorationImage(image: image, fit: BoxFit.cover)
            : null,
        color: backdrop == null && image == null
            ? (foundation?.color ?? s.surfaceContainerLowest)
            : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: s.onSurface.withAlpha(24)),
      ),
      child: Row(children: [
        Container(
          width: width * 0.13,
          color: panel(
              s.surfaceContainerLowest, glass?.surfaceContainerLowestOpacity),
          padding: const EdgeInsets.only(top: 5),
          child: Column(children: [
            dot(s.primary),
            dot(s.surfaceContainerHigh),
          ]),
        ),
        Container(
          width: width * 0.25,
          color:
              panel(s.surfaceContainerLow, glass?.surfaceContainerLowOpacity),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(s.surfaceContainerHigh, width * 0.18, 5),
              bar(s.secondary.withAlpha(120), width * 0.15, 3),
              bar(s.secondary.withAlpha(120), width * 0.12, 3),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: panel(s.surface, glass?.surfaceOpacity),
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(s.onSurface.withAlpha(200), width * 0.33, 4),
                bar(s.secondary.withAlpha(140), width * 0.43, 3),
                bar(s.onSurface.withAlpha(200), width * 0.25, 4),
                bar(s.secondary.withAlpha(140), width * 0.37, 3),
                const Spacer(),
                Container(
                  height: 10,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                      color: panel(s.surfaceContainerHigh,
                          glass?.surfaceContainerHighOpacity),
                      borderRadius: BorderRadius.circular(3)),
                  child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                          color: s.primary, shape: BoxShape.circle)),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
