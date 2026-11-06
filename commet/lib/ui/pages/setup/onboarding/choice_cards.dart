// Vommet: side-by-side choices with a picture each, for the onboarding pages
// (Vommet issue 524) and the settings they set.
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ChoiceCardOption<T> {
  const ChoiceCardOption({
    required this.value,
    required this.title,
    required this.description,
    this.preview,
    this.icon,
    this.badge,
    this.badgeExperimental = false,
    this.onBadgeTap,
    this.extra,
  });

  final T value;
  final String title;
  final String description;

  /// A small picture of what the choice looks like.
  final Widget? preview;

  /// Shown before the title when there is no [preview].
  final IconData? icon;

  /// A small tag after the title, such as "Default".
  final String? badge;

  /// Shows [badge] in the amber "Experimental" colors.
  final bool badgeExperimental;

  /// Makes [badge] a button of its own (an info icon shows it can be
  /// tapped), apart from picking the card.
  final VoidCallback? onBadgeTap;

  /// More content under the description (a list of pros and cons).
  final Widget? extra;
}

/// The options side by side, in rows of as many as fit, or stacked when
/// there's no room.
class ChoiceCards<T> extends StatelessWidget {
  const ChoiceCards({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<ChoiceCardOption<T>> options;
  final T selected;
  final void Function(T value) onSelected;

  /// Vommet issue 862: the narrowest a card gets beside others. Six app
  /// icon cards in one 460px row left titles one letter per line.
  static const double minCardWidth = 200;

  static const double _gap = 12;

  /// How many cards fit in one row of [width] (at least 1).
  static int cardsPerRow(double width, int count) =>
      ((width + _gap) ~/ (minCardWidth + _gap)).clamp(1, count < 1 ? 1 : count);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cards = [
        for (final o in options)
          ChoiceCard(
            key: ValueKey("choice-card-${o.value}"),
            option: o,
            selected: o.value == selected,
            onTap: () => onSelected(o.value),
          ),
      ];
      final perRow = cardsPerRow(constraints.maxWidth, cards.length);
      if (perRow == 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: cards,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _gap,
        children: [
          for (var i = 0; i < cards.length; i += perRow)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: _gap,
                children: [
                  for (var j = i; j < i + perRow; j++)
                    Expanded(
                        child: j < cards.length
                            ? cards[j]
                            : const SizedBox.shrink()),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class ChoiceCard<T> extends StatelessWidget {
  const ChoiceCard({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ChoiceCardOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withAlpha(70)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.preview != null) ...[
                  ExcludeSemantics(
                      child: IgnorePointer(child: option.preview!)),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    if (option.preview == null && option.icon != null) ...[
                      Icon(option.icon,
                          size: 20,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: option.badge == null
                          ? tiamat.Text.labelEmphasised(option.title)
                          // Wraps so a long badge drops under the title
                          // instead of squeezing it.
                          : Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                  tiamat.Text.labelEmphasised(option.title),
                                  ChoiceCardBadge(
                                    option.badge!,
                                    experimental: option.badgeExperimental,
                                    onTap: option.onBadgeTap,
                                  ),
                                ]),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                tiamat.Text.labelLow(option.description),
                if (option.extra != null) ...[
                  const SizedBox(height: 8),
                  option.extra!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small pill after a choice's title.
class ChoiceCardBadge extends StatelessWidget {
  const ChoiceCardBadge(this.text,
      {this.experimental = false, this.onTap, super.key});

  final String text;

  /// Amber, for a choice that is still unfinished.
  final bool experimental;

  /// When set, the pill is a button with an info icon.
  final VoidCallback? onTap;

  /// The amber of an [experimental] pill, readable on light and dark themes.
  static Color experimentalColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF0B45A)
          : const Color(0xFF8A5A00);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amber = experimentalColor(context);
    final fg = experimental ? amber : scheme.onPrimaryContainer;
    final radius = BorderRadius.circular(8);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: experimental ? amber.withAlpha(40) : scheme.primaryContainer,
        borderRadius: radius,
        border: experimental ? Border.all(color: amber.withAlpha(110)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          if (onTap != null) Icon(Icons.info_outline, size: 12, color: fg),
          Text(text,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w500)),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: pill,
        ),
      ),
    );
  }
}

/// A short list under a choice's description, with a heading and an icon
/// per line (checks for upsides, warnings for drawbacks).
class ChoiceCardPoints extends StatelessWidget {
  const ChoiceCardPoints(
      {required this.heading,
      required this.points,
      required this.icon,
      required this.iconColor,
      super.key});

  final String heading;
  final List<String> points;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        Text(heading.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.6)),
        for (final p in points)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              Expanded(child: tiamat.Text.labelLow(p)),
            ],
          ),
      ],
    );
  }
}
