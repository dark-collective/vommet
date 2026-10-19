import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/home_screen/dm_search.dart';
import 'package:commet/ui/organisms/home_screen/home_screen_view.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:commet/ui/atoms/notifying_list_builder.dart';

import 'package:commet/ui/pages/main/main_page.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class ImportantRoomsList extends StatefulWidget {
  const ImportantRoomsList({
    super.key,
    required this.state,
    required this.directMessagesListHeaderDesktop,
  });

  final MainPageState state;
  final String directMessagesListHeaderDesktop;

  @override
  State<ImportantRoomsList> createState() => _ImportantRoomsListState();
}

class _ImportantRoomsListState extends State<ImportantRoomsList> {
  MainPageState get state => widget.state;

  // Vommet: the search field filters favourites and DMs by person (Vommet
  // issue 362), and rooms without a space by name.
  final TextEditingController search = TextEditingController();
  late final DmListSearch searched = DmListSearch(
      state.favoriteRooms, state.directMessages, state.singleRooms);
  String get query => searched.query;
  INotifyingList<Room> get favoriteRooms => searched.favorites;
  INotifyingList<Room> get directMessages => searched.directMessages;
  INotifyingList<Room> get singleRooms => searched.rooms;

  String get directMessagesSearchHint => Intl.message(
        "Find a conversation",
        desc: "Hint in the search field above the direct messages list",
        name: "directMessagesSearchHint",
      );

  String directMessagesSearchNoResults(String query) => Intl.message(
        "No direct messages match \"$query\".",
        args: [query],
        desc:
            "Shown under the direct messages header when the search matches none",
        name: "directMessagesSearchNoResults",
      );

  String get directMessagesSearchClear => Intl.message(
        "Clear search",
        desc: "Tooltip of the button that empties the direct messages search",
        name: "directMessagesSearchClear",
      );

  @override
  void dispose() {
    searched.dispose();
    search.dispose();
    super.dispose();
  }

  void onSearchChanged(String text) {
    setState(() => searched.setQuery(text));
  }

  void clearSearch() {
    search.clear();
    onSearchChanged("");
  }

  Widget buildSearchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Vommet issue 456: the room list's collapse button, on desktop.
    final action = RoomListHeaderAction.of(context);
    final field = Padding(
      padding: EdgeInsets.fromLTRB(6, 8, action == null ? 6 : 2, 2),
      child: SizedBox(
        height: 36,
        child: TextField(
          key: const ValueKey("DirectMessagesSearch"),
          controller: search,
          onChanged: onSearchChanged,
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: directMessagesSearchHint,
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: directMessagesSearchClear,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: clearSearch),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none),
          ),
        ),
      ),
    );
    if (action == null) return field;
    return Row(children: [
      Expanded(child: field),
      Padding(padding: const EdgeInsets.fromLTRB(0, 6, 6, 0), child: action),
    ]);
  }

  String get directMessagesListEmptyHint => Intl.message(
        "No direct messages yet. Press + to start one.",
        desc: "Shown under the direct messages header when there are none",
        name: "directMessagesListEmptyHint",
      );

  @override
  Widget build(BuildContext context) {
    var padding = const EdgeInsets.fromLTRB(0, 4, 0, 4);

    // Vommet: slivers, so only the visible rows are built. A shrink-wrapped
    // list built a RoomPanel (with its member, avatar and presence lookups)
    // for every DM at startup.
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: buildSearchField(context)),
      NotifyingListBuilder(
        key: ObjectKey(favoriteRooms),
        sliver: true,
        list: favoriteRooms,
        builder: (context, {required child, required list}) {
          if (list.isNotEmpty) {
            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: tiamat.Text.labelLow("Favorites"),
                  ),
                ),
                SliverPadding(
                    padding: const EdgeInsetsGeometry.fromLTRB(3, 0, 0, 0),
                    sliver: child)
              ],
            );
          }

          return child;
        },
        itemBuilder: (context, value) {
          return Padding(
              padding: padding,
              child: RoomPanel(
                key: ValueKey("RoomFavoritesList-${value.localId}"),
                value,
                onTap: () {
                  EventBus.doOpenRoom(value.identifier,
                      clientId: value.client.identifier, openInSpace: false);
                },
              ));
        },
      ),
      NotifyingListBuilder(
        key: ObjectKey(directMessages),
        sliver: true,
        list: directMessages,
        sortFunction: (p0, p1) {
          return p1.lastEventTimestamp.compareTo(p0.lastEventTimestamp);
        },
        onSortStream: state.clientManager.directMessages.onEventReceived.stream,
        builder: (context, {required child, required list}) {
          // Vommet: the header and its new-DM button always show. Upstream
          // hid both until the first DM existed, which left a new user with a
          // blank pane and no way to start one from it.
          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                  child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: tiamat.Text.labelLow(
                      widget.directMessagesListHeaderDesktop,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: tiamat.IconButton(
                      icon: Icons.add,
                      onPressed: () {
                        state.searchUserToDm();
                      },
                    ),
                  ),
                ],
              )),
              if (searched.showDirectMessagesHint)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: tiamat.Text.labelLow(query.isEmpty
                        ? directMessagesListEmptyHint
                        : directMessagesSearchNoResults(query)),
                  ),
                )
              else
                SliverPadding(
                    padding: const EdgeInsetsGeometry.fromLTRB(3, 0, 0, 0),
                    sliver: child)
            ],
          );
        },
        itemBuilder: (context, value) {
          return Padding(
            padding: padding,
            key: ValueKey("DirectMessagesList-${value.localId}"),
            child: RoomPanel(value),
          );
        },
      ),
      // Vommet: rooms without a space, below the DMs, so they stay in reach
      // while a chat is open (Vommet issue 418). Upstream only listed them on
      // the Home page and behind the optional Rooms rail entry.
      NotifyingListBuilder(
        key: ObjectKey(singleRooms),
        sliver: true,
        list: singleRooms,
        sortFunction: (p0, p1) {
          return p1.lastEventTimestamp.compareTo(p0.lastEventTimestamp);
        },
        onSortStream: state.clientManager.onEventReceived,
        builder: (context, {required child, required list}) {
          if (list.isEmpty) return child;

          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child:
                      tiamat.Text.labelLow(HomeScreenView.labelHomeRoomsList),
                ),
              ),
              SliverPadding(
                  padding: const EdgeInsetsGeometry.fromLTRB(3, 0, 0, 0),
                  sliver: child)
            ],
          );
        },
        itemBuilder: (context, value) {
          return Padding(
              padding: padding,
              child: RoomPanel(
                key: ValueKey("SidebarSingleRoomsList-${value.localId}"),
                value,
                onTap: () {
                  EventBus.doOpenRoom(value.identifier,
                      clientId: value.client.identifier, openInSpace: false);
                },
              ));
        },
      ),
    ]);
  }
}
