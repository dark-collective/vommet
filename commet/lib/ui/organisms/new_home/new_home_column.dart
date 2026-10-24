import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/home_screen/important_rooms_list.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_editor.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_live_calls.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_store.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/new_home_tags.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/room_list_navigation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Home's column. The old one ([ImportantRoomsList]) unless the New
/// Home experiment is on; then search, a row per Home tab, and the shown
/// tab's side list: its sections of rooms (new_home_tabs.dart).
class HomeColumn extends StatelessWidget {
  const HomeColumn({
    super.key,
    required this.state,
    required this.directMessagesListHeaderDesktop,
  });

  final MainPageState state;
  final String directMessagesListHeaderDesktop;

  @override
  Widget build(BuildContext context) {
    if (!newHomeEnabled) {
      return ImportantRoomsList(
          state: state,
          directMessagesListHeaderDesktop: directMessagesListHeaderDesktop);
    }
    return NewHomeColumn(state: state, header: directMessagesListHeaderDesktop);
  }
}

class NewHomeColumn extends StatefulWidget {
  const NewHomeColumn({super.key, required this.state, required this.header});

  final MainPageState state;

  /// The Direct messages section's name.
  final String header;

  @override
  State<NewHomeColumn> createState() => _NewHomeColumnState();
}

class _NewHomeColumnState extends State<NewHomeColumn> {
  final TextEditingController search = TextEditingController();
  final List<StreamSubscription> subs = [];
  final List<StreamSubscription> clientSubs = [];
  String query = "";
  Timer? resort;

  /// The shown tab's sections and each one's rooms (search applied).
  List<(HomeSection, List<Room>)> sections = [];

  MainPageState get state => widget.state;
  HomeLayoutStore get store => HomeLayoutStore.instance;

  @override
  void initState() {
    super.initState();
    final manager = state.clientManager;
    final source = manager.directMessages.directMessageRooms;
    subs.addAll([
      source.onAdd.listen((_) => refreshSoon()),
      source.onRemove.listen((_) => refreshSoon()),
      source.onListUpdated.listen((_) => refreshSoon()),
      manager.directMessages.onEventReceived.stream
          .listen((_) => refreshSoon()),
      manager.onSync.stream.listen((_) => refreshSoon()),
      manager.onSpaceUpdated.stream.listen((_) => refreshSoon()),
      manager.onClientAdded.stream.listen((_) => clientsChanged()),
      manager.onClientRemoved.stream.listen((_) => clientsChanged()),
      EventBus.setFilterClient.stream.listen((_) => refreshSoon()),
    ]);
    store.attach(manager);
    store.tabs.addListener(refresh);
    newHomeTab.addListener(refresh);
    NewHomeInvites.instance.attach(manager);
    listenToClients();
    // Like the old column: Alt+Up/Down follow the rooms shown, in order.
    RoomListNavigation.register(this, () => shownRooms);
    refresh();
  }

  @override
  void dispose() {
    for (final s in [...subs, ...clientSubs]) {
      s.cancel();
    }
    resort?.cancel();
    store.tabs.removeListener(refresh);
    newHomeTab.removeListener(refresh);
    RoomListNavigation.unregister(this);
    search.dispose();
    super.dispose();
  }

  /// Favourites change outside the sync's room updates.
  void listenToClients() {
    for (final s in clientSubs) {
      s.cancel();
    }
    clientSubs.clear();
    for (final client in state.clientManager.clients) {
      clientSubs.addAll([
        client.favoriteRooms.onAdd.listen((_) => refreshSoon()),
        client.favoriteRooms.onRemove.listen((_) => refreshSoon()),
      ]);
    }
  }

  void clientsChanged() {
    listenToClients();
    refreshSoon();
  }

  void refreshSoon() {
    resort?.cancel();
    resort = Timer(const Duration(milliseconds: 100), refresh);
  }

  /// The rooms of expanded sections, top to bottom.
  List<Room> get shownRooms => [
        for (final (section, rooms) in sections)
          if (!collapsed(section)) ...rooms
      ];

  /// Searching shows every match, collapsed sections too.
  bool collapsed(HomeSection section) =>
      section.collapsed && query.trim().isEmpty;

  void refresh() {
    if (!mounted) return;
    final q = query.trim().toLowerCase();
    final shown = newHomeSideList(state);
    setState(() => sections = [
          for (final (section, rooms) in shown)
            (
              section,
              [
                for (final room in rooms)
                  if (q.isEmpty || matches(room, q)) room
              ]
            )
        ]);
  }

  static bool matches(Room room, String q) {
    if (room.displayName.toLowerCase().contains(q)) return true;
    final partner = room.client
        .getComponent<DirectMessagesComponent>()
        ?.getDirectMessagePartnerId(room);
    return partner?.toLowerCase().contains(q) ?? false;
  }

  void onSearch(String text) {
    query = text;
    refresh();
  }

  void open(HomeTab tab) => openNewHomeTab(context, state, tab);

  /// Collapsing is saved with the layout, so it follows you to your other
  /// devices.
  void toggle(HomeSection section) {
    final tab = store.current;
    final parent = section.parent;
    if (parent != null) {
      final all = tab.side.where((s) => s.id == parent).firstOrNull;
      if (all == null || section.tag == null) return;
      store.saveTabs(
          store.tabs.value.replaceTab(
              tab.replaceSection(toggleCollapsedTag(all, section.tag!))),
          undoable: false);
      return;
    }
    store.saveTabs(
        store.tabs.value.replaceTab(tab
            .replaceSection(section.copyWith(collapsed: !section.collapsed))),
        undoable: false);
  }

  String sectionTitle(HomeSection section) => section.type ==
          HomeSection.directMessages
      ? widget.header
      : section.type == HomeSection.spaceSection
          ? spaceOfSection(state.clientManager, section)?.displayName ?? "Space"
          : tagSectionTitle(section) ?? sectionLabel(section.type);

  Widget searchField(ColorScheme scheme) {
    return SizedBox(
      height: 38,
      child: TextField(
        key: const ValueKey("NewHomeSearch"),
        controller: search,
        onChanged: onSearch,
        textAlignVertical: TextAlignVertical.center,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: "Find a conversation",
          hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLowest,
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: "Clear search",
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    search.clear();
                    onSearch("");
                  }),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  /// A section's rows: its header, then its rooms unless collapsed. Empty
  /// sections are left out, except Direct messages (it has the + button).
  List<Widget> sectionSlivers(HomeSection section, List<Room> rooms) {
    final dms = section.type == HomeSection.directMessages;
    final searching = query.trim().isNotEmpty;
    if (rooms.isEmpty && (!dms || searching)) return const [];
    final isCollapsed = collapsed(section);
    final badge = sectionBadge<Room>(rooms,
        mentions: (r) => r.displayHighlightedNotificationCount,
        notifications: (r) => r.displayNotificationCount,
        isDirectMessage: isNewHomeDirectMessage);
    return [
      SliverToBoxAdapter(
        child: SideListSectionHeader(
          key: ValueKey("NewHomeSection-${section.id}"),
          title: sectionTitle(section),
          icon: section.type == HomeSection.tagSection
              ? Icons.label_outline_rounded
              : section.type == HomeSection.allTags
                  ? Icons.label_rounded
                  : null,
          collapsed: isCollapsed,
          mentions: badge.mentions,
          noisy: badge.noisy,
          onToggle: searching ? null : () => toggle(section),
          action: dms
              ? tiamat.IconButton(
                  icon: Icons.add,
                  onPressed: () => state.searchUserToDm(),
                )
              : null,
        ),
      ),
      if (!isCollapsed && rooms.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: tiamat.Text.labelLow(
                "No direct messages yet. Press + to start one."),
          ),
        ),
      if (!isCollapsed && rooms.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(3, 0, 0, 8),
          sliver: SliverList.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) => Padding(
              key:
                  ValueKey("NewHomeSideRoom-${section.id}-${rooms[i].localId}"),
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
              child: RoomPanel(rooms[i],
                  onTap: () => EventBus.doOpenRoom(rooms[i].identifier,
                      clientId: rooms[i].client.identifier,
                      openInSpace: false)),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final noRoom = state.currentRoom == null;
    // Like the old column: the room list's collapse button, on desktop.
    final collapse = RoomListHeaderAction.of(context);
    final tabs = store.tabs.value;
    final searching = query.trim().isNotEmpty;
    final slivers = [
      for (final (section, rooms) in sections) ...sectionSlivers(section, rooms)
    ];

    // Every tab removed: phones open on the side list, so it says so there
    // too (desktop shows it in the main area).
    if (store.isEmpty && MediaQuery.of(context).mobile) {
      return NewHomeEmpty(phone: true, clientManager: state.clientManager);
    }

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 12, collapse == null ? 10 : 2, 8),
          child: Row(children: [
            Expanded(child: searchField(scheme)),
            if (collapse != null)
              Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 6, 0),
                  child: collapse),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: NewHomeRows(
              tabs: tabs.tabs,
              selected: noRoom ? store.current.id : null,
              onSelect: open),
        ),
      ),
      // Customize Home: a dashed outline round the side list while it's
      // edited; dimmed while the main page is.
      ListenableBuilder(
        listenable: Listenable.merge([newHomeCustomizing, newHomeEditPart]),
        builder: (context, _) {
          final content = [
            ...slivers,
            if (slivers.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: tiamat.Text.labelLow(searching
                      ? "No conversations match \"${query.trim()}\"."
                      : store.isEmpty
                          ? "Home has no tabs."
                          : "Nothing in ${store.current.name}'s side list yet."),
                ),
              ),
          ];
          if (!newHomeCustomizing.value) {
            return SliverMainAxisGroup(slivers: content);
          }
          if (newHomeEditPart.value == HomeEditPart.side) {
            return DashedSliverOutline(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                slivers: content);
          }
          return SliverOpacity(
              opacity: 0.4, sliver: SliverMainAxisGroup(slivers: content));
        },
      ),
    ]);
  }
}

/// A side list section's name.
String sectionLabel(String type) => switch (type) {
      HomeSection.favourites => "Favourites",
      HomeSection.recent => "Recent activity",
      HomeSection.directMessages => "Direct messages",
      HomeSection.voice => "Voice rooms",
      HomeSection.liveVoice => "Live voice rooms",
      HomeSection.liveCalls => "Live calls",
      HomeSection.photos => "Photo albums",
      HomeSection.standalone => "Standalone rooms",
      HomeSection.spaceSection => "A space's rooms",
      HomeSection.lowPriority => "Low priority",
      HomeSection.tagSection => "Tags",
      HomeSection.allTags => "All my tags",
      _ => type,
    };

/// The space a side list section shows, or null when it's gone.
Space? spaceOfSection(ClientManager manager, HomeSection section) {
  final id = section.space;
  if (id == null) return null;
  final spaces = manager.spaces.where((s) => s.identifier == id).toList();
  return spaces
          .where((s) =>
              section.spaceClient == null ||
              s.client.identifier == section.spaceClient)
          .firstOrNull ??
      spaces.firstOrNull;
}

/// Shows Home tab [tab]'s page (closing an open room) and side list.
void openNewHomeTab(BuildContext context, MainPageState state, HomeTab tab) {
  final opensPage = newHomePickOpensPage(state, tab.id);
  newHomeTab.value = tab.id;
  if (state.currentRoom != null) EventBus.openHomeScreen.add(null);
  if (MediaQuery.of(context).mobile && opensPage) newHomeShowPage.add(tab.id);
}

/// Phones: whether picking Home tab [id] also slides its main page in.
/// Picking another tab only switches the side list to it (swipe for its
/// page); picking the tab Home already shows opens its page.
bool newHomePickOpensPage(MainPageState state, String id) => pickOpensPage(
    onHome: state.currentView == MainPageSubView.home,
    roomOpen: state.currentRoom != null,
    shown: newHomeTab.value,
    picked: id);

/// [newHomePickOpensPage] without the main page: only the tab already shown
/// on Home, with no room open, opens its page.
bool pickOpensPage(
        {required bool onHome,
        required bool roomOpen,
        required String shown,
        required String picked}) =>
    onHome && !roomOpen && shown == picked;

/// The shown Home tab's side list: its sections (tag sections expanded) and
/// each one's rooms, of the filtered account. The column and the compact
/// room list both show it (Vommet issue 630).
List<(HomeSection, List<Room>)> newHomeSideList(MainPageState state) {
  final manager = state.clientManager;
  final filter = state.filterClient;
  final rooms = [
    for (final room in filter?.rooms ?? manager.rooms)
      if ((filter == null || room.client == filter) && !hiddenFromNewHome(room))
        room
  ];
  final favourites = {
    for (final client in manager.clients) ...client.favoriteRooms
  };
  final standalone = manager.singleRooms(filterClient: filter).toSet();
  final tab = HomeLayoutStore.instance.current;
  final shown =
      expandTagSections(tab.sections, userTagsOf(rooms.map(roomTagsOf)));
  final lists = sideListRooms<Room>(
    shown,
    rooms,
    SideListFacts(
      lastEvent: (r) => r.lastEvent == null ? null : r.lastEventTimestamp,
      isFavourite: favourites.contains,
      isDirectMessage: isNewHomeDirectMessage,
      isVoice: (r) => r.getComponent<VoipRoomComponent>() != null,
      isLive: (r) =>
          r
              .getComponent<VoipRoomComponent>()
              ?.getCurrentParticipants()
              .isNotEmpty ??
          false,
      isPhotos: (r) => r.getComponent<PhotoAlbumRoom>() != null,
      isStandalone: (r) => standalone.contains(r) && !isNewHomeDirectMessage(r),
      isLowPriority: (r) =>
          r is MatrixRoom &&
          r.matrixRoom.tags[matrix.TagType.lowPriority] != null,
      spaceRooms: (section) =>
          spaceOfSection(manager, section)?.roomsWithChildren,
      hasTag: roomHasTag,
      hasUserTag: (r) => roomTagsOf(r).any(isUserTag),
      isInCall: (r) =>
          liveCallParticipants(r).isNotEmpty &&
          !isRoomMuted(r) &&
          !isRoomLowPriority(r),
    ),
  );
  return [for (var i = 0; i < shown.length; i++) (shown[i], lists[i])];
}

bool isNewHomeDirectMessage(Room room) =>
    room.client
        .getComponent<DirectMessagesComponent>()
        ?.isRoomDirectMessage(room) ==
    true;

/// A side list section's badge (Vommet issue 627), like a space's in the
/// rail: a red count of the mentions and keyword hits in its rooms; else a
/// red dot when one of them has a noisy notification (a direct message's,
/// under the default push rules); else nothing, as rooms that are only
/// unread show their own dots.
({int mentions, bool noisy}) sectionBadge<R>(
  Iterable<R> rooms, {
  required int Function(R room) mentions,
  required int Function(R room) notifications,
  required bool Function(R room) isDirectMessage,
}) {
  final count = rooms.fold<int>(0, (sum, room) => sum + mentions(room));
  return (
    mentions: count,
    noisy: count > 0 ||
        rooms.any((r) => isDirectMessage(r) && notifications(r) > 0),
  );
}

/// A side list section's header: a chevron, the name, the
/// [sectionBadge] of its rooms (shown collapsed too) and an optional action.
class SideListSectionHeader extends StatelessWidget {
  const SideListSectionHeader({
    super.key,
    required this.title,
    required this.collapsed,
    this.mentions = 0,
    this.noisy = false,
    this.onToggle,
    this.action,
    this.icon,
  });

  final String title;

  /// Drawn before the title (a tag section's tag).
  final IconData? icon;
  final bool collapsed;

  /// Mentions and keyword hits: a red count.
  final int mentions;

  /// A noisy notification without mentions: a red dot.
  final bool noisy;
  final VoidCallback? onToggle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(spacing: 4, children: [
                Icon(
                    collapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant),
                if (icon != null) Icon(icon, size: 14, color: scheme.primary),
                Expanded(
                  child: tiamat.Text.labelLow(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (mentions > 0)
                  NotificationBadge(mentions,
                      key: ValueKey("NewHomeSectionBadge-$title"))
                else if (noisy)
                  Semantics(
                    key: ValueKey("NewHomeSectionDot-$title"),
                    label: "New notifications",
                    child: Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          color: Colors.red.shade600, shape: BoxShape.circle),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

/// Discord-style rows, one per Home tab: full width, icon and name, the
/// shown tab on a rounded highlight. The tab holding People carries the
/// received-invites badge.
class NewHomeRows extends StatelessWidget {
  const NewHomeRows(
      {super.key,
      required this.tabs,
      required this.selected,
      required this.onSelect});

  final List<HomeTab> tabs;
  final String? selected;
  final void Function(HomeTab tab) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peopleTab =
        tabs.where((t) => t.holds(HomeLayout.peoplePage)).firstOrNull?.id;
    Widget row(HomeTab tab) {
      final s = selected == tab.id;
      final c = s ? scheme.onSurface : scheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: s ? scheme.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey("NewHomeRow-${tab.id}"),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(tab),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(spacing: 12, children: [
                Icon(homeTabIcon(tab.icon), size: 22, color: c),
                Expanded(
                  child: Text(tab.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: s ? FontWeight.w700 : FontWeight.w600,
                          color: c)),
                ),
                if (tab.id == peopleTab)
                  ValueListenableBuilder(
                    valueListenable: NewHomeInvites.instance.badge,
                    builder: (context, count, _) => count == 0
                        ? const SizedBox.shrink()
                        : NotificationBadge(count,
                            key: const ValueKey("NewHomeRowPeopleBadge")),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final tab in tabs) row(tab)],
    );
  }
}

/// [NewHomeRows] as icons, for the compact room list (Vommet issue 630):
/// each tab's icon with its name on hover, the shown tab on a rounded
/// highlight while no room is open, and the received-invites badge on the
/// tab holding People.
class NewHomeCompactRows extends StatelessWidget {
  const NewHomeCompactRows(
      {super.key,
      required this.tabs,
      required this.selected,
      required this.onSelect});

  final List<HomeTab> tabs;
  final String? selected;
  final void Function(HomeTab tab) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peopleTab =
        tabs.where((t) => t.holds(HomeLayout.peoplePage)).firstOrNull?.id;
    Widget row(HomeTab tab) {
      final s = selected == tab.id;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Tooltip(
          message: tab.name,
          child: Material(
            color: s ? scheme.surfaceContainerHighest : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: ValueKey("NewHomeCompactRow-${tab.id}"),
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelect(tab),
              child: SizedBox(
                height: 40,
                child: Stack(children: [
                  Center(
                    child: Icon(homeTabIcon(tab.icon),
                        size: 22,
                        semanticLabel: tab.name,
                        color: s ? scheme.onSurface : scheme.onSurfaceVariant),
                  ),
                  if (tab.id == peopleTab)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: ValueListenableBuilder(
                        valueListenable: NewHomeInvites.instance.badge,
                        builder: (context, count, _) => count == 0
                            ? const SizedBox.shrink()
                            : NotificationBadge(count, size: 14),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final tab in tabs) row(tab)],
      ),
    );
  }
}
