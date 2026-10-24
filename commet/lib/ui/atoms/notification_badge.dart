import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// What the badge shows: the count up to 99, then "99+", as Element and
/// Discord do (Vommet issue 654; it was "9+" past 9).
String notificationBadgeText(int count) => count > 99 ? "99+" : "$count";

class NotificationBadge extends StatelessWidget {
  const NotificationBadge(this.count, {super.key, this.size = 16});
  final double size;
  final int count;

  String notificationBadgeLabel(int howMany) => Intl.plural(howMany,
      one: "$howMany unread notification",
      other: "$howMany unread notifications",
      desc: "Read by screen readers for the red count badge on a room or space",
      name: "notificationBadgeLabel",
      args: [howMany]);

  @override
  Widget build(BuildContext context) {
    // Vommet: say the real count, not the "9+" drawn on it (Vommet issue 308).
    final label = notificationBadgeText(count);
    return Semantics(
        label: notificationBadgeLabel(count),
        excludeSemantics: true,
        // Vommet issue 654: two or three characters widen it into a pill.
        child: Container(
            height: size,
            constraints: BoxConstraints(minWidth: size),
            padding: label.length > 1
                ? EdgeInsets.symmetric(horizontal: size * 0.25)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size / 2),
                color: Colors.red.shade600),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    height: 1,
                    color: Colors.white,
                    shadows: [const BoxShadow(blurRadius: 2)]),
              ),
            )));
  }
}
