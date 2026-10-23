// Vommet: how tightly messages are packed in a room (Vommet issue 524).
// Kept beside the feature, not in preferences.dart, so this topic doesn't
// touch a file most topics edit.
import 'package:commet/config/preferences/string_preference.dart';
import 'package:intl/intl.dart';

enum MessageDensity {
  /// The usual spacing.
  cozy,

  /// Less space between messages and smaller profile pictures, so more
  /// messages fit on screen.
  compact;

  static MessageDensity parse(String value) =>
      values.where((d) => d.name == value).firstOrNull ?? cozy;

  String get label => switch (this) {
        cozy => messageDensityCozy,
        compact => messageDensityCompact,
      };

  String get description => switch (this) {
        cozy => messageDensityCozyDescription,
        compact => messageDensityCompactDescription,
      };

  /// Space above and below each message.
  double get verticalPadding => this == compact ? 0.5 : 2;

  /// Size of the sender's profile picture beside a message.
  double get avatarSize => this == compact ? 24 : 32;

  /// Space above the first bubble of a run (bubble layout).
  double get groupGap => this == compact ? 3 : 6;

  /// Space above reactions, and around a thread card.
  double get innerGap => this == compact ? 2 : 4;
}

final StringPreference messageDensityPreference = StringPreference(
    "vommet_message_density",
    defaultValue: MessageDensity.cozy.name);

MessageDensity get messageDensity =>
    MessageDensity.parse(messageDensityPreference.value);

String get messageDensityTitle => Intl.message("Message spacing",
    name: "messageDensityTitle",
    desc: "Title of the setting that picks how tightly messages are packed");

String get messageDensityCozy => Intl.message("Cozy",
    name: "messageDensityCozy",
    desc: "Message spacing option: the usual, roomier spacing");

String get messageDensityCompact => Intl.message("Compact",
    name: "messageDensityCompact",
    desc: "Message spacing option: tighter spacing, more messages on screen");

String get messageDensityCozyDescription =>
    Intl.message("Room between messages and larger profile pictures.",
        name: "messageDensityCozyDescription",
        desc: "Describes the Cozy message spacing option");

String get messageDensityCompactDescription => Intl.message(
    "Less space between messages and smaller profile pictures, so more fit on screen.",
    name: "messageDensityCompactDescription",
    desc: "Describes the Compact message spacing option");
