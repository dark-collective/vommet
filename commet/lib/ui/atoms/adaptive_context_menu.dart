import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AdaptiveContextMenu extends StatelessWidget {
  const AdaptiveContextMenu(
      {required this.items,
      this.itemsBuilder,
      this.onLongPress,
      this.touchTapOpens = false,
      this.modal = false,
      required this.child,
      super.key});
  final List<tiamat.ContextMenuItem> items;
  final Widget child;
  final bool modal;

  /// Vommet: builds the items when the menu opens; null means [items].
  final List<tiamat.ContextMenuItem>? Function()? itemsBuilder;

  /// Vommet: desktop only, runs on a long press instead of opening the
  /// menu; returning false opens the menu after all.
  final bool Function()? onLongPress;

  /// Vommet: desktop only, a touch tap opens the menu (when [onLongPress]
  /// took the long press, a touch screen has no other way in).
  final bool touchTapOpens;

  /// Vommet: this menu with [onLongPress], [itemsBuilder] and
  /// [touchTapOpens] set.
  AdaptiveContextMenu withHooks(
          {bool Function()? onLongPress,
          List<tiamat.ContextMenuItem>? Function()? itemsBuilder,
          bool touchTapOpens = false}) =>
      AdaptiveContextMenu(
          items: items,
          itemsBuilder: itemsBuilder,
          onLongPress: onLongPress,
          touchTapOpens: touchTapOpens,
          modal: modal,
          key: key,
          child: child);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return child;
    }

    if (MediaQuery.of(context).desktop) {
      return tiamat.ContextMenu(
        child: child,
        items: items,
        itemsBuilder: itemsBuilder,
        onLongPress: onLongPress,
        touchTapOpens: touchTapOpens,
        modal: modal,
      );
    } else {
      var callback = () => showModalBottomSheet(
          isDismissible: true,
          showDragHandle: true,
          context: context,
          builder: (modalContext) => SingleChildScrollView(
                child: ScaledSafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      spacing: 4,
                      mainAxisSize: MainAxisSize.min,
                      children: (itemsBuilder?.call() ?? items).map((item) {
                        if (item.customBuilder != null) {
                          return item.customBuilder!.call(
                            context,
                            () {
                              Navigator.of(modalContext).pop();
                              item.onPressed?.call();
                            },
                            closeMenu: () {
                              Navigator.of(modalContext).pop();
                            },
                          );
                        }

                        final button = SizedBox(
                          height: 50,
                          child: tiamat.TextButton(
                            item.text,
                            textColor: Theme.of(context).colorScheme.onSurface,
                            icon: item.icon,
                            onTap: () {
                              Navigator.of(modalContext).pop();
                              item.onPressed?.call();
                            },
                          ),
                        );
                        // Vommet: no hover on touch screens, so the
                        // explanation sits under the item.
                        if (item.tooltip == null) return button;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            button,
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                              child: tiamat.Text.labelLow(item.tooltip!),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ));

      return InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: child,
        onLongPress: modal ? null : callback,
        onTap: modal ? callback : null,
      );
    }
  }
}
