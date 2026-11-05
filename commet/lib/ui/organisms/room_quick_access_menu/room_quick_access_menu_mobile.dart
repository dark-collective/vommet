import 'package:commet/client/room.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';

class RoomQuickAccessMenuViewMobile extends StatelessWidget {
  const RoomQuickAccessMenuViewMobile({required this.room, super.key});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final menu = RoomQuickAccessMenu(room: room, context: context);

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: menu.actions
              .map((e) => e.icon == Icons.translate
                  ? Flexible(child: _LabeledButton(entry: e))
                  : AspectRatio(
                      aspectRatio: 1,
                      child: roomQuickAccessButton(context, e),
                    ))
              .toList(),
        ),
      ),
    );
  }
}

/// Vommet phone composer round 3: "Translate this room" with a visible
/// label ("Translate" / "Stop translating"), not just an icon.
class _LabeledButton extends StatelessWidget {
  const _LabeledButton({required this.entry});

  final RoomQuickAccessMenuEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = entry.name.startsWith("Stop");
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      child: Semantics(
        button: true,
        label: entry.name,
        excludeSemantics: true,
        child: Material(
          color: on ? scheme.primary.withAlpha(40) : Colors.transparent,
          shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => entry.action?.call(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(entry.icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(on ? "Stop translating" : "Translate",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: scheme.primary)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
