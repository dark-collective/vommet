import 'package:commet/client/attachment.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:flutter/material.dart';

abstract class TimelineEventMessage extends TimelineEvent {
  String getPlaintextBody(Timeline timeline);

  Widget? buildFormattedContent({Timeline? timeline});
  String? get body;
  String? get bodyFormat;
  String? get formattedBody;

  List<Attachment>? get attachments;

  bool isEdited(Timeline timeline);

  /// Vommet: every version of this message, newest first and the original
  /// last; just the original when there are no edits.
  Future<List<MessageVersion>> getEditHistory(Timeline timeline);

  List<Uri>? getLinks({Timeline? timeline});
}

/// Vommet: one version of an edited message (see
/// [TimelineEventMessage.getEditHistory]).
class MessageVersion {
  const MessageVersion({required this.time, required this.body});
  final DateTime time;
  final String body;
}
