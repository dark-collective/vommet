import 'dart:async';
import 'package:commet/client/components/space_banner/space_banner_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/layout/banner_gradient.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:flutter/material.dart';

import '../../client/client.dart';

class SpaceHeader extends StatefulWidget {
  const SpaceHeader(this.space,
      {this.onTap,
      this.backgroundColor = Colors.transparent,
      this.height,
      super.key});
  final Space space;
  final Color backgroundColor;
  final void Function()? onTap;

  /// Vommet: the current height, below the status bar (the collapsing header
  /// shrinks it from [fullHeight] to [compactHeight]); null for the full one.
  final double? height;

  /// Vommet: a banner header's full and collapsed heights. A space without a
  /// banner always uses [compactHeight].
  static const double fullHeight = 100;
  static const double compactHeight = 50;

  static bool hasBanner(Space space) =>
      space.getComponent<SpaceBannerComponent>()?.banner != null;

  @override
  State<SpaceHeader> createState() => _SpaceHeaderState();
}

class _SpaceHeaderState extends State<SpaceHeader> {
  late StreamSubscription _sub;
  late StreamSubscription _gradientSub;

  @override
  void initState() {
    super.initState();
    _sub = widget.space.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
    // Vommet: redraw when the banner gradient setting changes.
    _gradientSub = preferences.bannerGradient.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _gradientSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    EdgeInsets padding = MediaQuery.of(context).scale().viewPadding;
    final top = MediaQuery.of(context).padding.top;

    // Vommet: Discord-style header. Only a real banner fills it (upstream
    // stretched the avatar into a fake one); without one it is a plain row
    // on the sidebar's background. The name opens the space menu (which also
    // invites people), the rest opens the space's home.
    final image = widget.space.getComponent<SpaceBannerComponent>()?.banner;
    final height = widget.height ??
        (image != null ? SpaceHeader.fullHeight : SpaceHeader.compactHeight);
    final fullSize = image ?? widget.space.avatar;
    // How much of the banner shows: 1 at full height, fading to 0 (the plain
    // row Discord keeps pinned) as the header collapses.
    final shown = image == null
        ? 0.0
        : ((height - SpaceHeader.compactHeight) /
                (SpaceHeader.fullHeight - SpaceHeader.compactHeight))
            .clamp(0.0, 1.0);
    final onImage = shown > 0.4;
    final (glow, glowText) = bannerGlow(context);
    final textColor =
        Color.lerp(Theme.of(context).colorScheme.onSurface, glowText, shown)!;
    const shadows = [
      BoxShadow(
          blurRadius: 2,
          spreadRadius: 10,
          color: Colors.black,
          offset: Offset(2, 2))
    ];
    final gradient = image != null ? glow?.withValues(alpha: shown) : null;

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
      child: Row(
        children: [
          Flexible(
            child: Builder(
              builder: (_) => InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  // The whole header: the menu opens under it.
                  final box = context.findRenderObject() as RenderBox;
                  SpaceMenu.show(context, widget.space,
                      anchor: box.localToGlobal(Offset.zero) & box.size);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(widget.space.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium!
                                .copyWith(
                                    color: textColor,
                                    shadows: onImage ? shadows : null)),
                      ),
                      Icon(Icons.expand_more,
                          size: 20,
                          color: textColor,
                          shadows: onImage ? shadows : null),
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
      borderRadius: image != null
          ? const BorderRadius.only(
              bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8))
          : BorderRadius.zero,
      child: SizedBox(
        height: height + top,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null && shown > 0)
              Opacity(
                opacity: shown,
                child: Image(
                  image: image,
                  fit: BoxFit.cover,
                  alignment: padding.top > 0
                      ? AlignmentGeometry.xy(0, -0.25)
                      : Alignment.center,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onSecondaryTap: fullSize != null
                    ? () => Lightbox.show(context, image: fullSize)
                    : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: switch (gradient) {
                      final Color color => LinearGradient(
                          begin: AlignmentGeometry.bottomCenter,
                          end: AlignmentGeometry.topCenter,
                          colors: [color, Colors.transparent],
                        ),
                      null => null,
                    },
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(top: top),
                    child: Align(
                      alignment: Alignment.lerp(
                          Alignment.centerLeft, Alignment.bottomLeft, shown)!,
                      child: row,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
