// Vommet: the fork's own preferences live here, mixed into upstream's
// [Preferences] class with one `with` clause, so `preferences.someSetting`
// keeps working while upstream's file stays (nearly) untouched. Commet's
// preferences.dart is the file most of our topics used to edit, and every
// rebase onto upstream or restack of a topic could conflict there; a field
// added in this file never does.
//
// Rules (see .vommet/README.md, "Where fork code goes"):
// - New Vommet-only preferences go here, not in preferences.dart.
// - Preferences that topics already added to preferences.dart move here as
//   those topics land on main, each move a pure relocation.
// - Upstream state is reached through [vommetSharedPreferences]; never add
//   another hook to the upstream class for a preference.

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

mixin VommetPreferences {
  /// The loaded shared preferences, provided by [Preferences].
  SharedPreferences? get vommetSharedPreferences;

  /// Discord's unread pill beside spaces on the sidebar rail.
  final BoolPreference railUnreadMarks =
      BoolPreference("vommet_rail_unread_marks", defaultValue: true);

  /// Redacted mode (Vommet issue 400), behind its experiment. The switches
  /// are read through `RedactionPreferences` (utils/redaction/).
  final BoolPreference experimentRedactedMode =
      BoolPreference("vommet_experiment_redacted_mode", defaultValue: false);

  final BoolPreference redactionEnabled =
      BoolPreference("vommet_redaction_enabled", defaultValue: false);

  final StringPreference redactionNames =
      StringPreference("vommet_redaction_names", defaultValue: "hide");

  final BoolPreference redactionAvatars =
      BoolPreference("vommet_redaction_avatars", defaultValue: true);

  final StringPreference redactionText =
      StringPreference("vommet_redaction_text", defaultValue: "keep");

  final BoolPreference redactionDistinguishable =
      BoolPreference("vommet_redaction_distinguishable", defaultValue: true);

  final BoolPreference redactionRoomNames =
      BoolPreference("vommet_redaction_room_names", defaultValue: true);

  final BoolPreference redactionImages =
      BoolPreference("vommet_redaction_images", defaultValue: false);

  /// The clock for times in the app: "system", "twelveHour" or
  /// "twentyFourHour" (`ClockStyle` in utils/clock_format.dart).
  final StringPreference clockFormat =
      StringPreference("vommet_clock_format", defaultValue: "system");
}
