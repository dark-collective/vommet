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
import 'package:commet/ui/organisms/new_home/new_home_rooms_section.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_settings.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:commet/ui/organisms/new_home/new_home_search_index.dart';
import 'package:commet/ui/organisms/new_home/new_home_search_view.dart';
import 'package:commet/ui/organisms/new_home/new_home_space_index.dart';
import 'package:commet/ui/organisms/new_home/new_home_tab_icon.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/new_home_tags.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/room_list_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final FocusNode searchFocus = FocusNode();
  String query = "";
  Timer? resort;

  /// The shown tab's sections and each one's rooms.
  List<(HomeSection, List<Room>)> sections = [];

  /// Searching (new_home_search.dart): the scope token, the results, the
  /// groups shown in full, and the row Enter opens (the top one at first).
  SearchScope<Space>? scope;
  SearchIndex<Room, Space>? searchIndex;
  SearchResults<Room, Space> results = const SearchResults();
  final Set<Object> expanded = {};
  int selected = 0;

  bool get searching => query.trim().isNotEmpty || scope != null;

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
    searchFocus.dispose();
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

  /// The rooms shown, top to bottom: the search results in the order
  /// shown, else the expanded sections' rooms.
  List<Room> get shownRooms => searching
      ? resultOrder
      : [
          for (final (section, rooms) in sections)
            if (!section.collapsed) ...rooms
        ];

  List<Room> get resultOrder =>
      results.order(shownIn: NewHomeSearchView.groupRows, expanded: expanded);

  Room? get selectedRoom {
    final order = resultOrder;
    if (order.isEmpty) return null;
    return order[selected.clamp(0, order.length - 1)];
  }

  bool collapsed(HomeSection section) => section.collapsed;

  void refresh() {
    if (!mounted) return;
    final shown = newHomeSideList(state);
    final manager = state.clientManager;
    setState(() {
      sections = shown;
      if (searching) {
        final index =
            searchIndex = NewHomeSearchIndex.of(manager, state.filterClient);
        results = index.search(query, scope: scope);
      } else {
        results = const SearchResults();
      }
    });
  }

  /// Typing searches after a short pause, as before.
  void onSearch(String text) {
    query = text;
    selected = 0;
    expanded.clear();
    refreshSoon();
  }

  void scopeTo(SearchScope<Space>? next) {
    scope = next;
    selected = 0;
    expanded.clear();
    refresh();
    searchFocus.requestFocus();
  }

  void clearSearch() {
    search.clear();
    query = "";
    scope = null;
    selected = 0;
    expanded.clear();
    refresh();
  }

  void openRoom(Room room) => EventBus.doOpenRoom(room.identifier,
      clientId: room.client.identifier, openInSpace: false);

  /// Enter (or the phone's search key): the highlighted result.
  void openSelected() {
    if (resort?.isActive == true) {
      resort!.cancel();
      refresh();
    }
    final room = selectedRoom;
    if (room != null) openRoom(room);
  }

  /// Up/Down move the highlight, Esc clears, Backspace in an empty field
  /// removes the scope token.
  KeyEventResult onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && searching) {
      clearSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace &&
        search.text.isEmpty &&
        scope != null) {
      scopeTo(null);
      return KeyEventResult.handled;
    }
    if (!searching || HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final count = resultOrder.length;
      if (count == 0) return KeyEventResult.handled;
      setState(() => selected =
          (selected + (key == LogicalKeyboardKey.arrowDown ? 1 : -1))
              .clamp(0, count - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// "Go to <space>" for each of the room's spaces (nearest first), then
  /// "Search in <space>" (Mockup 7). Only spaces you're in.
  List<tiamat.ContextMenuItem> spaceMenu(Room room) {
    final manager = state.clientManager;
    final path =
        NewHomeSpaceIndex.of(manager, state.filterClient).pathOf(room)?.spaces;
    if (path == null || path.isEmpty) return const [];
    return [
      for (final space in path.reversed)
        tiamat.ContextMenuItem(
            text: "Go to ${space.displayName}",
            icon: Icons.workspaces_outline,
            onPressed: () => EventBus.openSpace
                .add((space.identifier, space.client.identifier))),
      tiamat.ContextMenuItem(
          text: "Search in ${path.last.displayName}",
          icon: Icons.search_rounded,
          onPressed: () {
            search.clear();
            query = "";
            scopeTo(NewHomeSearchView.spaceScope(
                NewHomeSearchIndex.of(manager, state.filterClient), path.last));
          }),
    ];
  }

  /// Another account's row shows its account (all accounts shown).
  bool accountHint(Room room) {
    final clients = state.clientManager.clients;
    return state.filterClient == null &&
        clients.length > 1 &&
        room.client != clients.first;
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

  String sectionTitle(HomeSection section) => switch (section.type) {
        HomeSection.directMessages => widget.header,
        HomeSection.spaceSection =>
          spaceOfSection(state.clientManager, section)?.displayName ?? "Space",
        HomeSection.standalone => roomsSectionTitle(state, section),
        _ => tagSectionTitle(section) ?? sectionLabel(section.type),
      };

  /// A Rooms section's settings sheet; saves what it returns.
  Future<void> editRooms(HomeSection section) async {
    final tab = store.current;
    final index = tab.side.indexWhere((s) => s.id == section.id);
    final result = await showRoomsSettings(context, state.clientManager,
        initial: section.rooms,
        name: section.name,
        dmsAbove: tab.side
            .take(index < 0 ? 0 : index)
            .any((s) => s.type == HomeSection.directMessages));
    if (result == null || !mounted) return;
    final current = store.current;
    final now = current.side.where((s) => s.id == section.id).firstOrNull;
    if (now == null) return;
    store.saveTabs(store.tabs.value.replaceTab(current.replaceSection(
        now.copyWith(rooms: result.filter, name: result.name ?? ""))));
  }

  Widget searchField(ColorScheme scheme) {
    return SizedBox(
      height: 38,
      child: TextField(
        key: const ValueKey("NewHomeSearch"),
        controller: search,
        focusNode: searchFocus,
        onChanged: onSearch,
        onSubmitted: (_) {
          openSelected();
          searchFocus.requestFocus();
        },
        textAlignVertical: TextAlignVertical.center,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: "Search people and rooms",
          hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLowest,
          prefixIcon: scope == null
              ? Icon(Icons.search_rounded,
                  size: 18, color: scheme.onSurfaceVariant)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
                  child: InputChip(
                    key: const ValueKey("NewHomeSearchToken"),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                    avatar: Icon(
                        scope!.space != null
                            ? Icons.workspaces_outline
                            : scope!.tag != null
                                ? Icons.label_outline_rounded
                                : scope!.directMessages == true
                                    ? Icons.person_outline
                                    : Icons.tag_rounded,
                        size: 14),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(scope!.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    deleteIcon: const Icon(Icons.close_rounded, size: 14),
                    deleteButtonTooltipMessage: "Search everything",
                    onDeleted: () => scopeTo(null),
                  ),
                ),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          suffixIcon: !searching
              ? null
              : IconButton(
                  tooltip: "Clear search",
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: clearSearch),
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
    // A Rooms section of only spaces you've all left says so rather than
    // vanishing.
    final spacesGone = section.type == HomeSection.standalone &&
        rooms.isEmpty &&
        section.rooms.spaces == RoomsFilter.spacesOnly &&
        section.rooms.spaceList.isNotEmpty &&
        section.rooms.spaceList.every((ref) =>
            NewHomeSpaceIndex.of(state.clientManager, null)
                .spaceOf(state.clientManager, ref) ==
            null);
    if (rooms.isEmpty && !dms && !spacesGone) return const [];
    final isCollapsed = collapsed(section);
    final badge = sectionBadge<Room>(rooms,
        count: (r) => r.badgeCount, noisy: (r) => r.badgeNoisy);
    final isRooms = section.type == HomeSection.standalone;
    final filter = section.rooms;
    final manager = state.clientManager;
    final index =
        isRooms ? NewHomeSpaceIndex.of(manager, state.filterClient) : null;
    // A Rooms section's rows: its spaces (when asked for) among its rooms.
    final rows = index == null
        ? [for (final r in rooms) RoomsRow<Room, Space>.room(r)]
        : roomsSectionRows<Room, Space>(filter, rooms,
            index.sectionSpaces(manager, filter), (r) => index.pathOf(r)?.rail,
            isDirectMessage: isNewHomeDirectMessage);
    String? suffix(Room room) => index != null && filter.spaceNames
        ? index.pathOf(room)?.nearest.displayName
        : null;
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
          count: badge.count,
          noisy: badge.noisy,
          onToggle: () => toggle(section),
          onMenu: isRooms ? () => editRooms(section) : null,
          action: dms
              ? tiamat.IconButton(
                  icon: Icons.add,
                  onPressed: () => state.searchUserToDm(),
                )
              : isRooms
                  ? tiamat.IconButton(
                      key: ValueKey("NewHomeRoomsSettings-${section.id}"),
                      icon: Icons.more_horiz_rounded,
                      size: 18,
                      onPressed: () => editRooms(section),
                    )
                  : null,
        ),
      ),
      if (!isCollapsed && rooms.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: spacesGone
                ? Row(children: [
                    Expanded(
                        child: tiamat.Text.labelLow(
                            "You left the spaces this section shows.")),
                    TextButton(
                        onPressed: () => editRooms(section),
                        child: const Text("Settings…")),
                  ])
                : tiamat.Text.labelLow(
                    "No direct messages yet. Press + to start one."),
          ),
        ),
      if (!isCollapsed && rooms.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(3, 0, 0, 8),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final space = rows[i].space;
              if (space != null) {
                return Padding(
                  key: ValueKey(
                      "NewHomeSideSpace-${section.id}-${space.localId}"),
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                  child: NewHomeSpaceRow(space),
                );
              }
              final room = rows[i].room!;
              return Padding(
                key: ValueKey("NewHomeSideRoom-${section.id}-${room.localId}"),
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                child: RoomPanel(room,
                    nameSuffix: suffix(room),
                    leadingMenuItems: spaceMenu(room),
                    onTap: () => EventBus.doOpenRoom(room.identifier,
                        clientId: room.client.identifier, openInSpace: false)),
              );
            },
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
    final index = searchIndex;
    // Searching: the ranked results instead of the tab rows and sections.
    final slivers = searching && index != null
        ? NewHomeSearchView.slivers(context,
            index: index,
            results: results,
            scope: scope,
            query: query,
            expanded: expanded,
            selected: selectedRoom,
            actions: NewHomeSearchActions(
              scopeTo: scopeTo,
              expand: (key) => setState(() {
                if (!expanded.remove(key)) expanded.add(key);
              }),
              open: openRoom,
              menu: spaceMenu,
              accountHint: accountHint,
            ))
        : [
            for (final (section, rooms) in sections)
              ...sectionSlivers(section, rooms)
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
            Expanded(
                child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: onSearchKey,
                    child: searchField(scheme))),
            if (collapse != null)
              Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 6, 0),
                  child: collapse),
          ]),
        ),
      ),
      if (!searching)
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
                  child: tiamat.Text.labelLow(store.isEmpty
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

/// A Rooms section's name ([roomsSectionLabel]).
String roomsSectionTitle(MainPageState state, HomeSection section) {
  final manager = state.clientManager;
  return roomsSectionLabel(section.rooms,
      name: section.name,
      onlySpace: (ref) => NewHomeSpaceIndex.of(manager, state.filterClient)
          .spaceOf(manager, ref)
          ?.displayName);
}

/// A Rooms section's row for a space ("The spaces themselves"): its
/// avatar and name; tap to open it.
class NewHomeSpaceRow extends StatelessWidget {
  const NewHomeSpaceRow(this.space, {super.key});

  final Space space;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: "Open space ${space.displayName}",
      excludeSemantics: true,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: () =>
            EventBus.openSpace.add((space.identifier, space.client.identifier)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(spacing: 10, children: [
            tiamat.Avatar(
                radius: 14,
                image: space.avatar,
                placeholderText: space.displayName,
                placeholderColor: space.color),
            Expanded(
              child: Text(space.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

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
  final index = NewHomeSpaceIndex.of(manager, filter);
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
      rooms: index.facts(manager,
          isStandalone: (r) =>
              standalone.contains(r) && !isNewHomeDirectMessage(r),
          isDirectMessage: isNewHomeDirectMessage,
          hasTag: roomHasTag),
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
/// rail: its rooms' badge counts added up, red when one of them is noisy
/// and grey when all are silent (Vommet issue 719); nothing when its rooms
/// are only unread, as they show their own dots.
({int count, bool noisy}) sectionBadge<R>(
  Iterable<R> rooms, {
  required int Function(R room) count,
  required bool Function(R room) noisy,
}) {
  final total = rooms.fold<int>(0, (sum, room) => sum + count(room));
  return (
    count: total,
    noisy: total > 0 && rooms.any((r) => count(r) > 0 && noisy(r)),
  );
}

/// Vommet issue 719: the People badge ([NewHomeInvites.badge]), grey or
/// red; nothing at 0.
Widget peopleBadge(Widget Function(int count, bool noisy) badge) =>
    ListenableBuilder(
      listenable: Listenable.merge(
          [NewHomeInvites.instance.badge, NewHomeInvites.instance.badgeNoisy]),
      builder: (context, _) {
        final count = NewHomeInvites.instance.badge.value;
        return count == 0
            ? const SizedBox.shrink()
            : badge(count, NewHomeInvites.instance.badgeNoisy.value);
      },
    );

/// A side list section's header: a chevron, the name, the
/// [sectionBadge] of its rooms (shown collapsed too) and an optional action.
class SideListSectionHeader extends StatelessWidget {
  const SideListSectionHeader({
    super.key,
    required this.title,
    required this.collapsed,
    this.count = 0,
    this.noisy = false,
    this.onToggle,
    this.onMenu,
    this.action,
    this.icon,
  });

  final String title;

  /// Drawn before the title (a tag section's tag).
  final IconData? icon;
  final bool collapsed;

  /// The rooms' counted messages (Vommet issue 719).
  final int count;

  /// Whether [count] is red rather than grey.
  final bool noisy;
  final VoidCallback? onToggle;

  /// Hold or right-click: the section's settings (a Rooms section's).
  final VoidCallback? onMenu;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(children: [
        Expanded(
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(6),
            onTap: onToggle,
            onLongPress: onMenu,
            onSecondaryTap: onMenu,
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
                if (count > 0)
                  NotificationBadge(count,
                      noisy: noisy,
                      key: ValueKey("NewHomeSectionBadge-$title")),
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
            mouseCursor: WidgetStateMouseCursor.clickable,
            key: ValueKey("NewHomeRow-${tab.id}"),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(tab),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(spacing: 12, children: [
                HomeTabIcon(tab.icon, size: 22, color: c),
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
                  peopleBadge((count, noisy) => NotificationBadge(count,
                      noisy: noisy,
                      key: const ValueKey("NewHomeRowPeopleBadge"))),
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
              mouseCursor: WidgetStateMouseCursor.clickable,
              key: ValueKey("NewHomeCompactRow-${tab.id}"),
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelect(tab),
              child: SizedBox(
                height: 40,
                child: Stack(children: [
                  Center(
                    child: HomeTabIcon(tab.icon,
                        size: 22,
                        semanticLabel: tab.name,
                        color: s ? scheme.onSurface : scheme.onSurfaceVariant),
                  ),
                  if (tab.id == peopleTab)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: peopleBadge((count, noisy) =>
                          NotificationBadge(count, size: 14, noisy: noisy)),
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
