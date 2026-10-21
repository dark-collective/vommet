import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    return Semantics(
        label: notificationBadgeLabel(count),
        excludeSemantics: true,
        child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size / 2),
                  color: Colors.red.shade600),
              child: Center(
                child: Text(
                  count > 9 ? "9+" : count.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      color: Colors.white,
                      shadows: [const BoxShadow(blurRadius: 2)]),
                ),
              ),
            )));
  }
}
