// Vommet (Deep Search): Settings › Privacy › Search › "Remember recent
// searches". Kept beside the feature, not in preferences.dart.
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:intl/intl.dart';

/// Whether Deep Search keeps the last five searches (on this device only).
final BoolPreference deepSearchRecentPreference =
    BoolPreference("vommet_deep_search_recent", defaultValue: true);

/// The last searches, newest first (JSON, see DeepSearchRecentStore).
final StringListPreference deepSearchRecentListPreference =
    StringListPreference("vommet_deep_search_recent_list",
        defaultValue: const []);

String get deepSearchRecentSettingTitle =>
    Intl.message("Remember recent searches",
        name: "deepSearchRecentSettingTitle",
        desc: "Setting: Deep Search keeps the last few searches");

String get deepSearchRecentSettingDescription => Intl.message(
    "Deep Search shows your last 5 searches. They stay on this device.",
    name: "deepSearchRecentSettingDescription",
    desc: "Description of the Remember recent searches setting");
