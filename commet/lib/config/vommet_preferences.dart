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
import 'package:shared_preferences/shared_preferences.dart';

mixin VommetPreferences {
  /// The loaded shared preferences, provided by [Preferences].
  SharedPreferences? get vommetSharedPreferences;

  /// Discord's unread pill beside spaces on the sidebar rail.
  final BoolPreference railUnreadMarks =
      BoolPreference("vommet_rail_unread_marks", defaultValue: true);
}
