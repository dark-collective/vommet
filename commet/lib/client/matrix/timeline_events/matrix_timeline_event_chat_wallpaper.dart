import 'package:commet/client/matrix/components/chat_wallpaper/matrix_chat_wallpaper_component.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_generic.dart';
import 'package:commet/client/timeline_events/timeline_event_redactable_body.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 746: "<user> changed the chat wallpaper" (or removed it), from
/// the wallpaper's state event.
class MatrixTimelineEventChatWallpaper extends MatrixTimelineEvent
    implements TimelineEventGeneric, TimelineEventRedactableBody {
  MatrixTimelineEventChatWallpaper(super.event, {required super.client});

  String messageUserChangedChatWallpaper(String user) => Intl.message(
      "$user changed the chat wallpaper",
      desc: "Notice in a chat when someone sets a new wallpaper for everyone",
      args: [user],
      name: "messageUserChangedChatWallpaper");

  String messageUserRemovedChatWallpaper(String user) => Intl.message(
      "$user removed the chat wallpaper",
      desc: "Notice in a chat when someone removes the wallpaper everyone sees",
      args: [user],
      name: "messageUserRemovedChatWallpaper");

  @override
  IconData get icon => Icons.wallpaper;

  @override
  String get plainTextBody => getBody();

  @override
  bool get showSenderAvatar => false;

  @override
  String getBody({Timeline? timeline}) => _bodyFor(_senderName);

  @override
  String redactedBody(String Function(String name, String userId) nameOf,
          String Function(String text) textOf) =>
      _bodyFor(nameOf(_senderName, event.senderId));

  String get _senderName =>
      event.senderFromMemoryOrFallback.displayName ?? event.senderId;

  String _bodyFor(String name) {
    return MatrixChatWallpaperComponent.currentEventId(event.content) != null
        ? messageUserChangedChatWallpaper(name)
        : messageUserRemovedChatWallpaper(name);
  }
}
