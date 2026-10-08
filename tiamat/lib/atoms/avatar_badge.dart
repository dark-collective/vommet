import 'package:flutter/material.dart';

/// Small round icon pinned to the bottom-right corner of an avatar, the way
/// the presence dot sits on a user avatar. Used to mark room types (e.g. a
/// speaker on voice rooms) when the room's avatar hides its type icon.
class AvatarBadge extends StatelessWidget {
  const AvatarBadge(this.icon,
      {super.key, this.size = 14, this.ringColor, this.color});

  final IconData icon;
  final double size;

  /// Colour of the ring separating the badge from the avatar; defaults to
  /// the surface the lists are drawn on.
  final Color? ringColor;

  /// Fill colour; the icon turns white on it. Defaults to the theme's
  /// secondary container.
  final Color? color;

  /// Stacks [badge] on the bottom-right corner of [child].
  static Widget wrap(Widget child, Widget badge, {double offset = -2}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(right: offset, bottom: offset, child: badge),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? scheme.secondaryContainer,
        shape: BoxShape.circle,
        border: Border.all(
          color: ringColor ?? scheme.surfaceContainer,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.62,
          color: color != null ? Colors.white : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
