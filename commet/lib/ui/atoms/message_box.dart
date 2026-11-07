import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// The filled input bar shared by the live composer and theme preview.
/// Bars above it and popups keep their own surfaces.
class MessageBox extends StatelessWidget {
  const MessageBox({
    required this.borderRadius,
    required this.child,
    this.useComposerColors = true,
    this.minimumHeight = 0,
    this.fill,
    super.key,
  });

  static const chatPadding = EdgeInsets.fromLTRB(8, 2, 8, 4);
  static const double chatMinimumHeight = 44;

  final BorderRadius borderRadius;
  final double minimumHeight;
  // Vommet issue 1142: the floating cards share a fill across the panes.
  final Color? fill;
  final Widget child;

  /// Profile bio editing reuses MessageInput but is not a chat composer.
  final bool useComposerColors;

  static Color backgroundColor(ThemeData theme,
          {bool useComposerColors = true}) =>
      (useComposerColors
          ? theme.extension<ExtraColors>()?.composerBackground
          : null) ??
      theme.colorScheme.surfaceContainerLow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = useComposerColors
        ? theme.extension<ExtraColors>()?.composerBorder
        : null;
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        constraints: BoxConstraints(minHeight: minimumHeight),
        decoration: BoxDecoration(
          color: fill ??
              backgroundColor(theme, useComposerColors: useComposerColors),
          borderRadius: borderRadius,
        ),
        foregroundDecoration: border == null
            ? null
            : BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: border),
              ),
        child: child,
      ),
    );
  }
}
