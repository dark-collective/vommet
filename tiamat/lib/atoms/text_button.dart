import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';
import './text.dart' as tiamat;

@UseCase(name: 'Default', type: TextButton)
Widget wbiconUseCase(BuildContext context) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 30,
            child: TextButton("Height: 30", icon: Icons.tag),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 35,
            child: TextButton("Height: 35", icon: Icons.tag),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 40,
            child: TextButton("Height: 40", icon: Icons.tag),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 45,
            child: TextButton("Height: 45", icon: Icons.tag),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 50,
            child: TextButton("Height: 50", icon: Icons.tag),
          ),
        ),
      ],
    ),
  );
}

@UseCase(name: 'With Image', type: TextButton)
Widget wbiconUseCaseWithImage(BuildContext context) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 30,
            child: TextButton(
              "Height: 30",
              avatar: AssetImage(
                "assets/images/placeholder/generic/checker_purple.png",
              ),
              icon: Icons.tag,
            ),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 35,
            child: TextButton(
              "Height: 35",
              avatar: AssetImage(
                "assets/images/placeholder/generic/checker_purple.png",
              ),
              icon: Icons.tag,
            ),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 40,
            child: TextButton(
              "Height: 40",
              avatar: AssetImage(
                "assets/images/placeholder/generic/checker_purple.png",
              ),
              icon: Icons.tag,
            ),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 45,
            child: TextButton(
              "Height: 45",
              avatar: AssetImage(
                "assets/images/placeholder/generic/checker_purple.png",
              ),
              icon: Icons.tag,
            ),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 50,
            child: TextButton(
              "Height: 50",
              avatar: AssetImage(
                "assets/images/placeholder/generic/checker_purple.png",
              ),
              icon: Icons.tag,
            ),
          ),
        ),
      ],
    ),
  );
}

@UseCase(name: 'With Avatar Placeholder', type: TextButton)
Widget wbiconUseCaseWithAvatarPlaceholder(BuildContext context) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 30,
            child: TextButton(
              "Height: 30",
              avatarPlaceholderText: "A",
              avatarPlaceholderColor: Colors.amber,
              icon: Icons.tag,
            ),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 35,
            child: TextButton(
              "Height: 35",
              avatarPlaceholderText: "A",
              avatarPlaceholderColor: Colors.amber,
              icon: Icons.tag,
            ),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 40,
            child: TextButton(
              "Height: 40",
              avatarPlaceholderText: "A",
              avatarPlaceholderColor: Colors.amber,
              icon: Icons.tag,
            ),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 45,
            child: TextButton(
              "Height: 45",
              avatarPlaceholderText: "A",
              avatarPlaceholderColor: Colors.amber,
              icon: Icons.tag,
            ),
          ),
        ),
        material.Padding(
          padding: EdgeInsets.all(8.0),
          child: material.SizedBox(
            height: 50,
            child: TextButton(
              "Height: 50",
              avatarPlaceholderText: "A",
              avatarPlaceholderColor: Colors.amber,
              icon: Icons.tag,
            ),
          ),
        ),
      ],
    ),
  );
}

class TextButton extends StatelessWidget {
  const TextButton(
    this.text, {
    super.key,
    this.icon,
    this.onTap,
    this.highlighted = false,
    this.textColor,
    this.iconColor,
    this.avatar,
    this.highlightColor = null,
    this.iconSize = 20,
    this.avatarRadius = 12,
    this.avatarPlaceholderColor,
    this.avatarPlaceholderText,
    this.customBuilder,
    this.softwrap,
    this.footer,
    this.avatarBadge,
    this.avatarBadgeColor,
    this.avatarRingColor,
    this.maxLines = 1,
  });
  final String text;

  final IconData? icon;
  final ImageProvider? avatar;
  final String? avatarPlaceholderText;
  final Color? avatarPlaceholderColor;
  final Color? highlightColor;
  final bool highlighted;
  final double iconSize;
  final double avatarRadius;
  final void Function()? onTap;
  final Widget Function(Widget child, BuildContext context)? customBuilder;
  final Widget? footer;
  final Color? textColor;
  final Color? iconColor;
  final bool? softwrap;

  /// Small icon drawn on the bottom-right of the avatar (see [AvatarBadge]).
  final IconData? avatarBadge;

  /// Fill of the [avatarBadge]; null for the theme's default.
  final Color? avatarBadgeColor;

  /// Vommet: when set, the avatar sits in an [AvatarRing] of this colour and
  /// [avatarBadge] becomes a small glyph beside it (in [avatarBadgeColor])
  /// instead of a badge covering the picture.
  final Color? avatarRingColor;

  /// Vommet: lines the label may wrap to before it's cut off.
  final int maxLines;

  double get _leadSize => avatarRingColor != null && useAvatar
      ? avatarRadius * 2 + 4
      : avatarRadius * 2;

  bool get useAvatar => avatar != null || avatarPlaceholderText != null;

  Widget _withBadge(BuildContext context, Widget avatar) {
    if (avatarRingColor != null) {
      return AvatarRing(
        size: _leadSize,
        color: avatarRingColor!,
        glyph: avatarBadge,
        glyphColor: avatarBadgeColor,
        child: avatar,
      );
    }
    if (avatarBadge == null) return avatar;
    return AvatarBadge.wrap(
      avatar,
      AvatarBadge(
        avatarBadge!,
        size: (avatarRadius + 4).clamp(14, 16).roundToDouble(),
        color: avatarBadgeColor,
        ringColor: highlighted
            ? highlightColor ?? Theme.of(context).colorScheme.secondaryContainer
            : null,
      ),
      offset: -3,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = material.Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            // Vommet: a row sized by a wrapping label centres its avatar
            // and label (a fixed-height row centres them by its height).
            crossAxisAlignment: maxLines > 1
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (icon != null || useAvatar)
                Padding(
                  padding: const EdgeInsets.all(1.0),
                  child: Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: _leadSize,
                      height: _leadSize,
                      child: useAvatar
                          ? _withBadge(
                              context,
                              Avatar(
                                radius: avatarRingColor != null
                                    ? AvatarRing.innerSize(_leadSize) / 2
                                    : avatarRadius,
                                image: avatar,
                                placeholderColor: avatarPlaceholderColor,
                                placeholderText: avatarPlaceholderText,
                              ),
                            )
                          : Icon(
                              size: iconSize,
                              icon!,
                              weight: 0.5,
                              color: highlighted
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer
                                  : iconColor ??
                                      Theme.of(context).colorScheme.onSurface,
                            ),
                    ),
                  ),
                ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: tiamat.Text.labelEmphasised(
                      text,
                      maxLines: maxLines,
                      softwrap: softwrap,
                      overflow: TextOverflow.ellipsis,
                      color: highlighted
                          ? Theme.of(context).colorScheme.onSecondaryContainer
                          : textColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (footer != null) footer!,
      ],
    );

    if (customBuilder != null) {
      content = customBuilder!(content, context);
    }

    return material.TextButton(
      clipBehavior: Clip.antiAlias,
      style: ButtonStyle(
        // Vommet: wrapping labels size the row themselves (the caller sets
        // its minimum height) instead of Material's 40 px minimum.
        minimumSize:
            maxLines > 1 ? const MaterialStatePropertyAll(Size.zero) : null,
        tapTargetSize: maxLines > 1 ? MaterialTapTargetSize.shrinkWrap : null,
        padding: MaterialStatePropertyAll(
          material.EdgeInsets.fromLTRB(
              8, maxLines > 1 ? 3 : 0, 8, maxLines > 1 ? 3 : 0),
        ),
        backgroundColor: MaterialStatePropertyAll(
          highlighted
              ? highlightColor ??
                  Theme.of(context).colorScheme.secondaryContainer
              : null,
        ),
      ),
      child: content,
      onPressed: onTap,
    );
  }
}
