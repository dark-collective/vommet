// Vommet (New Home step 2): the rail's shortcuts into Home. With the New
// Home experiment on, an optional People button under Home opens Home with
// People selected, and the existing # button ("Standalone rooms") opens
// Home with Rooms on its Standalone chip. Shared files only get one-line
// hooks into this file.
import 'dart:async';

import 'package:commet/config/layout_config.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/ui/atoms/rail_pill.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_store.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_model.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings › Appearance › "Add a People button" (New Home only). On for
/// new installs; installs that already had an account keep it off
/// (Preferences.keepOldDefaultsForExistingInstalls).
final BoolPreference peopleInRail =
    BoolPreference("vommet_people_in_rail", defaultValue: true);

String get labelHomeShortcuts => Intl.message("Shortcuts under Home",
    name: "labelHomeShortcuts",
    desc:
        "Heading over the settings for the optional sidebar buttons under Home (People, Standalone rooms)");

String get labelPeopleInRail => Intl.message("Add a People button",
    name: "labelPeopleInRail",
    desc:
        "Label for the toggle which adds a People button under Home in the sidebar");

String get labelPeopleInRailDescription => Intl.message(
    "Opens People: contacts, direct-message invites and blocked people. People is always in Home too.",
    name: "labelPeopleInRailDescription",
    desc:
        "Description for the toggle which adds a People button under Home in the sidebar");

String get labelShowRoomsInSidebar => Intl.message(
    "Add a “Standalone rooms” button",
    name: "labelShowRoomsInSidebar",
    desc:
        "Label for the toggle which shows an extra entry for rooms which are not contained in a space in the sidebar");

String get labelShowRoomsInSidebarDescription => Intl.message(
    "A # button for rooms that aren't part of a space.",
    name: "labelShowRoomsInSidebarDescription",
    desc:
        "Description for the toggle which shows an extra entry for rooms which are not contained in a space in the sidebar");

String get labelStandaloneRoomsAlwaysInHome => Intl.message(
    "They're always in Home › Rooms too.",
    name: "labelStandaloneRoomsAlwaysInHome",
    desc:
        "Added after the description of the Standalone rooms button setting when Home has a Rooms page");

String get labelStandaloneRoomsStillInHome => Intl.message(
    "Standalone rooms are still in Home › Rooms.",
    name: "labelStandaloneRoomsStillInHome",
    desc:
        "Starts the dialog shown when hiding the Standalone rooms sidebar button, when Home has a Rooms page");

String get labelHidePeopleButtonTitle => Intl.message("Hide the People button?",
    name: "labelHidePeopleButtonTitle",
    desc: "Title of the dialog shown when hiding the People sidebar button");

String get promptHidePeopleButtonReminder => Intl.message(
    "People is still in Home. You can turn the button back on in Settings › Appearance › Add a People button.",
    name: "promptHidePeopleButtonReminder",
    desc:
        "Shown when hiding the People sidebar button: where People still is, and where to turn the button back on");

String get promptHideThisButton => Intl.message("Hide this button",
    name: "promptHideThisButton",
    desc: "Context menu item which hides a button from the sidebar");

String get promptHideSidebarButton => Intl.message("Hide",
    name: "promptHideSidebarButton",
    desc: "Button to confirm hiding a sidebar button");

/// The hide dialog's text for the # button: [reminder] (where to turn it
/// back on), after a line saying where the rooms still are when Home has a
/// Rooms page.
String standaloneRoomsHideReminder(String reminder) =>
    newHomeEnabled ? "$labelStandaloneRoomsStillInHome $reminder" : reminder;

/// Asks, then hides the rail's People button.
Future<void> hidePeopleButton(BuildContext context) async {
  final confirmed = await AdaptiveDialog.confirmation(context,
      title: labelHidePeopleButtonTitle,
      prompt: promptHidePeopleButtonReminder,
      confirmationText: promptHideSidebarButton,
      cancelText: CommonStrings.promptCancel);
  if (confirmed == true) await peopleInRail.set(false);
}

/// Opens Home with [page] selected in the main area (on phones the main
/// panel slides in, like the column's rows).
void openNewHomePage(MainPageState state, NewHomePage page) {
  newHomePage.value = page;
  state.selectHome();
  if (MediaQuery.of(state.context).mobile) newHomeShowPage.add(page);
}

/// The # button's hook in [MainPageState.selectRoomsView]: with New Home on
/// it opens Home's Rooms page on the Standalone chip and returns true; off,
/// false (the old rooms view opens as before).
bool newHomeOpenRooms(MainPageState state) {
  if (!newHomeEnabled) return false;
  newHomeRoomsChip.value = RoomsChip.standalone;
  openNewHomePage(state, NewHomePage.rooms);
  return true;
}

/// Settings › Appearance › "Shortcuts under Home": the People button (with
/// New Home on) and the # "Standalone rooms" button. Follows the
/// preferences, so hiding a button from its menu shows here at once.
class HomeShortcutsSettings extends StatefulWidget {
  const HomeShortcutsSettings({super.key});

  @override
  State<HomeShortcutsSettings> createState() => _HomeShortcutsSettingsState();
}

class _HomeShortcutsSettingsState extends State<HomeShortcutsSettings> {
  late final List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();
    subs = [
      experimentNewHome.onChanged.listen((_) => rebuild()),
      peopleInRail.onChanged.listen((_) => rebuild()),
      preferences.showRoomsInSidebar.onChanged.listen((_) => rebuild()),
    ];
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    super.dispose();
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final newHome = newHomeEnabled;
    return tiamat.Panel(
      header: labelHomeShortcuts,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: Column(
          children: [
            if (newHome) ...[
              // Keyed by value: the toggle keeps its own copy of it.
              BooleanPreferenceToggle(
                key: ValueKey("people-in-rail-${peopleInRail.value}"),
                preference: peopleInRail,
                title: labelPeopleInRail,
                description: labelPeopleInRailDescription,
              ),
              const tiamat.Seperator(),
            ],
            BooleanPreferenceToggle(
              key: ValueKey(
                  "rooms-in-rail-${preferences.showRoomsInSidebar.value}"),
              preference: preferences.showRoomsInSidebar,
              title: labelShowRoomsInSidebar,
              description: newHome
                  ? "$labelShowRoomsInSidebarDescription "
                      "$labelStandaloneRoomsAlwaysInHome"
                  : labelShowRoomsInSidebarDescription,
            ),
          ],
        ),
      ),
    );
  }
}

/// The rail entries under Home, with New Home on: the People button (with
/// the received-invites badge), or that badge on Home when People is
/// hidden. Nothing with New Home off.
class NewHomeRailShortcuts extends StatefulWidget {
  const NewHomeRailShortcuts({super.key, this.onHomeSelected});

  /// The rail's Home callback, used when the main page can't be found.
  final void Function()? onHomeSelected;

  static const peopleKey = ValueKey("NewHomeRailPeople");

  @override
  State<NewHomeRailShortcuts> createState() => _NewHomeRailShortcutsState();
}

class _NewHomeRailShortcutsState extends State<NewHomeRailShortcuts> {
  final List<StreamSubscription> subs = [];

  @override
  void initState() {
    super.initState();
    subs.addAll([
      experimentNewHome.onChanged.listen((_) => rebuild()),
      peopleInRail.onChanged.listen((_) => rebuild()),
    ]);
    newHomePage.addListener(rebuild);
    NewHomeInvites.instance.count.addListener(rebuild);
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    newHomePage.removeListener(rebuild);
    NewHomeInvites.instance.count.removeListener(rebuild);
    super.dispose();
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!newHomeEnabled) return const SizedBox.shrink();
    final main = context.findAncestorStateOfType<MainPageState>();
    if (main != null) NewHomeInvites.instance.attach(main.clientManager);
    final count = NewHomeInvites.instance.count.value;
    final rail = RailMetrics.current;

    if (!peopleInRail.value) {
      if (count == 0) return const SizedBox.shrink();
      // Over Home's lower corner, without taking any room in the rail
      // (Home's top corner has the unread DMs badge).
      return SizedBox(
        width: rail.slot,
        height: 0,
        child: OverflowBox(
          alignment: Alignment.bottomCenter,
          minHeight: rail.slot,
          maxHeight: rail.slot,
          child: IgnorePointer(
            child: Align(
              key: const ValueKey("NewHomeRailHomeInvites"),
              alignment: Alignment.bottomRight,
              child: NotificationBadge(count),
            ),
          ),
        ),
      );
    }

    final selected = main != null &&
        main.currentView == MainPageSubView.home &&
        newHomePage.value == NewHomePage.people &&
        main.currentRoom == null;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SideNavigationBar.tooltip(
          "People",
          AdaptiveContextMenu(
            items: [
              tiamat.ContextMenuItem(
                text: promptHideThisButton,
                icon: Icons.visibility_off,
                onPressed: () => hidePeopleButton(context),
              ),
            ],
            child: Stack(clipBehavior: Clip.none, children: [
              RailSlot(
                unread: count > 0,
                inset: rail.sidePadding,
                child: tiamat.ImageButton(
                  key: NewHomeRailShortcuts.peopleKey,
                  size: rail.slot,
                  icon: Icons.people_alt_rounded,
                  semanticsLabel: "People",
                  onTap: () {
                    if (main == null) {
                      newHomePage.value = NewHomePage.people;
                      widget.onHomeSelected?.call();
                      return;
                    }
                    openNewHomePage(main, NewHomePage.people);
                  },
                ),
              ),
              // The selected pill, as a space's (RailSlot only grows it
              // for spaces).
              if (selected)
                Positioned(
                  left: -rail.sidePadding - rail.margin,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        key: const ValueKey("NewHomeRailPeopleSelected"),
                        width: RailSlot.width,
                        height: rail.pill(40),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface,
                          borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(RailSlot.width)),
                        ),
                      ),
                    ),
                  ),
                ),
              if (count > 0)
                Align(
                  alignment: AlignmentGeometry.topRight,
                  child: NotificationBadge(count),
                ),
            ]),
          ),
          context),
    );
  }
}
