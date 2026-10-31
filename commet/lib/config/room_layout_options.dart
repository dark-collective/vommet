// Vommet: the "Rooms and spaces" options in Settings › Appearance › Layout.
// They were one "Discord-style layout" switch (an experiment until 10-25,
// key vommet_experiment_banner_layout); now each is its own setting. They are
// not part of a layout style: picking Discord or Telegram style leaves them
// alone, and changing one doesn't make the layout Custom.
//
// Migration: while one of these has never been set, it follows the stored
// old switch (on unless it was switched off), so existing setups carry over
// and anyone who had the old switch off gets all seven off.
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';

bool _oldSwitch() => preferences.experimentBannerLayout.value;

/// A room or space banner folds into its name bar when you scroll down.
final BoolPreference shrinkBannersOnScroll = BoolPreference(
  "vommet_rooms_shrink_banners",
  defaultValue: true,
  defaultGetter: _oldSwitch,
);

/// The member list is grouped into Online and Offline (within roles); off
/// groups by role only.
final BoolPreference memberListOnlineSections = BoolPreference(
  "vommet_rooms_member_list_online",
  defaultValue: true,
  defaultGetter: _oldSwitch,
);

/// "In voice" and "Sharing their screen" under names in the member list.
final BoolPreference memberListCallActivity = BoolPreference(
  "vommet_rooms_show_call_activity",
  defaultValue: true,
  defaultGetter: _oldSwitch,
);

/// The member panel has tabs (Members, Media, Files, Pins…) and the room
/// header keeps only Invite, Call and Search, the rest in the ▾ menu. DMs
/// always have the tabs.
final BoolPreference memberPanelTabs = BoolPreference(
  "vommet_rooms_member_tabs",
  defaultValue: true,
  defaultGetter: _oldSwitch,
);

/// The room list and member list edges can be dragged to resize them.
final BoolPreference resizablePanels = BoolPreference(
  "vommet_rooms_resize_panels",
  defaultValue: true,
  defaultGetter: _oldSwitch,
);

/// A space's home page lists its rooms like the room list; off shows cards.
final BoolPreference spaceHomeLikeRoomList = BoolPreference(
  "vommet_rooms_space_home_list",
  defaultValue: true,
  defaultGetter: _oldSwitch,
);

/// The Home button badge also counts unread direct messages.
final BoolPreference homeBadgeCountsDms = BoolPreference(
  "vommet_rooms_home_dm_badge",
  defaultValue: true,
  defaultGetter: _oldSwitch,
);

/// All seven, in the order the Layout settings show them.
List<BoolPreference> get roomLayoutOptions => [
      shrinkBannersOnScroll,
      memberListOnlineSections,
      memberListCallActivity,
      memberPanelTabs,
      resizablePanels,
      spaceHomeLikeRoomList,
      homeBadgeCountsDms,
    ];
