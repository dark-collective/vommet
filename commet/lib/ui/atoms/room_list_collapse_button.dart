import 'package:commet/ui/layout/responsive_desktop.dart';
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
class RoomListHeaderAction extends InheritedWidget {
  const RoomListHeaderAction({required super.child, super.key});

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
