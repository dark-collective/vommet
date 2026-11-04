import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// The filled input bar shared by the live composer and theme preview.
/// Bars above it and popups keep their own surfaces.
class MessageBox extends StatelessWidget {
  const MessageBox({
    required this.borderRadius,
    required this.child,
    this.useComposerColors = true,
    super.key,
  });

  final BorderRadius borderRadius;
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
        decoration: BoxDecoration(
          color: backgroundColor(theme, useComposerColors: useComposerColors),
          borderRadius: borderRadius,
        ),
        // Paint over the contents, without adding padding or shifting controls.
        foregroundDecoration: border == null
            ? null
            : BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: border, width: 1),
              ),
        child: child,
      ),
    );
  }
}
