// Vommet: the opt-in composer design workshop (Vommet issue 1142).
import 'dart:math' as math;

import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ComposerWorkshop extends InheritedWidget {
  const ComposerWorkshop(
      {required this.enabled,
      required this.cardColor,
      required super.child,
      super.key});
  final bool enabled;
  final Color cardColor;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComposerWorkshop>()?.enabled ??
      preferences.experimentComposerWorkshop.value;
  @override
  bool updateShouldNotify(ComposerWorkshop oldWidget) =>
      enabled != oldWidget.enabled || cardColor != oldWidget.cardColor;

  static const desktopHeight = 44.0;
  static const desktopInsets = EdgeInsets.fromLTRB(8, 0, 8, 8);
  static const cardRadius = BorderRadius.all(Radius.circular(8));

  static Color? fillOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComposerWorkshop>()?.cardColor;

  static ThemeData sidebarTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    final glass = theme.extension<GlassSettings>();
    return theme.copyWith(
      colorScheme: scheme.copyWith(
        surfaceContainerLow:
            Color.lerp(scheme.surfaceContainerLow, scheme.surface, .55),
      ),
      extensions: [
        ...theme.extensions.values
            .where((extension) => extension is! GlassSettings),
        if (glass != null)
          glass.copyWith(
            surfaceContainerLowOpacity:
                (glass.surfaceContainerLowOpacity + glass.surfaceOpacity) / 2,
          ),
      ],
    );
  }

  static const phoneHeight = 52.0;
  static double barHeight(BuildContext context, {bool phone = false}) {
    final text = Theme.of(context).textTheme;
    final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        text: phone
            ? TextSpan(text: ' ', style: text.bodyMedium)
            : TextSpan(children: [
                TextSpan(
                    text: 'Name\n',
                    style: text.bodyMedium!.copyWith(fontSize: 15)),
                TextSpan(
                    text: 'Online',
                    style: text.labelSmall!.copyWith(fontSize: 11)),
              ]))
      ..layout();
    final result = math.max(
        phone ? phoneHeight : desktopHeight, painter.height + (phone ? 32 : 4));
    painter.dispose();
    return result;
  }
}

class ComposerWorkshopScope extends StatelessWidget {
  const ComposerWorkshopScope({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
      stream: preferences.experimentComposerWorkshop.onChanged,
      initialData: preferences.experimentComposerWorkshop.value,
      builder: (context, snapshot) {
        final enabled = snapshot.data ?? false;
        final theme = Theme.of(context);
        final fill = theme.extension<ExtraColors>()?.composerBackground ??
            theme.colorScheme.surfaceContainerLow;
        final gradient = theme.extension<FoundationSettings>()?.gradient;
        return ComposerWorkshop(
          enabled: enabled,
          cardColor: gradient != null && theme.brightness == Brightness.dark
              ? Color.lerp(fill, Colors.black, .25)!
              : fill,
          child: child,
        );
      });
}
