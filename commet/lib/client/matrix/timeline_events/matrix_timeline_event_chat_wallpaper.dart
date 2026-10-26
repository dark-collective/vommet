import 'package:commet/client/matrix/components/chat_wallpaper/matrix_chat_wallpaper_component.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_generic.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 746: "<user> changed the chat wallpaper" (or removed it), from
/// the wallpaper's state event.
class MatrixTimelineEventChatWallpaper extends MatrixTimelineEvent
    implements TimelineEventGeneric {
  MatrixTimelineEventChatWallpaper(super.event, {required super.client});

  String messageUserChangedChatWallpaper(String user) =>
      Intl.message("$user changed the chat wallpaper",
          desc: "Notice in a 1:1 chat when someone sets a new shared wallpaper",
          args: [user],
          name: "messageUserChangedChatWallpaper");

  String messageUserRemovedChatWallpaper(String user) => Intl.message(
      "$user removed the chat wallpaper",
      desc: "Notice in a 1:1 chat when someone removes the shared wallpaper",
      args: [user],
      name: "messageUserRemovedChatWallpaper");

  @override
  IconData get icon => Icons.wallpaper;

  @override
  String get plainTextBody => getBody();

  @override
  bool get showSenderAvatar => false;

  @override
  String getBody({Timeline? timeline}) {
    final name = event.senderFromMemoryOrFallback.displayName ?? event.senderId;
    return MatrixChatWallpaperComponent.currentEventId(event.content) != null
        ? messageUserChangedChatWallpaper(name)
        : messageUserRemovedChatWallpaper(name);
  }
}
