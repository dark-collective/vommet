import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/ui/organisms/new_home/new_home_live_calls.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/utils/mark_all_read.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/ui/atoms/rail_pill.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:commet/ui/molecules/space_selector.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar_direct_messages.dart';
import 'package:commet/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:commet/ui/pages/room_directory/directory_strings.dart';
import 'package:commet/ui/pages/room_directory/room_directory_launcher.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:commet/config/room_layout_options.dart';

class SideNavigationBar extends StatefulWidget {
  const SideNavigationBar(
      {super.key,
      this.currentUser,
      this.onSpaceSelected,
      this.onDirectMessageSelected,
      this.onSettingsSelected,
      this.onHomeSelected,
      this.extraEntryBuilders,
      this.onRoomsViewSelected,
      this.clearSpaceSelection});

  static ValueKey settingsKey =
      const ValueKey("SIDE_NAVIGATION_SETTINGS_BUTTON");

  final List<Widget Function(double width)>? extraEntryBuilders;

  final Profile? currentUser;
  final void Function(Space space)? onSpaceSelected;
  final void Function()? clearSpaceSelection;
  final void Function(Room room)? onDirectMessageSelected;
  final void Function()? onHomeSelected;
  final void Function()? onSettingsSelected;
  final void Function()? onRoomsViewSelected;

  @override
  State<SideNavigationBar> createState() => _SideNavigationBarState();

  static Widget tooltip(String text, Widget child, BuildContext context) {
    // Vommet: the icon buttons here have no text, and the tooltip is never
    // shown on mobile, so screen readers only said "Button" (Vommet issue
    // 308). Read the tooltip's text, with any badge, as one button.
    child = MergeSemantics(child: Semantics(label: text, child: child));

    if (MediaQuery.of(context).mobile) {
      return AspectRatio(
        aspectRatio: 1.0,
        child: child,
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: JustTheTooltip(
          content: Padding(
            padding: const EdgeInsets.all(8.0),
            child: tiamat.Text(text),
          ),
          preferredDirection: AxisDirection.right,
          offset: 5,
          tailLength: 5,
          tailBaseWidth: 5,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: child),
    );
  }
}

class _SideNavigationBarState extends State<SideNavigationBar> {
  late ClientManager _clientManager;

  late List<StreamSubscription> subs;

  String get promptAddRoomOrSpace => Intl.message("Add Room or Space",
      name: "promptAddRoomOrSpace",
      desc: "Prompt to create or join a room or space");

  // Vommet: the # "Standalone rooms" button, and hiding it from its menu
  String get labelRoomsOutsideSpaces => Intl.message("Standalone rooms",
      name: "labelRoomsOutsideSpaces",
      desc:
          "Tooltip for the sidebar button which lists rooms that are not in any space");

  String get promptHideRoomsOutsideSpaces => Intl.message("Hide this button",
      name: "promptHideRoomsOutsideSpaces",
      desc:
          "Context menu item which hides the 'Standalone rooms' button from the sidebar");

  String get labelHideRoomsOutsideSpacesTitle => Intl.message(
      "Hide the “Standalone rooms” button?",
      name: "labelHideRoomsOutsideSpacesTitle",
      desc:
          "Title of the dialog shown when hiding the 'Standalone rooms' sidebar button");

  String get promptHideRoomsOutsideSpacesReminder => Intl.message(
      "You can turn the button back on in Settings › Appearance › Add a “Standalone rooms” button.",
      name: "promptHideRoomsOutsideSpacesReminder",
      desc:
          "Shown when hiding the 'Standalone rooms' sidebar button, reminding the user where to turn it back on");

  String get promptHideButton => Intl.message("Hide",
      name: "promptHideButton",
      desc: "Button to confirm hiding a sidebar button");

  Future<void> hideRoomsOutsideSpaces() async {
    var confirmed = await AdaptiveDialog.confirmation(context,
        title: labelHideRoomsOutsideSpacesTitle,
        prompt:
            standaloneRoomsHideReminder(promptHideRoomsOutsideSpacesReminder),
        confirmationText: promptHideButton,
        cancelText: CommonStrings.promptCancel);
    if (confirmed == true) {
      await preferences.showRoomsInSidebar.set(false);
    }
  }

  late List<SidebarEntry> items;

  Client? filterClient;

  int notificationCount = 0;
  int highlightedNotificationCount = 0;

  /// Vommet issue 719: whether the rooms button's badge is red, not grey.
  bool highlightedNotificationNoisy = false;

  @override
  void initState() {
    _clientManager = Provider.of<ClientManager>(context, listen: false);

    void setFilterClient(Client? event) {
      setState(() {
        filterClient = event;

        getSpaces();
      });
    }

    // showRoomsInSidebar = preferences.showRoomsInSidebar.v

    var countsPending = false;
    subs = [
      _clientManager.onSpaceChildUpdated.stream.listen((_) => onSpaceUpdate()),
      _clientManager.onSpaceUpdated.stream.listen((_) => onSpaceUpdate()),
      _clientManager.onSpaceRemoved.listen((_) => onSpaceUpdate()),
      _clientManager.onSpaceAdded.listen((_) => onSpaceUpdate()),
      _clientManager.onClientRemoved.stream.listen((_) => onSpaceUpdate()),
      _clientManager.onDirectMessageRoomUpdated.stream
          .listen(onDirectMessageUpdated),
      // Vommet: one recount per burst of room updates. Every room reports
      // an update as its state loads at startup, and each recount walks all
      // rooms (and asks each whether it is a DM): on a 237-room account that
      // was ~14% of the UI isolate's first 8 s. Badges catch up within 100 ms.
      _clientManager.onRoomUpdated.stream.listen((_) {
        if (countsPending) return;
        countsPending = true;
        Timer(const Duration(milliseconds: 100), () {
          countsPending = false;
          if (mounted) setState(updateNotificationCounts);
        });
      }),
      EventBus.setFilterClient.stream.listen(setFilterClient),
      SidebarEntriesComponent.onOrderChanged.listen((_) => onSpaceUpdate()),
      preferences.experimentSidebarPinnedRooms.onChanged
          .listen((_) => onSpaceUpdate()),
      preferences.showRoomsInSidebar.onChanged.listen((_) => setState(() {
            updateNotificationCounts();
          })),
      roomsShortcutChanged.listen((_) => setState(updateNotificationCounts)),
      // Vommet: "Sidebar icon size" in Appearance settings.
      preferences.sidebarIconSize.onChanged.listen((_) => setState(() {})),
      _clientManager.clients.onListUpdated.listen((_) => watchInvites()),
    ];

    watchInvites();
    getSpaces();

    super.initState();
  }

  /// Vommet issue 550: each account's invite list, so the Home badge
  /// follows invites as they come and go.
  List<StreamSubscription> inviteSubs = [];

  void watchInvites() {
    for (final sub in inviteSubs) {
      sub.cancel();
    }
    inviteSubs = [
      for (final client in _clientManager.clients)
        if (client.getComponent<InvitationComponent>() case final invites?)
          invites.invitations.onListUpdated.listen((_) {
            if (mounted) setState(() {});
          }),
    ];
    if (mounted) setState(() {});
  }

  /// Vommet issue 550: invites waiting on Home (of the filtered account).
  int get pendingInvites => _clientManager.clients
      .where((client) => filterClient == null || client == filterClient)
      .fold(
          0,
          (sum, client) =>
              sum +
              (client.getComponent<InvitationComponent>()?.invitations.length ??
                  0));

  int get homeBadgeCount =>
      pendingInvites + (homeBadgeCountsDms.value ? unreadDirectMessages : 0);

  /// Vommet issue 719: Home's badge is red for invites, or when a counted
  /// direct message is noisy (as under the spec's default rules); grey when
  /// all it counts are silent messages.
  bool get homeBadgeNoisy =>
      pendingInvites > 0 ||
      (preferences.experimentBannerLayout.value &&
          _clientManager.directMessages.highlightedRoomsList.any((room) =>
              (filterClient == null || room.client == filterClient) &&
              room.notificationCount > 0 &&
              room.badgeNoisy));

  /// Vommet: unread messages across DMs (of the filtered account).
  int get unreadDirectMessages =>
      _clientManager.directMessages.highlightedRoomsList
          .where((room) => filterClient == null || room.client == filterClient)
          .fold(0, (sum, room) => sum + room.notificationCount);

  void updateNotificationCounts() {
    highlightedNotificationCount = 0;
    highlightedNotificationNoisy = false;
    notificationCount = 0;
    for (var room in clientManager!.singleRooms(filterClient: filterClient)) {
      // Vommet: unread rooms (Discord's rule), not just notifying ones
      if (roomHasUnread(room)) notificationCount += 1;
      // Vommet issue 719: every counted message, grey or red.
      highlightedNotificationCount += room.badgeCount;
      highlightedNotificationNoisy |= room.badgeNoisy;
    }
  }

  void getSpaces() {
    if (filterClient != null) {
      var entries =
          filterClient!.getComponent<SidebarEntriesComponent>()!.getEntries();

      items = entries;
    } else {
      _clientManager = Provider.of<ClientManager>(context, listen: false);
      items = _clientManager.clients.fold(List.empty(growable: true), (v, c) {
        var entries = c.getComponent<SidebarEntriesComponent>()!.getEntries();
        v.addAll(entries);
        return v;
      });

      Map<String, SpaceGroupSidebarEntry> mergedFolders = {};

      List<SidebarEntry> finalEntries = List.empty(growable: true);

      for (var item in items) {
        if (item is SpaceGroupSidebarEntry) {
          if (mergedFolders.containsKey(item.id)) {
            mergedFolders[item.id]!.spaces.addAll(item.spaces);
            mergedFolders[item.id]!.rooms.addAll(item.rooms);
          } else {
            mergedFolders[item.id] = item;
          }
        } else {
          finalEntries.add(item);
        }
      }

      finalEntries.addAll(mergedFolders.values);
      items = finalEntries;
    }

    items.sort(
      (a, b) => a.order.compareTo(b.order),
    );
  }

  void onSpaceUpdate() {
    setState(() {
      getSpaces();
    });
  }

  void onDirectMessageUpdated(Room room) {
    setState(() {});
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    for (var sub in inviteSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      // Vommet: right-click (press and hold) for the spaces guide.
      GuideArea(guide: Guides.spaces, child: buildWithoutGuide(context));

  Widget buildWithoutGuide(BuildContext context) {
    final rail = RailMetrics.current;
    return SizedBox(
        width: rail.railWidth,
        child: Column(
          children: [
            Expanded(
              child: SpaceSelector(
                items,
                width: rail.slot,
                clearSelection: widget.clearSpaceSelection,
                shouldShowAvatarForSpace: shouldShowAvatarForSpace,
                header: Column(
                  children: [
                    SideNavigationBar.tooltip(
                        CommonStrings.promptHome,
                        Stack(
                          children: [
                            // Vommet: the rail pill, selected while Home is
                            // open with New Home on (Vommet issue 609)
                            // Vommet issue 719: Mark all as read (of the
                            // filtered account) in the Home button's menu.
                            AdaptiveContextMenu(
                              items: [
                                tiamat.ContextMenuItem(
                                  text: MarkAllRead.markAllReadLabel,
                                  icon: Icons.mark_chat_read_outlined,
                                  onPressed: () => MarkAllRead.confirmAndMark(
                                      context,
                                      _clientManager.clients.where((c) =>
                                          filterClient == null ||
                                          c == filterClient)),
                                ),
                              ],
                              child: HomeRailSelection(
                                  builder: (context, selected) => RailSlot(
                                        selected: selected,
                                        inset: rail.sidePadding,
                                        child: ImageButton(
                                          size: rail.slot,
                                          icon: Icons.home,
                                          onTap: () {
                                            newHomeShowFirstTab();
                                            widget.onHomeSelected?.call();
                                          },
                                        ),
                                      )),
                            ),
                            // Vommet: all unread DMs counted on Home, as
                            // Discord does; each DM shows its own below.
                            // Pending invites count too, with or without
                            // the experiment (Vommet issue 550).
                            if (homeBadgeCount > 0)
                              Align(
                                alignment: AlignmentGeometry.topRight,
                                child: NotificationBadge(homeBadgeCount,
                                    noisy: homeBadgeNoisy),
                              ),
                            // Vommet: a call going on, when a Live calls
                            // card asks for it (off by default).
                            const Positioned(
                                right: 4,
                                bottom: 4,
                                child: NewHomeLiveCallDot()),
                          ],
                        ),
                        context),
                    NewHomeRailShortcuts(onHomeSelected: widget.onHomeSelected),
                    if (roomsShortcutShown) ...[
                      SizedBox(
                        height: 4,
                      ),
                      SideNavigationBar.tooltip(
                          labelRoomsOutsideSpaces,
                          AdaptiveContextMenu(
                            items: [
                              tiamat.ContextMenuItem(
                                text: promptHideRoomsOutsideSpaces,
                                icon: Icons.visibility_off,
                                onPressed: hideRoomsOutsideSpaces,
                              ),
                              // Vommet: this menu hides the space bar's guide
                              // area, so offer that guide here too.
                              if (Guides.menuItem(context, Guides.spaces)
                                  case final help?)
                                help,
                            ],
                            child: Stack(
                              children: [
                                // Vommet: the same rail pill as spaces
                                RailSlot(
                                  unread: notificationCount > 0,
                                  inset: rail.sidePadding,
                                  child: ImageButton(
                                    size: rail.slot,
                                    icon: Icons.tag,
                                    onTap: () {
                                      widget.onRoomsViewSelected?.call();
                                    },
                                  ),
                                ),
                                if (highlightedNotificationCount > 0)
                                  Align(
                                    alignment: AlignmentGeometry.topRight,
                                    child: NotificationBadge(
                                        highlightedNotificationCount,
                                        noisy: highlightedNotificationNoisy),
                                  )
                              ],
                            ),
                          ),
                          context),
                    ],
                    SideNavigationBarDirectMessages(
                      _clientManager.directMessages,
                      onRoomTapped: widget.onDirectMessageSelected,
                    ),
                  ],
                ),
                footer: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
                      child: SideNavigationBar.tooltip(
                          promptAddRoomOrSpace,
                          ImageButton(
                            size: rail.slot,
                            icon: Icons.add,
                            onTap: () {
                              GetOrCreateRoom.show(null, context,
                                  pickExisting: false, showAllRoomTypes: true);
                            },
                          ),
                          context),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
                      child: SideNavigationBar.tooltip(
                          directoryTitle,
                          ImageButton(
                            key: const ValueKey("sidebar_discover_button"),
                            size: rail.slot,
                            icon: Icons.explore,
                            onTap: () {
                              RoomDirectoryLauncher.open(context,
                                  current: filterClient,
                                  onSpaceJoined: widget.onSpaceSelected);
                            },
                          ),
                          context),
                    ),
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height / 2,
                    )
                  ],
                ),
                onSelected: (space) {
                  widget.onSpaceSelected?.call(space);
                },
                onRoomSelected: widget.onDirectMessageSelected,
              ),
            ),
            if (widget.extraEntryBuilders != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                children: widget.extraEntryBuilders!
                    .map((e) => e(rail.slot))
                    .toList(),
              ),
          ],
        ));
  }

  bool shouldShowAvatarForSpace(Space space) {
    var spaces = _clientManager.spaces
        .where((element) => element.identifier == space.identifier);
    return spaces.length > 1;
  }
}
