import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/layout/banner_gradient.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:flutter/material.dart';

/// The room's banner as a header with the room's name, laid out like the space
/// banner, or nothing when the room has none. Clicking it opens the full image.
class RoomBanner extends StatefulWidget {
  const RoomBanner(this.room,
      {this.width,
      this.height = RoomBannerView.fullHeight,
      this.showTitle = true,
      super.key});
  final Room room;

  /// False when the parent draws the room's name itself (the phone drawer's
  /// row, whose one name glides from the banner into the row).
  final bool showTitle;

  /// The current height (the collapsing header shrinks it).
  final double height;

  /// Width to use when the parent leaves it unbounded, as the desktop side
  /// panel does. A bounded parent's width always wins.
  final double? width;

  @override
  State<RoomBanner> createState() => _RoomBannerState();
}

class _RoomBannerState extends State<RoomBanner> {
  StreamSubscription? _sub;
  StreamSubscription? _gradientSub;

  @override
  void initState() {
    super.initState();
    _gradientSub = preferences.bannerGradient.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _sub = widget.room
        .getComponent<RoomBannerComponent>()
        ?.onBannerChanged
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _gradientSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (glow, glowText) = bannerGlow(context);
    return RoomBannerView(
      widget.room.getComponent<RoomBannerComponent>()?.banner,
      name: widget.room.displayName,
      width: widget.width,
      height: widget.height,
      gradientColor: glow,
      textColor: glowText,
      showTitle: widget.showTitle,
      onOpenMenu: (anchor) =>
          RoomMenu.show(context, widget.room, anchor: anchor),
    );
  }
}

/// Draws a banner like SpaceHeader: cover-cropped, a gradient up from the
/// bottom and the name over it. Click or right-click opens the full image.
class RoomBannerView extends StatelessWidget {
  const RoomBannerView(this.image,
      {required this.name,
      this.width,
      this.height = fullHeight,
      this.gradientColor,
      this.textColor,
      this.onOpenMenu,
      this.showTitle = true,
      super.key});
  final ImageProvider? image;
  final bool showTitle;
  final String name;
  final double? width;
  final double height;

  /// A banner header's full and collapsed heights (the space header's).
  static const double fullHeight = 100;
  static const double compactHeight = 50;

  /// Behind the title, fading up from the bottom; null for no gradient.
  final Color? gradientColor;
  final Color? textColor;

  /// Opens the room menu under the name (anchored to [anchor]); null for a
  /// plain name.
  final void Function(Rect anchor)? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final width =
          constraints.hasBoundedWidth ? constraints.maxWidth : this.width;
      // An unbounded parent and no width given: draw nothing. Asking for an
      // infinite width throws during layout and blanks the whole room view.
      if (width == null || !width.isFinite) return const SizedBox.shrink();

      final colorScheme = Theme.of(context).colorScheme;
      void open() => Lightbox.show(context, image: image);

      // How much of the image shows: 1 at full height, fading to 0 (a plain
      // name row, as Discord keeps pinned) as the header collapses.
      final shown = ((height - compactHeight) / (fullHeight - compactHeight))
          .clamp(0.0, 1.0);
      final color =
          Color.lerp(colorScheme.onSurface, textColor ?? Colors.white, shown)!;
      final shadows = shown > 0.4
          ? const [
              BoxShadow(
                  blurRadius: 2,
                  spreadRadius: 10,
                  color: Colors.black,
                  offset: Offset(2, 2))
            ]
          : null;

      final title = Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .titleMedium!
            .copyWith(color: color, shadows: shadows),
      );

      final row = Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
        child: Row(
          children: [
            Flexible(
              child: onOpenMenu == null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                      child: title)
                  : Builder(
                      builder: (_) => InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          // The whole banner: the menu opens under it.
                          final box = context.findRenderObject() as RenderBox;
                          onOpenMenu!(
                              box.localToGlobal(Offset.zero) & box.size);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: title),
                              Icon(Icons.expand_more,
                                  size: 20, color: color, shadows: shadows),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );

      return ClipRRect(
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Solid behind the pinned row, so the list doesn't show through.
              ColoredBox(color: colorScheme.surfaceContainer),
              if (shown > 0)
                Opacity(
                  opacity: shown,
                  child: Image(
                    image: image,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) =>
                        ColoredBox(color: colorScheme.primary),
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: open,
                  onSecondaryTap: open,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: switch (gradientColor) {
                        final Color color => LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              color.withValues(alpha: color.a * shown),
                              Colors.transparent
                            ],
                          ),
                        null => null,
                      },
                    ),
                    child: Align(
                      alignment: Alignment.lerp(
                          Alignment.centerLeft, Alignment.bottomLeft, shown)!,
                      child: showTitle ? row : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
