import 'package:commet/ui/organisms/people/people_model.dart';
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/atoms/sidebar_room_icon.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:commet/utils/room_list_navigation.dart';

/// Vommet: the room list drawn as room pictures only (Vommet issue 456), for
/// a narrow window or when collapsed by hand. Hovering a picture shows the
/// room's name; unread dots and mention counts stay. Subspaces and the line
/// between favourites and direct messages become thin dividers.
class CompactRoomList extends StatefulWidget {
  const CompactRoomList(this.state, {super.key});

  final MainPageState state;

  @override
  State<CompactRoomList> createState() => _CompactRoomListState();
}

/// A room picture, or a divider (null).
typedef _Entry = Room?;

class _CompactRoomListState extends State<CompactRoomList> {
  List<StreamSubscription> _subs = [];
  Object? _watching;

  MainPageState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // Vommet issues 290/499: Alt+Up/Down follow this list.
    RoomListNavigation.register(
        this, () => _entries().whereType<Room>().toList());
  }

  @override
  void dispose() {
    RoomListNavigation.unregister(this);
    _unwatch();
    super.dispose();
  }

  void _unwatch() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs = [];
  }

  void _changed(_) {
    if (mounted) setState(() {});
  }

  void _watchLists(List<INotifyingList<Room>> lists) {
    for (final list in lists) {
      _subs.addAll([
        list.onAdd.listen(_changed),
        list.onRemove.listen(_changed),
        list.onListUpdated.listen(_changed),
      ]);
    }
  }

  void _watchSpaces(Iterable<Space> spaces) {
    for (final space in spaces) {
      _subs.addAll([
        space.onUpdate.listen(_changed),
        space.onRoomAdded.listen(_changed),
        space.onRoomRemoved.listen(_changed),
        space.onChildSpaceAdded.listen(_changed),
        space.onChildSpaceRemoved.listen(_changed),
      ]);
    }
  }

  /// Re-subscribes when what's listed changes (another view, another space,
  /// a subspace added or removed).
  void _watch(Object key, void Function() subscribe) {
    if (_watching == key) return;
    _unwatch();
    _watching = key;
    subscribe();
  }

  static int _newestFirst(Room a, Room b) =>
      b.lastEventTimestamp.compareTo(a.lastEventTimestamp);

  List<_Entry> _entries() {
    // Vommet issue 580: People, every DM newest first.
    if (state.currentView == MainPageSubView.people) {
      final dms = state.clientManager.directMessages.directMessageRooms;
      _watch(dms, () => _watchLists([dms]));
      return PeopleModel.rooms(dms, client: state.filterClient);
    }

    if (state.currentView == MainPageSubView.rooms) {
      _watch(state.singleRooms, () => _watchLists([state.singleRooms]));
      return state.singleRooms.toList()..sort(_newestFirst);
    }

    final space = state.currentSpace;
    if (space == null) {
      _watch(state.directMessages,
          () => _watchLists([state.favoriteRooms, state.directMessages]));
      final favourites = state.favoriteRooms.toList();
      final dms = state.directMessages
          .where((r) => !favourites.contains(r))
          .toList()
        ..sort(_newestFirst);
      return [
        ...favourites,
        if (favourites.isNotEmpty && dms.isNotEmpty) null,
        ...dms,
      ];
    }

    final entries = <_Entry>[];
    final spaces = <Space>[];
    _walk(space, entries, spaces, 0);
    _watch(Object.hashAll(spaces), () => _watchSpaces(spaces));
    // No divider at either end, nor two in a row.
    final tidy = <_Entry>[];
    for (final e in entries) {
      if (e == null && (tidy.isEmpty || tidy.last == null)) continue;
      tidy.add(e);
    }
    if (tidy.isNotEmpty && tidy.last == null) tidy.removeLast();
    return tidy;
  }

  /// The space's rooms in sidebar order (rooms you're banned from last,
  /// replaced rooms left out), each subspace after a divider.
  static void _walk(
      Space space, List<_Entry> entries, List<Space> spaces, int depth) {
    spaces.add(space);
    final children = space.children;
    final banned = <Room>[];
    for (final child in children) {
      if (child case SpaceChildRoom c) {
        if (c.child.isBanned) {
          banned.add(c.child);
        } else if (!isSupersededRoom(c.child)) {
          entries.add(c.child);
        }
      } else if (child case SpaceChildSpace c) {
        if (depth < 5) {
          entries.add(null);
          _walk(c.child, entries, spaces, depth + 1);
          entries.add(null);
        }
      }
    }
    entries.addAll(banned);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    const width = ResponsiveDesktop.compactListWidth;
    return Column(
      children: [
        // At the top, where the full list's header row has the button that
        // collapsed it. Only a list collapsed by hand can be widened by hand;
        // one the window squeezed has no room for names.
        ValueListenableBuilder(
          valueListenable: ResponsiveDesktop.collapsed,
          builder: (context, collapsed, _) => !collapsed
              ? const SizedBox.shrink()
              : const SizedBox(
                  height: 48,
                  child: Center(
                    child: RoomListCollapseButton(collapsed: true),
                  ),
                ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final room = entries[i];
              if (room == null) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Divider(height: 1),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                child: SidebarRoomIcon(
                  room,
                  key: ValueKey("compact-room-${room.localId}"),
                  width: width,
                  onTap: () => state.selectRoom(room),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
