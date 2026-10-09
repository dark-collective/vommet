import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: optional extras for a room action, kept beside the entry rather
/// than in it, so the views that draw actions and the features that add
/// extras don't depend on each other.
///
/// - an icon drawn by a widget (the call button shows whether a call is on,
///   whether you're in it, or that you can't call), instead of `entry.icon`;
/// - secondary entries (DMs' "Classic call"), offered on right-click or
///   long-press of the button and in the ▾ room menu.
///
/// The same file is added by more than one topic; keep the copies identical.
class RoomQuickAccessExtras {
  static final _icons =
      Expando<Widget Function(BuildContext context, double size)>();
  static final _secondary = Expando<List<RoomQuickAccessMenuEntry>>();

  static void setIcon(RoomQuickAccessMenuEntry entry,
          Widget Function(BuildContext context, double size) builder) =>
      _icons[entry] = builder;

  static void setSecondary(RoomQuickAccessMenuEntry entry,
          List<RoomQuickAccessMenuEntry> entries) =>
      _secondary[entry] = entries;

  /// The entry's icon: its own widget if it has one, else `entry.icon`.
  static Widget icon(BuildContext context, RoomQuickAccessMenuEntry entry,
      {double size = 20, Color? color}) {
    final builder = _icons[entry];
    if (builder != null) return builder(context, size);
    return Icon(entry.icon,
        size: size, color: color ?? Theme.of(context).colorScheme.secondary);
  }

  /// The entry as a round icon button, like tiamat's IconButton, drawing
  /// its own icon widget when it has one.
  static Widget button(BuildContext context, RoomQuickAccessMenuEntry entry,
      {double size = 20, VoidCallback? onPressed}) {
    final onTap = onPressed ?? () => entry.action?.call(context);
    if (_icons[entry] == null) {
      return tiamat.IconButton(icon: entry.icon, size: size, onPressed: onTap);
    }
    return ClipOval(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Center(child: icon(context, entry, size: size)),
          ),
        ),
      ),
    );
  }

  static List<RoomQuickAccessMenuEntry> secondary(
          RoomQuickAccessMenuEntry entry) =>
      _secondary[entry] ?? const [];
}
