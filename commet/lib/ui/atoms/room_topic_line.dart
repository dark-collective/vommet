// Vommet issue 970: a DM topic is metadata, below the latest message.
import 'package:commet/utils/dm_topic_line.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RoomTopicLine extends StatelessWidget {
  const RoomTopicLine(this.topic, {super.key});
  final String topic;

  String get label => Intl.message("Topic",
      name: "roomListTopicLabel",
      desc: "Label before a DM topic in the room list");

  String description(String topic) => Intl.message("Room topic: $topic",
      name: "roomListTopicDescription",
      desc: "Screen reader label for the full topic below a message preview",
      args: [topic]);

  @override
  Widget build(BuildContext context) {
    final line = dmTopicLine(topic);
    if (line == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: description(line),
      excludeSemantics: true,
      child: Tooltip(
        message: line,
        excludeFromSemantics: true,
        child: Text("$label · $line",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
