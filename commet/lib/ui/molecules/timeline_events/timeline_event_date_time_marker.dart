import 'package:commet/main.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventDateTimeMarker extends StatelessWidget {
  const TimelineEventDateTimeMarker(
      {required this.time, this.onTap, super.key});
  final DateTime time;

  /// Vommet (chat navigation): tapping the date opens Jump to date.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var color = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: Opacity(
              opacity: 0.1,
              child: Divider(
                height: 1,
                color: color,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: tiamat.Text.labelLow(
                  TextUtils.dividerLabel(time, context,
                      relative: preferences.relativeDateDividers.value),
                  color: color,
                ),
              ),
            ),
          ),
          Expanded(
            child: Opacity(
              opacity: 0.1,
              child: Divider(
                height: 1,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
