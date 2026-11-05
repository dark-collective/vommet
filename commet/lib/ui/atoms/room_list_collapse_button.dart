import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the button that collapses the room list to room pictures, or
/// widens it again (Vommet issue 456). It sits in the room list's header row
/// (the space name, the Home search field), where Discord, Slack and VS Code
/// keep theirs, with a small rounded-square hover.
class RoomListCollapseButton extends StatelessWidget {
  const RoomListCollapseButton(
      {required this.collapsed, this.color, super.key});

  /// True in the collapsed list: the button widens it again.
  final bool collapsed;

  /// The icon's colour; the theme's muted text colour when null.
  final Color? color;

  static String get collapseRoomListTooltip =>
      Intl.message("Show room pictures only",
          name: "collapseRoomListTooltip",
          desc: "Tooltip on the button that collapses the room list to room "
              "pictures without names");

  static String get expandRoomListTooltip => Intl.message("Show room names",
      name: "expandRoomListTooltip",
      desc: "Tooltip on the button that widens the room list again after it "
          "was collapsed to room pictures");

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = color ?? scheme.onSurfaceVariant;
    return tiamat.Tooltip(
      text: collapsed ? expandRoomListTooltip : collapseRoomListTooltip,
      preferredDirection: AxisDirection.right,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(6),
          hoverColor: scheme.onSurface.withValues(alpha: 0.10),
          onTap: () => ResponsiveDesktop.setCollapsed(!collapsed),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: CustomPaint(
                size: const Size.square(18),
                painter: _SidebarIconPainter(iconColor, pointsRight: collapsed),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A side panel outline with an arrow pointing the way the list will move.
class _SidebarIconPainter extends CustomPainter {
  _SidebarIconPainter(this.color, {required this.pointsRight});

  final Color color;
  final bool pointsRight;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
        RRect.fromLTRBR(3 * s, 4 * s, 21 * s, 20 * s, Radius.circular(3 * s)),
        paint);
    canvas.drawLine(Offset(9 * s, 4 * s), Offset(9 * s, 20 * s), paint);
    final (tip, tail) = pointsRight ? (16.0, 13.5) : (13.5, 16.0);
    canvas.drawPath(
        Path()
          ..moveTo(tail * s, 9.5 * s)
          ..lineTo(tip * s, 12 * s)
          ..lineTo(tail * s, 14.5 * s),
        paint);
  }

  @override
  bool shouldRepaint(_SidebarIconPainter old) =>
      old.color != color || old.pointsRight != pointsRight;
}

/// Hands the collapse button to the header rows of the room list below it,
/// so the lists needn't take it as a parameter. Absent (mobile, the narrow
/// window's drawer), the headers show no button.
///
/// A space's banner header shows no button (it covered the artwork); its
/// menu offers [menuEntry] instead.
class RoomListHeaderAction extends InheritedWidget {
  const RoomListHeaderAction({required super.child, super.key});

  /// The space menu's entry collapsing the list, or null where the list
  /// can't be collapsed.
  static SpaceMenuEntry? menuEntry(BuildContext context) {
    if (context.getInheritedWidgetOfExactType<RoomListHeaderAction>() == null) {
      return null;
    }
    return SpaceMenuEntry(RoomListCollapseButton.collapseRoomListTooltip,
        Icons.view_sidebar_outlined, () => ResponsiveDesktop.setCollapsed(true),
        shortcut: RoomListCollapseShortcut.label);
  }

  /// The button for the room list header row, or null where the list can't
  /// be collapsed. [color] matches the row's text (e.g. over a banner).
  static Widget? of(BuildContext context, {Color? color}) {
    final found =
        context.dependOnInheritedWidgetOfExactType<RoomListHeaderAction>();
    if (found == null) return null;
    return RoomListCollapseButton(collapsed: false, color: color);
  }

  @override
  bool updateShouldNotify(RoomListHeaderAction oldWidget) => false;
}

/// Vommet issue 456: Ctrl+Shift+B (Cmd+Shift+B on macOS) collapses the room
/// list to room pictures, or widens it again, anywhere in the desktop layout.
class RoomListCollapseShortcut extends StatefulWidget {
  const RoomListCollapseShortcut({required this.child, super.key});

  final Widget child;

  static bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;

  /// The keys, as the space menu shows them.
  static String get label => _mac ? "⌘⇧B" : "Ctrl+Shift+B";

  /// Whether [event] is the shortcut.
  static bool matches(KeyEvent event, HardwareKeyboard keyboard) =>
      event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.keyB &&
      keyboard.isShiftPressed &&
      (_mac ? keyboard.isMetaPressed : keyboard.isControlPressed) &&
      !keyboard.isAltPressed;

  @override
  State<RoomListCollapseShortcut> createState() =>
      _RoomListCollapseShortcutState();
}

class _RoomListCollapseShortcutState extends State<RoomListCollapseShortcut> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!RoomListCollapseShortcut.matches(event, HardwareKeyboard.instance)) {
      return false;
    }
    ResponsiveDesktop.setCollapsed(!ResponsiveDesktop.collapsed.value);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Vommet issue 456: over the room list while its edge is dragged far enough
/// past the narrowest width that letting go collapses it.
class RoomListCollapseHint extends StatelessWidget {
  const RoomListCollapseHint({super.key});

  static String get roomListCollapseHint =>
      Intl.message("Let go to show room pictures only",
          name: "roomListCollapseHint",
          desc: "Shown over the room list while its edge is dragged narrow "
              "enough that letting go collapses it to room pictures");

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ColoredBox(
        color: scheme.primary.withValues(alpha: 0.10),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.inverseSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(roomListCollapseHint,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onInverseSurface)),
          ),
        ),
      ),
    );
  }
}
