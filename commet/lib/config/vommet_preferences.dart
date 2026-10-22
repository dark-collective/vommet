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
import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:commet/config/preferences/string_list_preference.dart';

mixin VommetPreferences {
  /// The loaded shared preferences, provided by [Preferences].
  SharedPreferences? get vommetSharedPreferences;

  /// Domains whose web links open without the Open Link prompt (Vommet
  /// issue 503), read through `TrustedLinkDomains` (utils/links/).
  final StringListPreference trustedLinkDomains =
      StringListPreference("vommet_trusted_link_domains", defaultValue: []);

  /// Discord's unread pill beside spaces on the sidebar rail.
  final BoolPreference railUnreadMarks =
      BoolPreference("vommet_rail_unread_marks", defaultValue: true);

  /// The sidebar rail's icon size in px (Vommet issue 506); see `RailMetrics`.
  final DoublePreference sidebarIconSize =
      DoublePreference("vommet_sidebar_icon_size", defaultValue: 56);

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

  /// Chat-bubble message layout (Vommet issue 421), off by default.
  final BoolPreference chatBubbleLayout =
      BoolPreference("vommet_chat_bubble_layout", defaultValue: false);

  /// The People button under Home on the sidebar rail (Vommet issue 580):
  /// every direct message in one list, in place of a picture per unread DM.
  final BoolPreference peopleInRail =
      BoolPreference("vommet_people_in_rail", defaultValue: true);
}
