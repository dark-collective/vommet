import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/home_screen/important_rooms_list.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_store.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/room_list_navigation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Home's column. The old one ([ImportantRoomsList]) unless the New
/// Home experiment is on; then search, the Overview / People / Rooms rows
/// and the direct messages (no favourites: Overview has them).
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
  final String header;

  @override
  State<NewHomeColumn> createState() => _NewHomeColumnState();
}

class _NewHomeColumnState extends State<NewHomeColumn> {
  final TextEditingController search = TextEditingController();
  final List<StreamSubscription> subs = [];
  List<Room> dms = [];
  String query = "";
  Timer? resort;

  MainPageState get state => widget.state;

  @override
  void initState() {
    super.initState();
    final source = state.clientManager.directMessages.directMessageRooms;
    subs.addAll([
      source.onAdd.listen((_) => refresh()),
      source.onRemove.listen((_) => refresh()),
      source.onListUpdated.listen((_) => refresh()),
      state.clientManager.directMessages.onEventReceived.stream
          .listen((_) => refreshSoon()),
      EventBus.setFilterClient.stream.listen((_) => refreshSoon()),
    ]);
    newHomePage.addListener(onPage);
    NewHomeInvites.instance.attach(state.clientManager);
    // Like the old column: Alt+Up/Down follow the direct messages shown.
    RoomListNavigation.register(this, () => List.of(dms));
    refresh();
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    resort?.cancel();
    newHomePage.removeListener(onPage);
    RoomListNavigation.unregister(this);
    search.dispose();
    super.dispose();
  }

  void onPage() => setState(() {});

  void refreshSoon() {
    resort?.cancel();
    resort = Timer(const Duration(milliseconds: 100), refresh);
  }

  /// All DMs (favourite ones too, unlike the old column), newest first,
  /// matching the search by name or Matrix ID.
  void refresh() {
    if (!mounted) return;
    final filter = state.filterClient;
    final q = query.trim().toLowerCase();
    final next = [
      for (final room in state.clientManager.directMessages.directMessageRooms)
        if ((filter == null || room.client == filter) &&
            !hiddenFromNewHome(room) &&
            (q.isEmpty || matches(room, q)))
          room
    ]..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
    setState(() => dms = next);
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

  void open(NewHomePage page) {
    if (MediaQuery.of(context).mobile) {
      newHomePage.value = page;
      NewHomePageScreen.push(context, page, state.clientManager,
          filterClient: state.filterClient);
      return;
    }
    newHomePage.value = page;
    if (state.currentRoom != null) EventBus.openHomeScreen.add(null);
  }

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = MediaQuery.of(context).mobile;
    final noRoom = phone || state.currentRoom == null;
    const rowPadding = EdgeInsets.fromLTRB(0, 4, 0, 4);
    // Like the old column: the room list's collapse button, on desktop.
    final collapse = RoomListHeaderAction.of(context);

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
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: NewHomeRows(
              selected: noRoom ? newHomePage.value : null, onSelect: open),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: tiamat.Text.labelLow(widget.header),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: tiamat.IconButton(
                icon: Icons.add,
                onPressed: () => state.searchUserToDm(),
              ),
            ),
          ]),
        ),
      ),
      if (dms.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: tiamat.Text.labelLow(query.trim().isEmpty
                ? "No direct messages yet. Press + to start one."
                : "No direct messages match \"${query.trim()}\"."),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(3, 0, 0, 8),
          sliver: SliverList.builder(
            itemCount: dms.length,
            itemBuilder: (context, i) => Padding(
              key: ValueKey("NewHomeDirectMessages-${dms[i].localId}"),
              padding: rowPadding,
              child: RoomPanel(dms[i]),
            ),
          ),
        ),
    ]);
  }
}

/// Discord-style rows: full width, icon and label, the open page on a
/// rounded highlight. People carries the received-invites badge.
class NewHomeRows extends StatelessWidget {
  const NewHomeRows(
      {super.key, required this.selected, required this.onSelect});

  final NewHomePage? selected;
  final void Function(NewHomePage page) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(NewHomePage page) {
      final s = selected == page;
      final c = s ? scheme.onSurface : scheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: s ? scheme.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey("NewHomeRow-${page.name}"),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(page),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(spacing: 12, children: [
                Icon(page.icon, size: 22, color: c),
                Expanded(
                  child: Text(page.label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: s ? FontWeight.w700 : FontWeight.w600,
                          color: c)),
                ),
                if (page == NewHomePage.people)
                  ValueListenableBuilder(
                    valueListenable: NewHomeInvites.instance.count,
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
      children: [for (final page in NewHomePage.values) row(page)],
    );
  }
}
