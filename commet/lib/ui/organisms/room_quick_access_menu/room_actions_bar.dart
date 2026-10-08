import 'package:commet/client/room.dart';
import 'package:commet/ui/layout/banner_gradient.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the phone member drawer's header (Discord-style layout): the room's
/// banner, if any, over a pinned row of room actions. The room's name with ▾
/// (its menu) is drawn once and moves the way the space name does: it sits at
/// the bottom of the banner, then glides into the row as the banner scrolls
/// away, its colour following. Icons that don't fit next to the name move into
/// the ▾ menu, the most used ones staying; the set never changes while
/// scrolling.
class RoomActionsBar extends StatelessWidget {
  const RoomActionsBar(this.room,
      {this.banner, this.bannerHeight = 0, super.key});

  final Room room;

  /// The banner, drawn at [fullBannerHeight] without its own title and
  /// clipped to [bannerHeight]; null when the room has none.
  final Widget? banner;

  /// How much of the banner still shows, 0 to [fullBannerHeight].
  final double bannerHeight;

  static const double rowHeight = 50;
  static const double fullBannerHeight = 100;
  static const double iconWidth = 44;
  static const double nameMinWidth = 140;

  // Kept in view first when space runs out.
  static int _priority(IconData icon) {
    const order = [
      Icons.person_add,
      Icons.call,
      Icons.phone_callback,
      Icons.search,
      Icons.calendar_month,
      Icons.push_pin,
      Icons.widgets,
    ];
    final i = order.indexOf(icon);
    return i < 0 ? order.length : i;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actions = RoomQuickAccessMenu(room: room, context: context).actions;
    final banner = this.banner;
    // 1 with the whole banner showing, 0 once it has scrolled away.
    final t = banner == null
        ? 0.0
        : (bannerHeight / fullBannerHeight).clamp(0.0, 1.0);
    final (_, glowText) = bannerGlow(context);
    final color = Color.lerp(scheme.onSurface, glowText, t)!;
    final shadows = t > 0.4
        ? const [
            BoxShadow(
                blurRadius: 2,
                spreadRadius: 10,
                color: Colors.black,
                offset: Offset(2, 2))
          ]
        : null;

    return LayoutBuilder(builder: (context, constraints) {
      // Always leave room for the name, so no icon comes or goes mid-scroll.
      final room = constraints.maxWidth - nameMinWidth;
      final fit = (room / iconWidth).floor().clamp(0, actions.length);
      final kept = ([...actions]
            ..sort((a, b) => _priority(a.icon).compareTo(_priority(b.icon))))
          .take(fit)
          .toSet();
      final shown = actions.where(kept.contains).toList();
      final overflow = actions.where((a) => !kept.contains(a)).toList();

      // The name's centre: the row's middle once collapsed, the banner's
      // bottom edge (as on the banner itself) while it shows.
      final collapsedY = bannerHeight + rowHeight / 2;
      final expandedY = bannerHeight - 18;
      final nameY = collapsedY + (expandedY - collapsedY) * t;

      final name = Builder(
        builder: (nameContext) => InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // The whole header: the menu opens under it.
            final box = context.findRenderObject() as RenderBox;
            RoomMenu.show(nameContext, this.room,
                anchor: box.localToGlobal(Offset.zero) & box.size,
                extra: [
                  for (final a in overflow)
                    SpaceMenuEntry(
                        a.name, a.icon, () => a.action?.call(context)),
                ]);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(this.room.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: color, shadows: shadows)),
                ),
                Icon(Icons.expand_more,
                    size: 20, color: color, shadows: shadows),
              ],
            ),
          ),
        ),
      );

      return Stack(
        children: [
          Column(
            children: [
              if (banner != null && bannerHeight > 0)
                SizedBox(
                  height: bannerHeight,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minHeight: fullBannerHeight,
                      maxHeight: fullBannerHeight,
                      child: Opacity(opacity: t, child: banner),
                    ),
                  ),
                ),
              Container(
                color: scheme.surfaceContainerLow,
                height: rowHeight,
                child: Row(
                  children: [
                    const Spacer(),
                    for (final action in shown)
                      SizedBox(
                        width: iconWidth,
                        height: rowHeight,
                        child: tiamat.IconButton(
                          icon: action.icon,
                          size: 20,
                          onPressed: () => action.action?.call(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 4,
            top: nameY - 20,
            height: 40,
            width: constraints.maxWidth - 8 - shown.length * iconWidth,
            child: Align(alignment: Alignment.centerLeft, child: name),
          ),
        ],
      );
    });
  }
}
