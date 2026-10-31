import 'package:commet/main.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventDateTimeMarker extends StatelessWidget {
  const TimelineEventDateTimeMarker({required this.time, super.key});
  final DateTime time;

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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: tiamat.Text.labelLow(
              TextUtils.dividerLabel(time, context,
                  relative: preferences.relativeDateDividers.value),
              color: color,
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
