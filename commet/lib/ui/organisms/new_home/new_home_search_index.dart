import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room_replacement.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:commet/ui/organisms/new_home/new_home_space_index.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';

/// Vommet (New Home): the side list search's [SearchIndex] of Commet rooms
/// and spaces: every joined room and DM of the filtered account (one per
/// room across accounts, the filtered or first account's), without rooms
/// hidden from New Home or replaced by a newer version. Rebuilt on the
/// first search after a sync or a space, account or rail change, never per
/// keystroke.
class NewHomeSearchIndex {
  static SearchIndex<Room, Space>? _cached;
  static Object? _cachedKey;
  static int _generation = 0;
  static ClientManager? _attached;
  static final List<StreamSubscription> _subs = [];

  static SearchIndex<Room, Space> of(ClientManager manager, Client? filter) {
    _attach(manager);
    final spaces = NewHomeSpaceIndex.of(manager, filter);
    final key = (_generation, identityHashCode(spaces), filter?.identifier);
    final cached = _cached;
    if (cached != null && key == _cachedKey) return cached;
    _cachedKey = key;
    return _cached = build(manager, filter, spaces);
  }

  static void _attach(ClientManager manager) {
    if (identical(_attached, manager)) return;
    for (final s in _subs) {
      s.cancel();
    }
    _subs
      ..clear()
      ..addAll([
        manager.onSync.stream.listen((_) => _generation++),
        manager.onSpaceUpdated.stream.listen((_) => _generation++),
        manager.onClientAdded.stream.listen((_) => _generation++),
        manager.onClientRemoved.stream.listen((_) => _generation++),
      ]);
    _attached = manager;
    _generation++;
  }

  static SearchIndex<Room, Space> build(
      ClientManager manager, Client? filter, NewHomeSpaceIndex index) {
    final docs = <SearchDoc<Room, Space>>[];
    final seen = <String>{};
    final clients = filter == null ? manager.clients : [filter];
    for (final client in clients) {
      final dms = client.getComponent<DirectMessagesComponent>();
      for (final room in client.rooms) {
        if (hiddenFromNewHome(room) || isSupersededRoom(room)) continue;
        if (!seen.add(room.identifier)) continue;
        final isDm = dms?.isRoomDirectMessage(room) == true;
        final path = index.pathOf(room)?.spaces ?? const <Space>[];
        final tags = roomTagsOf(room).where(isUserTag).toList();
        docs.add(SearchDoc<Room, Space>(
          room: room,
          name: room.displayName,
          partner: isDm ? dms?.getDirectMessagePartnerId(room) : null,
          path: path,
          pathNames: [for (final s in path) s.displayName],
          tags: tags,
          tagNames: [for (final t in tags) tagName(t)],
          topic: isDm ? "" : plainTopic(room.topic),
          isDirectMessage: isDm,
          last: room.lastEvent == null ? null : room.lastEventTimestamp,
        ));
      }
    }
    final spaces = <SearchSpace<Space>>[];
    final seenSpaces = <String>{};
    for (final client in clients) {
      for (final space in client.spaces) {
        if (!seenSpaces.add(space.identifier)) continue;
        final path = index.pathOfSpace(space);
        spaces.add(SearchSpace<Space>(space, space.displayName, path,
            parentName:
                path.length > 1 ? path[path.length - 2].displayName : null));
      }
    }
    return SearchIndex(docs, spaces);
  }

  /// A topic as plain text (any HTML tags dropped).
  static String plainTopic(String? topic) =>
      (topic ?? "").replaceAll(RegExp(r"<[^>]*>"), " ");
}
