import 'package:commet/client/room.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the phone member drawer's pinned row (Discord-style layout). The
/// room's name with ▾ (its menu) fades in on the left as the banner above
/// scrolls away, and the room actions sit on the right. Icons that don't fit
/// next to the name move into the ▾ menu, the most used ones staying.
class RoomActionsBar extends StatelessWidget {
  const RoomActionsBar(this.room, {required this.nameOpacity, super.key});

  final Room room;

  /// 0 while the banner shows the name, 1 once it has scrolled away.
  final double nameOpacity;

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
    final showName = nameOpacity > 0;

    return LayoutBuilder(builder: (context, constraints) {
      final room = constraints.maxWidth - (showName ? nameMinWidth : 0);
      final fit = (room / iconWidth).floor().clamp(0, actions.length);
      final kept = ([...actions]
            ..sort((a, b) => _priority(a.icon).compareTo(_priority(b.icon))))
          .take(fit)
          .toSet();
      final shown = actions.where(kept.contains).toList();
      final overflow = actions.where((a) => !kept.contains(a)).toList();

      return Container(
        color: scheme.surfaceContainerLow,
        height: 50,
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          children: [
            Expanded(
              child: showName
                  ? IgnorePointer(
                      ignoring: nameOpacity < 0.5,
                      child: Opacity(
                        opacity: nameOpacity,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Builder(
                            builder: (nameContext) => InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                final box =
                                    context.findRenderObject() as RenderBox;
                                RoomMenu.show(nameContext, this.room,
                                    anchor: box.localToGlobal(Offset.zero) &
                                        box.size,
                                    extra: [
                                      for (final a in overflow)
                                        SpaceMenuEntry(a.name, a.icon,
                                            () => a.action?.call(context)),
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
                                              ?.copyWith(
                                                  color: scheme.onSurface)),
                                    ),
                                    Icon(Icons.expand_more,
                                        size: 20, color: scheme.onSurface),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            for (final action in shown)
              SizedBox(
                width: iconWidth,
                height: 50,
                child: tiamat.IconButton(
                  icon: action.icon,
                  size: 20,
                  onPressed: () => action.action?.call(context),
                ),
              ),
          ],
        ),
      );
    });
  }
}
