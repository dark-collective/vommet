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
    // Whole logical pixels throughout, and a glyph no smaller than 8 px: a
    // fractional glyph of about 7 px rendered as a grey blob at 1x.
    final outer = size.roundToDouble();
    const ring = 2.0;
    final glyph = (outer - 2 * ring - 2).clamp(8.0, 24.0);
    return Container(
      width: outer,
      height: outer,
      padding: const EdgeInsets.all(ring),
      decoration: BoxDecoration(
        color: ringColor ?? scheme.surfaceContainer,
        shape: BoxShape.circle,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: color ?? scheme.secondaryContainer,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: glyph,
          color: color != null ? Colors.white : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
