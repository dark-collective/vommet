// Vommet: the switch for the Friends tab on Home (Vommet issue 93). Kept
// beside the feature, not in preferences.dart, so this topic doesn't touch a
// file most topics edit.
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/utils/event_bus.dart';

final BoolPreference experimentFriendsTab =
    BoolPreference("vommet_experiment_friends_tab", defaultValue: false);

bool get friendsTabEnabled => experimentFriendsTab.value;

/// Opens Home again so the tab bar appears or goes straight away.
void onFriendsTabToggled(bool _) => EventBus.openHomeScreen.add(null);
