import 'package:commet/client/client.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Vommet issues 290 and 499: Alt+Up / Alt+Down open the previous / next room
/// in the left panel, and Alt+Shift+Up / Alt+Shift+Down the previous / next
/// room with unread messages. Nothing happens at either end of the list.
///
/// The room list on screen registers how to read its rooms in the order it
/// shows them, leaving out collapsed sections. It's only read when a shortcut
/// is pressed. A panel that registers nothing (the unified chat list
/// experiment) gets no shortcut.
class RoomListNavigation {
  static final List<(Object, List<Room> Function())> _lists = [];
  static final Map<Space, int> _shownSubspaces = {};

  /// [rooms] gives the panel's rooms in the order they're shown. The most
  /// recently registered list wins.
  static void register(Object owner, List<Room> Function() rooms) {
    _lists.removeWhere((e) => e.$1 == owner);
    _lists.add((owner, rooms));
  }

  static void unregister(Object owner) {
    _lists.removeWhere((e) => e.$1 == owner);
  }

  /// The rooms of the panel on screen, in order; empty when none registered.
  static List<Room> get visibleRooms =>
      _lists.isEmpty ? const [] : _lists.last.$2();

  /// A subspace's room list is on screen (its section is expanded).
  static void subspaceShown(Space space) {
    _shownSubspaces[space] = (_shownSubspaces[space] ?? 0) + 1;
  }

  static void subspaceHidden(Space space) {
    final count = (_shownSubspaces[space] ?? 0) - 1;
    if (count > 0) {
      _shownSubspaces[space] = count;
    } else {
      _shownSubspaces.remove(space);
    }
  }

  static bool isSubspaceShown(Space space) =>
      _shownSubspaces.containsKey(space);

  /// The item after (or before) [current] in [items] that matches [where].
  /// With no [current] in the list, the first (or last) match. Null at the
  /// end of the list: it doesn't wrap around.
  static T? step<T>(List<T> items, T? current,
      {required bool forward, bool Function(T item)? where}) {
    final index = current == null ? -1 : items.indexOf(current);
    if (forward) {
      for (var i = index + 1; i < items.length; i++) {
        if (where == null || where(items[i])) return items[i];
      }
    } else {
      for (var i = (index == -1 ? items.length : index) - 1; i >= 0; i--) {
        if (where == null || where(items[i])) return items[i];
      }
    }
    return null;
  }

  /// Handles Alt+Up/Down and Alt+Shift+Up/Down, opening the room with
  /// [open]. Returns whether [event] was one of them.
  static bool handleKey(
      KeyEvent event, Room? current, void Function(Room room) open) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return false;
    }

    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed) {
      return false;
    }

    final room = step(visibleRooms, current,
        forward: key == LogicalKeyboardKey.arrowDown,
        where: keyboard.isShiftPressed ? roomHasUnread : null);
    if (room != null) open(room);
    return true;
  }
}

/// Registers [rooms] with [RoomListNavigation] while this widget is mounted.
class RoomListRegistration extends StatefulWidget {
  const RoomListRegistration(
      {required this.rooms, required this.child, super.key});

  /// The list's rooms in the order it shows them.
  final List<Room> Function() rooms;

  final Widget child;

  @override
  State<RoomListRegistration> createState() => _RoomListRegistrationState();
}

class _RoomListRegistrationState extends State<RoomListRegistration> {
  @override
  void initState() {
    super.initState();
    RoomListNavigation.register(this, () => widget.rooms());
  }

  @override
  void dispose() {
    RoomListNavigation.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
