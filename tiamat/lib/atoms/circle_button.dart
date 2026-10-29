import 'package:flutter/material.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

import '../config/style/theme_extensions.dart';

@UseCase(name: 'Default', type: CircleButton)
Widget wbcircleButton(BuildContext context) {
  return const Center(
      child: CircleButton(
    radius: 25,
    icon: Icons.add,
  ));
}

class CircleButton extends StatelessWidget {
  const CircleButton(
      {super.key,
      this.radius = 15,
      this.icon,
      this.onPressed,
      this.color,
      this.iconColor,
      this.mouseCursor = WidgetStateMouseCursor.clickable});
  final double radius;
  final Function? onPressed;
  final IconData? icon;
  final Color? color;
  final Color? iconColor;
  final MouseCursor? mouseCursor;
  @override
  Widget build(BuildContext context) {
    var shadows = Theme.of(context).extension<ShadowSettings>();
    return Container(
      decoration:
          BoxDecoration(shape: BoxShape.circle, boxShadow: shadows?.shadows),
      clipBehavior: Clip.antiAlias,
      child: ClipOval(
        child: Material(
          color: color ?? Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            mouseCursor: mouseCursor,
            // Vommet issue 599: the theme's splash colour, like every other
            // InkWell; onSecondaryContainer is opaque (white on AMOLED) and
            // hid the icon while the ripple played.
            onTap: onPressed == null
                ? null
                : () {
                    onPressed?.call();
                  },
            child: SizedBox(
                width: radius * 2,
                height: radius * 2,
                child: icon != null
                    ? Align(
                        alignment: Alignment.center,
                        child: Icon(
                          color: iconColor ??
                              Theme.of(context).colorScheme.secondary,
                          icon,
                          size: radius,
                        ))
                    : null),
          ),
        ),
      ),
    );
  }
}
