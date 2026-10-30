import 'dart:convert';

import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_room_permissions.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_mixin_per_message_profile.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_generic.dart';
import 'package:commet/client/timeline_events/timeline_event_redactable_body.dart';
import 'package:commet/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixTimelineEventEmote extends MatrixTimelineEvent
    with MatrixTimelineEventPerMessageProfile
    implements
        TimelineEventEmote,
        TimelineEventGeneric,
        TimelineEventRedactableBody {
  MatrixTimelineEventEmote(super.event, {required super.client});

  @override
  bool get editable => true;

  String messageUserEmote(String user, String emote) =>
      Intl.message("*$user $emote",
          desc: "Message to display when a user does a custom emote (/me)",
          args: [user, emote],
          name: "messageUserEmote");

  String messageUserEmoteViaProfile(String user, String emote, String sender) =>
      Intl.message("*$user $emote (via $sender)",
          desc:
              "Message to display when a user does a custom emote (/me) with a per message profile",
          args: [user, emote, sender],
          name: "messageUserEmoteViaProfile");

  @override
  String getBody({Timeline? timeline}) =>
      _withSender(_getEmoteBody(timeline: timeline), timeline: timeline);

  // Vommet issue 475: redacted mode draws the emote as plain text.
  @override
  String redactedBody(String Function(String name, String userId) nameOf,
      String Function(String text) textOf) {
    final sender = nameOf(
        event.senderFromMemoryOrFallback.displayName ?? event.senderId,
        event.senderId);
    final body = textOf(_getEmoteBody());
    final profile = getPerMessageProfile();
    if (profile?.hasDisplayName == true) {
      return messageUserEmoteViaProfile(
          nameOf(profile!.displayName!, event.senderId), body, sender);
    }
    return messageUserEmote(sender, body);
  }

  /// "*name body", or "*name body (via sender)" for a per-message profile.
  /// [escape] is applied to the names (for an HTML body).
  String _withSender(String body,
      {Timeline? timeline, String Function(String)? escape}) {
    String? sender = event.senderId.localpart;

    if (timeline != null) {
      sender = timeline.room.getMemberOrFallback(event.senderId).displayName;
    }

    escape ??= (s) => s;

    var profile = getPerMessageProfile(timeline: timeline);
    if (profile?.hasDisplayName == true && sender != null) {
      return messageUserEmoteViaProfile(
          escape(profile!.displayName!), body, escape(sender));
    }

    if (sender != null) {
      return messageUserEmote(escape(sender), body);
    }

    return body;
  }

  /// Vommet issue 325: the emote as HTML, its `formatted_body` (as last
  /// edited) after the sender's name, or null when it has none, like a
  /// plain-text message.
  String? getFormattedBody({Timeline? timeline}) {
    var e = getDisplayEvent(timeline);
    if (!MatrixTimelineEventMessage.usesFormattedBody(
        e.messageType, e.content, e.formattedText)) {
      return null;
    }

    var html = e.formattedText.isEmpty
        ? const HtmlEscape(HtmlEscapeMode.element).convert(e.plaintextBody)
        : e.formattedText;
    return _withSender(stripFallbackHtml(html, timeline: timeline),
        timeline: timeline,
        escape: const HtmlEscape(HtmlEscapeMode.element).convert);
  }

  @override
  Widget buildFormattedContent({Timeline? timeline}) {
    var room = client.getRoom(event.roomId!);
    var html = getFormattedBody(timeline: timeline);
    if (html == null || room is! MatrixRoom) {
      return PlaintextMessageBody(
        content: getBody(timeline: timeline),
        clientIdentifier: client.identifier,
      );
    }

    var e = getDisplayEvent(timeline);
    bool mentionsRoom = e.content.tryGetMap("m.mentions")?["room"] == true &&
        MatrixRoomPermissions.canUserMentionRoom(e.senderId, room.matrixRoom);

    return MatrixHtmlParser.parse(html, client, room,
        mentionsRoom: mentionsRoom);
  }

  @override
  String getPlaintextBody(Timeline timeline) =>
      _getEmoteBody(timeline: timeline);

  String _getEmoteBody({Timeline? timeline}) =>
      stripFallback(getDisplayEvent(timeline).body, timeline: timeline);

  @override
  matrix.Event getPerMessageProfileSource({Timeline? timeline}) =>
      getDisplayEvent(timeline);

  @override
  IconData? get icon => null;

  @override
  bool get showSenderAvatar => true;
}
