import 'package:flutter/material.dart';

/// Vommet: shown in place of the message composer when the user cannot
/// chat in a room (banned from it, a DM with a blocked user, or a room that
/// was replaced).
///
/// A full-width bar with a top divider. The action is a tonal button to the
/// right of the text on wide panes, and a full-width row under it on narrow
/// ones.
class ComposerNotice extends StatelessWidget {
  const ComposerNotice({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.destructiveAction = false,
    this.iconColor,
    this.actionIcon,
    super.key,
  });

  final IconData icon;
  final String title;

  /// Optional second line; may wrap over several lines.
  final String? subtitle;

  final String? actionLabel;
  final VoidCallback? onAction;

  /// Draws the action's label in the theme's error colour.
  final bool destructiveAction;

  /// The icon's colour; the theme's error colour when null.
  final Color? iconColor;

  /// Optional icon in front of the action's label.
  final IconData? actionIcon;

  static const double narrowWidth = 480;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ],
    );

    final iconWidget = Padding(
      padding: const EdgeInsets.only(right: 12, top: 2),
      child: Icon(icon, color: iconColor ?? scheme.error, size: 22),
    );

    final buttonStyle = destructiveAction
        ? FilledButton.styleFrom(foregroundColor: scheme.error)
        : null;
    final button = actionLabel != null && onAction != null
        ? actionIcon != null
            ? FilledButton.tonalIcon(
                onPressed: onAction,
                style: buttonStyle,
                icon: Icon(actionIcon, size: 18),
                label: Text(actionLabel!),
              )
            : FilledButton.tonal(
                onPressed: onAction,
                style: buttonStyle,
                child: Text(actionLabel!),
              )
        : null;

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < narrowWidth;

      return Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, narrow ? 16 : 12),
        child: narrow
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [iconWidget, Expanded(child: text)],
                  ),
                  if (button != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(height: 44, child: button),
                  ],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  iconWidget,
                  Expanded(child: text),
                  if (button != null) ...[const SizedBox(width: 12), button],
                ],
              ),
      );
    });
  }
}
