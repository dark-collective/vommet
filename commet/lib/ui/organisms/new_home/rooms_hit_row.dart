import 'package:flutter/material.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/atoms/avatar_badge.dart';

/// Vommet: the New Home Rooms page's search hit leading picture. A room
/// shows its avatar, like the room lists do, so two rooms with similar names
/// can be told apart; a non-text room (voice, photos, calendar) keeps its
/// type as a small badge on the avatar's corner. A room without an avatar
/// keeps its type icon, as before.
class RoomsHitAvatar extends StatelessWidget {
  const RoomsHitAvatar(
      {super.key,
      required this.name,
      required this.color,
      required this.typeIcon,
      this.avatar,
      this.badge});

  /// Width and height of the leading picture.
  static const double size = 28;

  final String name;
  final Color color;
  final ImageProvider? avatar;

  /// The room's type icon (#, speaker, photo, calendar), drawn when there
  /// is no [avatar].
  final IconData typeIcon;

  /// Type mark on the avatar's corner, or null for a text room.
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = avatar;
    if (image == null) {
      return SizedBox.square(
          dimension: size,
          child: Icon(typeIcon, size: 20, color: scheme.onSurfaceVariant));
    }
    // The room's own (thumbnail) avatar provider, as the room lists use: no
    // full-size download for a 28 px picture.
    final picture = Avatar(
        radius: size / 2,
        image: image,
        placeholderText: name,
        placeholderColor: color);
    final mark = badge;
    return SizedBox.square(
      dimension: size,
      child: mark == null
          ? picture
          : AvatarBadge.wrap(picture, AvatarBadge(mark, size: 14), offset: -3),
    );
  }
}

/// Vommet: one New Home Rooms search hit: [leading], the name with the
/// matched part highlighted, where it lives ([breadcrumb]), and an unread dot.
class RoomsHitRow extends StatelessWidget {
  const RoomsHitRow(
      {super.key,
      required this.leading,
      required this.name,
      required this.matchStart,
      required this.matchEnd,
      required this.breadcrumb,
      required this.unread,
      required this.onTap});

  final Widget leading;
  final String name;
  final int matchStart;
  final int matchEnd;
  final String breadcrumb;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(
        fontSize: 14,
        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
        color: scheme.onSurface);
    final start = matchStart.clamp(0, name.length);
    final end = matchEnd.clamp(start, name.length);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(spacing: 10, children: [
            leading,
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text.rich(
                      TextSpan(style: base, children: [
                        TextSpan(text: name.substring(0, start)),
                        TextSpan(
                            text: name.substring(start, end),
                            style: TextStyle(
                                backgroundColor: scheme.primary.withAlpha(70),
                                color: scheme.onSurface)),
                        TextSpan(text: name.substring(end)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(breadcrumb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
            ),
            if (unread)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: scheme.onSurface, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),
    );
  }
}
