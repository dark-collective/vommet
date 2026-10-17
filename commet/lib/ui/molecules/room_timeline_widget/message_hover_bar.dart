import 'package:commet/config/preferences/string_preference.dart';
import 'package:intl/intl.dart';

/// Vommet: what shows over a message when you point at it on desktop
/// (Settings › Appearance › Message actions on hover). Right-click opens
/// every action whichever is picked.
enum MessageHoverBar {
  /// Upstream's bar: recent reactions, add reaction, actions and more,
  /// floating above the message. The default.
  full,

  /// Add reaction, reply and more, tucked into the message's own corner so
  /// the message above stays readable.
  compact,

  /// No bar.
  off;

  static MessageHoverBar parse(String value) => MessageHoverBar.values
      .firstWhere((m) => m.name == value, orElse: () => MessageHoverBar.full);

  /// Kept here rather than in preferences.dart so no other topic's edits
  /// there can conflict with it.
  static final StringPreference preference = StringPreference(
      "vommet_message_hover_bar",
      defaultValue: MessageHoverBar.full.name);

  static MessageHoverBar get current => parse(preference.value);

  String get label => switch (this) {
        full => Intl.message("Full",
            name: "messageHoverBarFull",
            desc: "Setting choice: the full bar of reactions and actions "
                "over a message you point at"),
        compact => Intl.message("Compact",
            name: "messageHoverBarCompact",
            desc: "Setting choice: a small bar of three icons in the corner "
                "of a message you point at"),
        off => Intl.message("Off",
            name: "messageHoverBarOff",
            desc: "Setting choice: no bar over a message you point at"),
      };

  String get description => switch (this) {
        full => Intl.message(
            "Recent reactions and every action, floating above the message.",
            name: "messageHoverBarFullDescription",
            desc: "Explains the Full choice of the message hover bar setting"),
        compact => Intl.message(
            "Add reaction, reply and more, in the message's corner. "
            "Nothing above it is covered.",
            name: "messageHoverBarCompactDescription",
            desc: "Explains the Compact choice of the message hover bar "
                "setting"),
        off => Intl.message("No bar. Right-click a message for its actions.",
            name: "messageHoverBarOffDescription",
            desc: "Explains the Off choice of the message hover bar setting"),
      };
}
