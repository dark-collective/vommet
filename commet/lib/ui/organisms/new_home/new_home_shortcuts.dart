// Vommet (New Home step 2): the rail's shortcuts into Home. With the New
// Home experiment on, an optional People button under Home opens Home with
// People selected, and the existing # button ("Standalone rooms") opens
// Home with Rooms on its All chip. Shared files only get one-line
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
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/new_home/new_home_fallback.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_store.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
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

String get labelHomeShortcutsInCustomize => Intl.message(
    "Each Home tab can have its own button here. Choose them in Customize Home: open a tab's menu and pick Show in sidebar, or right-click a button to hide it.",
    name: "labelHomeShortcutsInCustomize",
    desc:
        "Shown in Appearance settings, with New Home on, where the sidebar shortcut settings used to be");

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

String labelHideTabButtonTitle(String tab) => Intl.message(
    "Hide the $tab button?",
    args: [tab],
    name: "labelHideTabButtonTitle",
    desc:
        "Title of the dialog shown when hiding a Home tab's sidebar button; tab is the tab's name, such as People");

String promptHideTabButtonReminder(String tab) => Intl.message(
    "$tab is still in Home. You can show the button again in Customize Home, from the tab's menu.",
    args: [tab],
    name: "promptHideTabButtonReminder",
    desc:
        "Shown when hiding a Home tab's sidebar button: the tab is still in Home, and where to turn the button back on; tab is the tab's name");

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

/// Asks, then hides Home tab [tab]'s sidebar button.
Future<void> hideTabButton(BuildContext context, HomeTab tab) async {
  final confirmed = await AdaptiveDialog.confirmation(context,
      title: labelHideTabButtonTitle(tab.name),
      prompt: promptHideTabButtonReminder(tab.name),
      confirmationText: promptHideSidebarButton,
      cancelText: CommonStrings.promptCancel);
  if (confirmed == true) await setTabInRail(tab.id, false);
}

/// Opens Home on the tab holding [type] (a whole page such as People, or a
/// card); on phones the main panel slides in. When no tab holds it, it
/// opens on its own page (with "Add it to a tab").
void openHomeBlock(MainPageState state, String type) {
  HomeLayoutStore.instance.attach(state.clientManager);
  if (!HomeLayoutStore.instance.showTabHolding(type)) {
    showBlockFallback(state.clientManager, type,
        onAdded: () => openHomeBlock(state, type));
    return;
  }
  state.selectHome();
  if (MediaQuery.of(state.context).mobile) {
    newHomeShowPage.add(newHomeTab.value);
  }
}

/// Whether the sidebar shows a button for Home tab [tab] (New Home on).
/// Chosen per tab in Customize Home; a tab never set follows the older
/// settings first-run setup asks about (People, and # for Rooms).
bool tabInRail(HomeTab tab) =>
    tab.rail ??
    switch (tab.id) {
      HomeTabs.people => peopleInRail.value,
      HomeTabs.rooms => preferences.showRoomsInSidebar.value,
      _ => false,
    };

/// Shows or hides tab [id]'s sidebar button. The default People and Rooms
/// tabs also keep their older settings in step (first-run setup shows them).
Future<void> setTabInRail(String id, bool on) async {
  final store = HomeLayoutStore.instance;
  final tab = store.tabs.value.tab(id);
  if (tab == null) return;
  await store.saveTabs(store.tabs.value.replaceTab(tab.copyWith(rail: on)));
  if (id == HomeTabs.people) await peopleInRail.set(on);
  if (id == HomeTabs.rooms) await preferences.showRoomsInSidebar.set(on);
}

/// Whether the rail shows the classic # "Standalone rooms" button: switched
/// on, with New Home off (with New Home on, Home's tabs have their own
/// buttons).
bool get roomsShortcutShown =>
    preferences.showRoomsInSidebar.value && !newHomeEnabled;

/// Fires when [roomsShortcutShown] may change with New Home switched.
Stream<void> get roomsShortcutChanged =>
    experimentNewHome.onChanged.map((_) {});

/// The # button's hook in [MainPageState.selectRoomsView]: with New Home on
/// it opens Home's Rooms page on the All chip and returns true; off, false
/// (the old rooms view opens as before).
bool newHomeOpenRooms(MainPageState state) {
  if (!newHomeEnabled) return false;
  newHomeRoomsChip.value = RoomsChip.all;
  openHomeBlock(state, HomeLayout.roomsPage);
  return true;
}

/// The rail's Home button, with New Home on: Home opens on its first tab
/// (Overview by default), not on the last one shown (Vommet issue 609).
void newHomeShowFirstTab() {
  if (!newHomeEnabled) return;
  newHomeTab.value = HomeLayoutStore.instance.tabs.value.tabs.first.id;
}

/// The Home tab whose sidebar button is lit while Home is open: the shown
/// tab, when it has a button; null lights Home's (Vommet issue 609). It
/// stays lit while a room opened from the tab's side list is open, as that
/// list stays on screen (Vommet issue 628).
String? homeRailLitTab() {
  final tab = HomeLayoutStore.instance.tabs.value.tab(newHomeTab.value);
  return tab != null && tabInRail(tab) ? tab.id : null;
}

/// Whether the rail's Home button shows the selected pill (Vommet issue
/// 609): Home is open with New Home on, and the shown tab's own button
/// isn't lit instead ([homeRailLitTab]).
bool homeRailSelected(MainPageState? main) {
  if (!newHomeEnabled || main == null) return false;
  if (main.currentView != MainPageSubView.home) return false;
  return homeRailLitTab() == null;
}

/// Builds the rail's Home button with [homeRailSelected]. Follows the shown
/// Home tab and the tabs; the main page rebuilds the rail when the view or
/// the room changes.
class HomeRailSelection extends StatelessWidget {
  const HomeRailSelection({required this.builder, super.key});

  final Widget Function(BuildContext context, bool selected) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([newHomeTab, HomeLayoutStore.instance.tabs]),
      builder: (context, _) => builder(context,
          homeRailSelected(context.findAncestorStateOfType<MainPageState>())),
    );
  }
}

/// Settings › Appearance › "Shortcuts under Home": with New Home on, where
/// to find the tabs' sidebar buttons (Customize Home); off, the classic
/// # "Standalone rooms" button. Follows the
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
    // With New Home on, every Home tab has its own "Show in sidebar"
    // switch in Customize Home instead.
    final newHome = newHomeEnabled;
    return tiamat.Panel(
      header: labelHomeShortcuts,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: newHome
            ? Padding(
                key: const ValueKey("HomeShortcutsInCustomize"),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: tiamat.Text.labelLow(labelHomeShortcutsInCustomize),
              )
            : BooleanPreferenceToggle(
                key: ValueKey(
                    "rooms-in-rail-${preferences.showRoomsInSidebar.value}"),
                preference: preferences.showRoomsInSidebar,
                title: labelShowRoomsInSidebar,
                description: labelShowRoomsInSidebarDescription,
              ),
      ),
    );
  }
}

/// The rail entries under Home, with New Home on: a button for each Home
/// tab with "Show in sidebar"
/// on (its icon and name; the tab holding People carries that badge too).
/// Nothing with New Home off.
class NewHomeRailShortcuts extends StatefulWidget {
  const NewHomeRailShortcuts({super.key, this.onHomeSelected});

  /// The rail's Home callback, used when the main page can't be found.
  final void Function()? onHomeSelected;

  /// The People tab's button.
  static const peopleKey = ValueKey("NewHomeRailPeople");

  static Key keyOf(String tabId) =>
      tabId == HomeTabs.people ? peopleKey : ValueKey("NewHomeRailTab-$tabId");

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
      preferences.showRoomsInSidebar.onChanged.listen((_) => rebuild()),
    ]);
    newHomeTab.addListener(rebuild);
    HomeLayoutStore.instance.tabs.addListener(rebuild);
    NewHomeInvites.instance.badge.addListener(rebuild);
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    newHomeTab.removeListener(rebuild);
    HomeLayoutStore.instance.tabs.removeListener(rebuild);
    NewHomeInvites.instance.badge.removeListener(rebuild);
    super.dispose();
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!newHomeEnabled) return const SizedBox.shrink();
    final main = context.findAncestorStateOfType<MainPageState>();
    if (main != null) {
      NewHomeInvites.instance.attach(main.clientManager);
      HomeLayoutStore.instance.attach(main.clientManager);
    }
    final count = NewHomeInvites.instance.badge.value;
    final tabs = HomeLayoutStore.instance.tabs.value;
    final peopleTab = tabs.tabHolding(HomeLayout.peoplePage)?.id;

    // People counts invites and unread DMs (Vommet issues 550, 654).
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final tab in tabs.tabs)
        if (tabInRail(tab))
          _TabRailButton(
            tab: tab,
            main: main,
            badge: tab.id == peopleTab ? count : 0,
            onHomeSelected: widget.onHomeSelected,
          ),
    ]);
  }
}

/// A Home tab's sidebar button: the tab's icon in a rail slot (themed like
/// the rail's other buttons), its name as the tooltip, the selected pill
/// while Home shows that tab, and "Hide this button" on right-click.
class _TabRailButton extends StatelessWidget {
  const _TabRailButton(
      {required this.tab,
      required this.main,
      required this.badge,
      this.onHomeSelected});

  final HomeTab tab;
  final MainPageState? main;
  final int badge;
  final void Function()? onHomeSelected;

  void open() {
    // The Rooms page opens on All, which lists standalone rooms first and
    // searches every room and space (Vommet issue 610).
    if (tab.holds(HomeLayout.roomsPage)) newHomeRoomsChip.value = RoomsChip.all;
    final main = this.main;
    if (main == null) {
      newHomeTab.value = tab.id;
      onHomeSelected?.call();
      return;
    }
    HomeLayoutStore.instance.attach(main.clientManager);
    final opensPage = newHomePickOpensPage(main, tab.id);
    newHomeTab.value = tab.id;
    main.selectHome();
    if (MediaQuery.of(main.context).mobile && opensPage) {
      newHomeShowPage.add(tab.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rail = RailMetrics.current;
    final main = this.main;
    final selected = main != null &&
        main.currentView == MainPageSubView.home &&
        homeRailLitTab() == tab.id;
    final pillKey = tab.id == HomeTabs.people
        ? const ValueKey("NewHomeRailPeopleSelected")
        : ValueKey("NewHomeRailTabSelected-${tab.id}");

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SideNavigationBar.tooltip(
          tab.name,
          AdaptiveContextMenu(
            items: [
              tiamat.ContextMenuItem(
                text: promptHideThisButton,
                icon: Icons.visibility_off,
                onPressed: () => hideTabButton(context, tab),
              ),
            ],
            child: Stack(clipBehavior: Clip.none, children: [
              RailSlot(
                unread: badge > 0,
                inset: rail.sidePadding,
                child: tiamat.ImageButton(
                  key: NewHomeRailShortcuts.keyOf(tab.id),
                  size: rail.slot,
                  icon: homeTabIcon(tab.icon),
                  semanticsLabel: tab.name,
                  onTap: open,
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
                        key: pillKey,
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
              if (badge > 0)
                Align(
                  alignment: AlignmentGeometry.topRight,
                  child: NotificationBadge(badge),
                ),
            ]),
          ),
          context),
    );
  }
}
