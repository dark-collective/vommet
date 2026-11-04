import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/rng.dart';

class SidebarEntry extends Object {
  String order;
  String id;

  SidebarEntry(this.id, this.order);
}

class SpaceSidebarEntry extends SidebarEntry {
  Space space;

  SpaceSidebarEntry(this.space, {required String order})
      : super(space.localId, order);
}

class SpaceGroupSidebarEntry extends SidebarEntry {
  String groupId;
  List<SpaceSidebarEntry> spaces;

  // Vommet: pinned rooms can sit in a folder too.
  List<RoomSidebarEntry> rooms = [];

  /// Vommet: the folder's spaces and rooms, in folder order.
  List<SidebarEntry> get members => <SidebarEntry>[...spaces, ...rooms]
    ..sort((a, b) => a.order.compareTo(b.order));

  SpaceGroupSidebarEntry(this.groupId, this.spaces, {required String order})
      : super(groupId, order);
}

/// Vommet: a room pinned to the sidebar as its own icon (#104).
class RoomSidebarEntry extends SidebarEntry {
  Room room;

  RoomSidebarEntry(this.room, {required String order})
      : super(room.localId, order);
}

class StringOrderGenerator {
  Map<String, String> idToOrder = {};
  StreamController _onChangedController = StreamController.broadcast();
  Stream get onChange => _onChangedController.stream;

  void setIndex(String id, int index) {
    if (idToOrder.containsKey(id) == false) {
      idToOrder[id] = RandomUtils.getRandomString(10);
    }

    var numEntries = idToOrder.length;

    index = index.clamp(0, numEntries - 1);

    Log.i("Setting entry: $id to index: $index");

    List<String> keys = List.empty(growable: true);

    for (int i = 0; i < numEntries; i++) {
      keys.add(RandomUtils.getRandomString(10));
    }

    keys.sort((a, b) => a.compareTo(b));

    var nthKey = keys.removeAt(index);

    var sorted = idToOrder.entries.where((i) => i.key != id).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (int i = 0; i < sorted.length; i++) {
      var key = sorted[i].key;

      idToOrder[key] = keys[i];
    }

    idToOrder[id] = nthKey;

    var resultSorted = idToOrder.values.sorted((a, b) => a.compareTo(b));
    assert(resultSorted[index] == nthKey);

    _onChangedController.add(null);
  }

  String? get(String id) {
    return idToOrder[id];
  }

  void set(String id, String value) {
    idToOrder[id] = value;
    _onChangedController.add(null);
  }

  void remove(String id) {
    idToOrder.remove(id);
    _onChangedController.add(null);
  }

  bool containsKey(String id) {
    return idToOrder.containsKey(id);
  }
}

abstract class SidebarEntriesComponent<T extends Client>
    implements Component<T> {
  static Stream get onOrderChanged => idToOrder.onChange;

  static StringOrderGenerator idToOrder = StringOrderGenerator();

  static Map<String, StringOrderGenerator> folderOrders = {};

  static StringOrderGenerator getFolderOrder(String folderId) {
    if (folderOrders.containsKey(folderId) == false) {
      folderOrders[folderId] = StringOrderGenerator();
    }

    return folderOrders[folderId]!;
  }

  List<SidebarEntry> getEntries();

  // Vommet: folders take pinned rooms as well as spaces, so these take
  // a [SpaceSidebarEntry] or a [RoomSidebarEntry].

  /// Starts a folder in [target]'s place on the sidebar; returns its id.
  String createFolder(SidebarEntry target);

  void save();

  addToFolder(SidebarEntry entry, String folderId, int index);

  removeFromFolder(SidebarEntry entry, String folderId);

  static SidebarEntriesComponent? of(SidebarEntry entry) => switch (entry) {
        SpaceSidebarEntry e =>
          e.space.client.getComponent<SidebarEntriesComponent>(),
        RoomSidebarEntry e =>
          e.room.client.getComponent<SidebarEntriesComponent>(),
        _ => null,
      };

  static void saveAll(Iterable<Client> clients) {
    for (var client in clients) {
      client.getComponent<SidebarEntriesComponent>()?.save();
    }
  }

  /// Vommet: everything in [folderId] across [clients], in folder order.
  /// A folder can hold spaces from more than one account.
  static List<SidebarEntry> folderMembers(
      String folderId, Iterable<Client> clients) {
    return [
      for (var client in clients)
        for (var entry
            in client.getComponent<SidebarEntriesComponent>()?.getEntries() ??
                const <SidebarEntry>[])
          if (entry is SpaceGroupSidebarEntry && entry.groupId == folderId)
            ...entry.members,
    ]..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Vommet: like Discord, a folder left with one item goes away and that
  /// item takes the folder's place.
  static void tidyFolder(String folderId, Iterable<Client> clients) {
    var members = folderMembers(folderId, clients);
    if (members.length > 1) return;

    var place = idToOrder.get(folderId);
    for (var member in members) {
      of(member)?.removeFromFolder(member, folderId);
      if (place != null) idToOrder.set(member.id, place);
    }

    idToOrder.remove(folderId);
    folderOrders.remove(folderId);
    saveAll(clients);
  }

  /// Vommet: "Delete Folder". Its spaces and rooms go back on the sidebar
  /// where the folder was, in the folder's order.
  static void deleteFolder(String folderId, Iterable<Client> clients) {
    var members = folderMembers(folderId, clients);
    var place = idToOrder.get(folderId);

    for (var i = 0; i < members.length; i++) {
      of(members[i])?.removeFromFolder(members[i], folderId);
      // Extending the folder's key sorts right after it and before the
      // next entry's.
      if (place != null) {
        idToOrder.set(members[i].id, place + i.toString().padLeft(3, "0"));
      }
    }

    idToOrder.remove(folderId);
    folderOrders.remove(folderId);
    saveAll(clients);
  }

  /// Vommet: takes [entry] out of [folderId] and puts it on the sidebar
  /// just below the folder.
  static void moveOutBelowFolder(
      SidebarEntry entry, String folderId, Iterable<Client> clients) {
    var place = idToOrder.get(folderId);
    of(entry)?.removeFromFolder(entry, folderId);
    if (place != null) {
      idToOrder.set(entry.id, "$place~${RandomUtils.getRandomString(4)}");
    }

    saveAll(clients);
    tidyFolder(folderId, clients);
  }

  // Vommet: rooms pinned to the sidebar (#104).
  bool isRoomPinned(Room room);

  void setRoomPinned(Room room, bool pinned);
}
