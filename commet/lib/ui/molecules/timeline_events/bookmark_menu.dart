import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: "Save message" in a message's menu; once saved, "Edit saved
/// tags" and "Remove from saved". Saved messages are listed under the room
/// header's bookmark.
class BookmarkMenu {
  static String get promptSaveMessage => Intl.message("Save message",
      name: "promptSaveMessage",
      desc: "Menu option to bookmark a message in your saved messages");

  static String get promptEditSavedTags => Intl.message("Edit saved tags",
      name: "promptEditSavedTags",
      desc: "Menu option to change the tags and note of a saved message");

  static String get promptRemoveFromSaved => Intl.message("Remove from saved",
      name: "promptRemoveFromSaved",
      desc: "Menu option to remove a message from your saved messages");

  static List<TimelineEventMenuEntry> entries(
      Room room, TimelineEvent event, void Function()? onActionFinished) {
    if (!Bookmarks.supported(room.client) ||
        event.status != TimelineEventStatus.synced ||
        !(event is TimelineEventMessage ||
            event is TimelineEventSticker ||
            event is TimelineEventEmote)) {
      return const [];
    }
    final client = room.client;
    final roomId = room.identifier;
    final eventId = event.eventId;
    if (!Bookmarks.isSaved(client, roomId, eventId)) {
      return [
        TimelineEventMenuEntry(
          name: promptSaveMessage,
          icon: Icons.bookmark_add_outlined,
          action: (context) {
            onActionFinished?.call();
            BookmarkTagEditor.show(context, client, roomId, eventId,
                saveNow: true);
          },
        ),
      ];
    }
    return [
      TimelineEventMenuEntry(
        name: promptEditSavedTags,
        icon: Icons.sell_outlined,
        action: (context) {
          onActionFinished?.call();
          BookmarkTagEditor.show(context, client, roomId, eventId);
        },
      ),
      TimelineEventMenuEntry(
        name: promptRemoveFromSaved,
        icon: Icons.bookmark_remove_outlined,
        action: (context) {
          Bookmarks.remove(client, roomId, eventId);
          onActionFinished?.call();
        },
      ),
    ];
  }
}
