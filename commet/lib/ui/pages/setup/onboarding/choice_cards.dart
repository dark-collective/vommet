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
  });

  final T value;
  final String title;
  final String description;

  /// A small picture of what the choice looks like.
  final Widget? preview;

  /// Shown before the title when there is no [preview].
  final IconData? icon;
}

/// The options side by side, or stacked when there's no room.
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

  /// Narrower than this, the cards stack.
  static const double sideBySideMinWidth = 460;

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
      if (constraints.maxWidth < sideBySideMinWidth) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: cards,
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [for (final c in cards) Expanded(child: c)],
        ),
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
                    Expanded(child: tiamat.Text.labelEmphasised(option.title)),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
