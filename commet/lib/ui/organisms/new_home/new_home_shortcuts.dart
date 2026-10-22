// Vommet (New Home step 2): the rail's shortcuts into Home. With the New
// Home experiment on, an optional People button under Home opens Home with
// People selected, and the existing # button ("rooms outside spaces") opens
// Home with Rooms on its Standalone chip. Shared files only get one-line
// hooks into this file.
import 'dart:async';

import 'package:commet/config/layout_config.dart';
import 'package:commet/config/preferences/bool_preference.dart';
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
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings › Appearance: "People button in the sidebar" (New Home only).
final BoolPreference peopleInRail =
    BoolPreference("vommet_people_in_rail", defaultValue: false);

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

/// Appearance settings' People toggle, shown with New Home on.
List<Widget> newHomeRailSettings() => [
      if (newHomeEnabled) ...[
        BooleanPreferenceToggle(
          preference: peopleInRail,
          title: "People button in the sidebar",
          description:
              "A button under Home that opens People (contacts, invites, blocked)",
        ),
        const tiamat.Seperator(),
      ],
    ];

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
                text: "Hide this button",
                icon: Icons.visibility_off,
                onPressed: () => peopleInRail.set(false),
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
