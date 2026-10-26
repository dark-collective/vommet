import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet (experiment): what double-tapping (double-clicking) a message does.
final BoolPreference experimentDoubleTapAction =
    BoolPreference("vommet_experiment_double_tap", defaultValue: false);

/// "nothing", "react", "reply" or "edit"; empty = this device's default
/// (React on phones, Nothing on computers).
final StringPreference doubleTapActionPreference =
    StringPreference("vommet_double_tap_action", defaultValue: "");

/// The reaction a double-tap sends.
final StringPreference doubleTapReactionPreference =
    StringPreference("vommet_double_tap_reaction", defaultValue: "❤️");

enum DoubleTapAction {
  nothing,
  react,
  reply,
  edit;

  String get label => switch (this) {
        nothing => doubleTapActionNothing,
        react => doubleTapActionReact,
        reply => doubleTapActionReply,
        edit => doubleTapActionEdit,
      };

  /// The device's default: React on phones, Nothing on computers (a
  /// double-click there selects words).
  static DoubleTapAction platformDefault({required bool phone}) =>
      phone ? react : nothing;

  static DoubleTapAction parse(String value, {required bool phone}) =>
      values.where((a) => a.name == value).firstOrNull ??
      platformDefault(phone: phone);

  static bool get isPhone => PlatformUtils.isAndroid || PlatformUtils.isIOS;

  /// The chosen action (Nothing while the experiment is off).
  static DoubleTapAction get current {
    if (!experimentDoubleTapAction.value) return nothing;
    return parse(doubleTapActionPreference.value, phone: isPhone);
  }

  /// What a double-tap on one message does: Edit on someone else's message
  /// (or one that can't be edited) replies instead; an action the message
  /// doesn't take does nothing.
  static DoubleTapAction forMessage(DoubleTapAction chosen,
      {required bool canReact, required bool canReply, required bool canEdit}) {
    switch (chosen) {
      case nothing:
        return nothing;
      case react:
        return canReact ? react : nothing;
      case reply:
        return canReply ? reply : nothing;
      case edit:
        if (canEdit) return edit;
        return canReply ? reply : nothing;
    }
  }

  /// Whether two emoji are the same reaction (with or without the emoji
  /// variation selector, which clients add or drop: ❤️ and ❤).
  static bool sameEmoji(String a, String b) =>
      a.replaceAll("️", "") == b.replaceAll("️", "");

  /// Runs the chosen action on [event]. A second React removes our own
  /// reaction again.
  static void perform(BuildContext context,
      {required Timeline timeline,
      required TimelineEvent event,
      bool isThreadTimeline = false,
      Function(TimelineEvent? event)? setEditingEvent,
      Function(TimelineEvent? event)? setReplyingEvent}) {
    final chosen = current;
    if (chosen == nothing) return;
    final menu = TimelineEventMenu(
        timeline: timeline,
        event: event,
        context: context,
        isThreadTimeline: isThreadTimeline,
        setEditingEvent: setEditingEvent,
        setReplyingEvent: setReplyingEvent);
    TimelineEventMenuEntry? entry(IconData icon) => menu.primaryActions
        .where((a) => a.icon == icon && a.action != null)
        .firstOrNull;
    final editEntry = entry(Icons.edit);
    final replyEntry = entry(Icons.reply);

    switch (forMessage(chosen,
        canReact: menu.addReactionAction != null,
        canReply: replyEntry != null,
        canEdit: editEntry != null)) {
      case nothing:
        return;
      case reply:
        replyEntry!.action!(context);
      case edit:
        editEntry!.action!(context);
      case react:
        toggleReaction(timeline, event, doubleTapReactionPreference.value);
    }
  }

  static void toggleReaction(
      Timeline timeline, TimelineEvent event, String emoji) {
    final me = timeline.client.self?.identifier;
    if (event is TimelineEventFeatureReactions) {
      final reactions =
          (event as TimelineEventFeatureReactions).getReactions(timeline);
      for (final MapEntry(key: Emoticon emote, value: users)
          in reactions.entries) {
        if (sameEmoji(emote.key, emoji) && users.contains(me)) {
          timeline.room.removeReaction(event, emote);
          return;
        }
      }
    }
    timeline.room.addReaction(event, UnicodeEmoticon(emoji));
  }
}

String get doubleTapSettingsHeader => Intl.message("Double-tap",
    name: "doubleTapSettingsHeader",
    desc:
        "Header of the settings panel for what double-tapping a message does");

String get doubleTapSettingsTitle => Intl.message("Double-tap a message",
    name: "doubleTapSettingsTitle",
    desc:
        "Title of the setting that picks what double-tapping (or double-clicking) a message does");

String get doubleTapSettingsDescription => Intl.message(
    "Double-click on a computer. Edit replies to other people's messages.",
    name: "doubleTapSettingsDescription",
    desc: "Description of the double-tap setting");

String get doubleTapSettingsReactWith => Intl.message("React with",
    name: "doubleTapSettingsReactWith",
    desc:
        "Label of the emoji a double-tap reacts with, in the double-tap setting");

String get doubleTapActionNothing => Intl.message("Nothing",
    name: "doubleTapActionNothing",
    desc: "Double-tap setting choice: double-tapping a message does nothing");

String get doubleTapActionReact => Intl.message("React",
    name: "doubleTapActionReact",
    desc: "Double-tap setting choice: double-tapping a message reacts to it");

String get doubleTapActionReply => Intl.message("Reply",
    name: "doubleTapActionReply",
    desc: "Double-tap setting choice: double-tapping a message replies to it");

String get doubleTapActionEdit => Intl.message("Edit",
    name: "doubleTapActionEdit",
    desc:
        "Double-tap setting choice: double-tapping your own message edits it");
