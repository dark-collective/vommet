import 'package:commet/config/preferences/bool_preference.dart';

/// Vommet experiment: your own nickname per space and per room. Off: the
/// settings panels are hidden and nothing writes member events (rules you
/// saved stay in account data, unused). Kept here instead of preferences.dart
/// so this topic doesn't touch that busy file.
final experimentSpaceNicknames =
    BoolPreference("vommet_experiment_space_nicknames", defaultValue: false);

/// Vommet experiment: name safety. A sender whose name looks like another
/// member's or a contact's, or who uses the same picture file, shows their
/// Matrix ID after the name. On by default: other apps can already set any
/// name in a room.
final experimentNameSafety =
    BoolPreference("vommet_experiment_name_safety", defaultValue: true);
