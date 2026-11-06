import 'package:commet/client/components/quick_replies/quick_replies.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/pages/settings/categories/account/quick_replies/quick_replies_tab.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: "Save as quick reply" in the menu of your own text messages.
class QuickReplyMenu {
  static String get promptSaveAsQuickReply =>
      Intl.message("Save as quick reply",
          name: "promptSaveAsQuickReply",
          desc: "Menu option to keep one of your messages as a quick reply");

  static TimelineEventMenuEntry? entry(
      Room room, TimelineEvent event, void Function()? onActionFinished) {
    if (!QuickReplies.supported(room.client) ||
        event.status != TimelineEventStatus.synced ||
        event is! TimelineEventMessage ||
        event.senderId != room.client.self?.identifier) {
      return null;
    }
    final body = event.body;
    if (body == null || body.trim().isEmpty) return null;
    if (QuickReplies.of(room.client).length >= QuickReplies.maxItems) {
      return null;
    }
    return TimelineEventMenuEntry(
      name: promptSaveAsQuickReply,
      icon: Icons.bolt,
      action: (context) {
        onActionFinished?.call();
        QuickReplyEditor.show(context, room.client, initialBody: body);
      },
    );
  }
}
