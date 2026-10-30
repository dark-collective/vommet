import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MentionWidget extends StatelessWidget {
  const MentionWidget(
      {required this.displayName,
      required this.placeholderColor,
      this.avatar,
      this.style,
      this.fallbackIcon,
      this.vias,
      this.onTap,
      this.showAvatar = true,
      this.userId,
      this.roomId,
      super.key});
  final String displayName;
  final ImageProvider? avatar;
  final Function()? onTap;
  final IconData? fallbackIcon;
  final TextStyle? style;
  final List<String>? vias;
  final bool showAvatar;
  final Color placeholderColor;

  /// The mentioned user or room, for redacted mode.
  final String? userId;
  final String? roomId;

  @override
  Widget build(BuildContext context) {
    final redaction = RedactionScope.of(context);
    var displayName = this.displayName;
    var placeholderColor = this.placeholderColor;
    if (userId != null) {
      displayName = redaction.name(displayName, userId!);
      placeholderColor = redaction.nameColor(placeholderColor, userId!);
    } else if (roomId != null) {
      displayName = redaction.roomName(displayName, roomId!);
    }

    return Material(
        // Vommet: a visible pill (was alpha 30, all but invisible on dark
        // themes, so its inner padding read as a stray indent).
        color: Theme.of(context).colorScheme.primary.withAlpha(50),
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fallbackIcon != null && avatar == null && showAvatar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 1, 0),
                    child: Icon(
                      fallbackIcon,
                      size: 14,
                      color: tiamat.Text.adjustColor(context, placeholderColor),
                    ),
                  ),
                if (avatar != null || fallbackIcon == null && showAvatar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 3, 0),
                    child: tiamat.Avatar(
                      placeholderText: displayName,
                      placeholderColor: placeholderColor,
                      redactionKey: userId ?? roomId,
                      image: avatar,
                      radius: 8,
                    ),
                  ),
                Text(displayName,
                    textScaler: TextScaler.noScaling,
                    style: (style ?? Theme.of(context).textTheme.bodyMedium)
                        ?.copyWith(
                            color: tiamat.Text.adjustColor(
                                context, placeholderColor))),
                if (vias != null && !redaction.isActive)
                  for (var i in vias!)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
                      child: Text("($i)",
                          textScaler: TextScaler.noScaling,
                          style:
                              (style ?? Theme.of(context).textTheme.bodyMedium)
                                  ?.copyWith(
                                      fontSize: 12,
                                      color: tiamat.Text.adjustColor(
                                          context, placeholderColor))),
                    ),
              ],
            ),
          ),
        ));
  }
}
