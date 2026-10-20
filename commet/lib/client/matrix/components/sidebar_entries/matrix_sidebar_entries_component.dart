import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/space.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/rng.dart';
import 'package:matrix/matrix_api_lite/model/sync_update.dart';
import 'package:matrix/matrix_api_lite/utils/try_get_map_extension.dart';
import 'package:uuid/uuid.dart';

class MatrixSidebarEntryData {
  String? folderId;
  String? order;

  MatrixSidebarEntryData({this.folderId, this.order});

  Map<String, dynamic> toJson() {
    return {
      if (folderId != null) "group": folderId,
      if (order != null) "order": order
    };
  }
}

class MatrixSidebarEntriesComponent
    implements SidebarEntriesComponent<MatrixClient>, NeedsPostLoginInit {
  @override
  MatrixClient client;

  MatrixSidebarEntriesComponent(this.client) {}

  @override
  void postLoginInit() {
    try {
      loadOrderFromAccountData();
    } catch (e, s) {
      Log.onError(e, s);
    }

    try {
      var pins = client.matrixClient.accountData[pinnedRoomsKey];
      if (pins != null) loadPinnedRooms(pins.content);
    } catch (e, s) {
      Log.onError(e, s);
    }

    client.matrixClient.onSync.stream.listen(_onSync);
  }

  void _onSync(SyncUpdate event) {
    if (event.accountData == null) return;

    for (var ev in event.accountData!) {
      if (ev.type == key) {
        loadFromContent(ev.content);
      }

      if (ev.type == pinnedRoomsKey) {
        loadPinnedRooms(ev.content);
      }
    }
  }

  void loadOrderFromAccountData() {
    var data = client.matrixClient.accountData[key];

    if (data == null) return;

    var content = data.content as Map<String, dynamic>;
    loadFromContent(content);
  }

  void loadFromContent(Map<String, dynamic> content) {
    var spaceData = content.tryGetMap<String, dynamic>("spaces");

    if (spaceData != null) {
      for (var entry in spaceData.entries) {
        var id = entry.key;

        var entryData = entry.value as Map<String, dynamic>;

        var order = entryData.tryGet<String>("order");
        var group = entryData.tryGet<String>("group");
        var space = client.getSpace(id);

        // Keep loading the rest: a space we left, or one not loaded yet,
        // must not drop the saved order of every space after it.
        if (space == null) {
          Log.w("Could not find space for ordering: $id");
          continue;
        }

        if (group != null) {
          spaceToFolder[id] = group;
          if (order != null) {
            var orderGen = SidebarEntriesComponent.getFolderOrder(group);
            orderGen.set(space.localId, order);
          }
        } else {
          // Vommet: taken out of its folder on another device.
          spaceToFolder.remove(id);
          if (order != null) {
            SidebarEntriesComponent.idToOrder.set(space.localId, order);
          }
        }
      }
    } else {
      Log.w("Could not find any ordering data for spaces");
    }

    var groupData = content.tryGetMap<String, dynamic>("groups");
    if (groupData != null) {
      for (var entry in groupData.entries) {
        var id = entry.key;
        var entryData = entry.value as Map<String, dynamic>;
        var order = entryData.tryGet<String>("order");
        if (order != null) {
          SidebarEntriesComponent.idToOrder.set(id, order);
        }
      }
    } else {
      Log.w("Could not find any ordering data for groups");
    }
  }

  Map<String, String> spaceToFolder = {};

  Debouncer serializeDebouncer = Debouncer(delay: Duration(seconds: 10));

  static const key = "chat.commet.sidebar_ordering";

  void serialize() {
    var spaces = client.spaces.where((i) => i.isTopLevel);

    Map<String, MatrixSidebarEntryData> data = {};

    Set<String> knownGroups = {};

    for (var space in spaces) {
      String? order = getOrder(space);
      var folder = spaceToFolder[space.identifier];

      if (folder != null) {
        knownGroups.add(folder);
        var orderGen = SidebarEntriesComponent.getFolderOrder(folder);
        order = orderGen.get(space.localId);
      }

      data[space.identifier] =
          MatrixSidebarEntryData(order: order, folderId: folder);
    }

    var spaceData = Map<String, dynamic>.new();

    for (var entry in data.entries) {
      spaceData[entry.key] = entry.value.toJson();
    }

    var groupData = Map<String, Map<String, dynamic>>.new();

    for (var key in knownGroups) {
      var order = SidebarEntriesComponent.idToOrder.get(key);
      if (order != null) {
        groupData[key] = {"order": order};
      }
    }

    var result = {
      "spaces": spaceData,
      if (groupData.isNotEmpty) "groups": groupData,
    };

    client.matrixClient
        .setAccountData(client.matrixClient.userID!, key, result);

    serializePinnedRooms();
  }

  // Vommet: rooms pinned to the sidebar (#104). They live in their own
  // event because serialize() above rewrites [key] with only spaces and
  // folders, so pins stored there would be wiped by a Commet elsewhere.
  static const pinnedRoomsKey = "im.nether.chat.sidebar_rooms";

  /// Pinned room id -> its saved order. Keeps rooms that aren't loaded
  /// (or that we've left) so a pin isn't lost before the room appears.
  Map<String, String?> pinnedRooms = {};

  /// Pinned room id -> the folder it's in. Its order then lives in that
  /// folder's order, like a space's.
  Map<String, String> roomToFolder = {};

  void loadPinnedRooms(Map<String, dynamic> content) {
    var rooms = content.tryGetMap<String, dynamic>("rooms") ?? {};

    var loaded = <String, String?>{
      for (var entry in rooms.entries)
        entry.key: switch (entry.value) {
          {"order": String order} => order,
          _ => null,
        }
    };

    // Unpinned on another device.
    for (var id in pinnedRooms.keys.where((i) => !loaded.containsKey(i))) {
      var room = client.getRoom(id);
      if (room != null) SidebarEntriesComponent.idToOrder.remove(room.localId);
    }

    pinnedRooms = loaded;
    roomToFolder = {
      for (var entry in rooms.entries)
        if (entry.value case {"group": String group}) entry.key: group,
    };

    for (var entry in loaded.entries) {
      var room = client.getRoom(entry.key);
      if (room == null || entry.value == null) continue;

      if (roomToFolder[entry.key] case String folder) {
        SidebarEntriesComponent.idToOrder.remove(room.localId);
        SidebarEntriesComponent.getFolderOrder(folder)
            .set(room.localId, entry.value!);
      } else {
        SidebarEntriesComponent.idToOrder.set(room.localId, entry.value!);
      }
    }

    // A folder holding only rooms has its place saved here, since the
    // shared event only keeps folders that hold a space.
    var groups = content.tryGetMap<String, dynamic>("groups") ?? {};
    for (var entry in groups.entries) {
      if (entry.value case {"order": String order}) {
        SidebarEntriesComponent.idToOrder.set(entry.key, order);
      }
    }
  }

  void serializePinnedRooms() {
    var hasEvent = client.matrixClient.accountData[pinnedRoomsKey] != null;
    if (pinnedRooms.isEmpty && !hasEvent) return;

    for (var id in pinnedRooms.keys.toList()) {
      var room = client.getRoom(id);
      var folder = roomToFolder[id];
      var order = room == null
          ? null
          : folder != null
              ? SidebarEntriesComponent.getFolderOrder(folder).get(room.localId)
              : SidebarEntriesComponent.idToOrder.get(room.localId);
      if (order != null) pinnedRooms[id] = order;
    }

    var groups = {
      for (var folder in roomToFolder.values.toSet())
        if (SidebarEntriesComponent.idToOrder.get(folder) case String order)
          folder: {"order": order},
    };

    var result = {
      "rooms": {
        for (var entry in pinnedRooms.entries)
          entry.key: {
            if (entry.value != null) "order": entry.value,
            if (roomToFolder[entry.key] != null)
              "group": roomToFolder[entry.key],
          },
      },
      if (groups.isNotEmpty) "groups": groups,
    };

    client.matrixClient
        .setAccountData(client.matrixClient.userID!, pinnedRoomsKey, result);
  }

  String getRoomOrder(Room room) {
    var order = SidebarEntriesComponent.idToOrder.get(room.localId);
    if (order != null) return order;

    // '~' sorts after the generated keys, so a new pin goes to the bottom.
    order = pinnedRooms[room.identifier] ?? "~${room.identifier}";
    SidebarEntriesComponent.idToOrder.set(room.localId, order);
    return order;
  }

  @override
  bool isRoomPinned(Room room) => pinnedRooms.containsKey(room.identifier);

  @override
  void setRoomPinned(Room room, bool pinned) {
    if (pinned) {
      pinnedRooms[room.identifier] = null;
      getRoomOrder(room);
    } else {
      pinnedRooms.remove(room.identifier);
      SidebarEntriesComponent.idToOrder.remove(room.localId);

      if (roomToFolder.remove(room.identifier) case String folder) {
        SidebarEntriesComponent.tidyFolder(
            folder, clientManager?.clients ?? [client]);
      }
    }

    // Pinning and unpinning are explicit, so don't wait for the debounce.
    serializePinnedRooms();
  }

  @override
  List<SidebarEntry> getEntries() {
    var spaces = client.spaces
        .where((i) =>
            i.isTopLevel && spaceToFolder.containsKey(i.identifier) == false)
        .map((i) => SpaceSidebarEntry(i, order: getOrder(i)))
        .toList();

    var spacesInFolders = client.spaces
        .where((i) => spaceToFolder.containsKey(i.identifier) && i.isTopLevel);

    Map<String, SpaceGroupSidebarEntry> folders = {};

    var showRooms = preferences.experimentSidebarPinnedRooms.value;

    for (var value in [
      ...spaceToFolder.values,
      if (showRooms) ...roomToFolder.values,
    ]) {
      folders[value] ??= SpaceGroupSidebarEntry(
          value, List.empty(growable: true),
          order: getGroupOrder(value));
    }

    for (var space in spacesInFolders) {
      var folder = spaceToFolder[space.identifier]!;
      var order = SidebarEntriesComponent.getFolderOrder(folder);

      if (order.containsKey(space.localId) == false) {
        order.set(space.localId, RandomUtils.getRandomString(10));
      }

      folders[folder]!
          .spaces
          .add(SpaceSidebarEntry(space, order: order.get(space.localId)!));
    }

    var rooms = <RoomSidebarEntry>[];
    if (showRooms) {
      for (var id in pinnedRooms.keys) {
        var room = client.getRoom(id);
        if (room == null) continue;

        if (roomToFolder[id] case String folder) {
          var order = SidebarEntriesComponent.getFolderOrder(folder);
          if (order.containsKey(room.localId) == false) {
            order.set(room.localId, RandomUtils.getRandomString(10));
          }

          folders[folder]!
              .rooms
              .add(RoomSidebarEntry(room, order: order.get(room.localId)!));
        } else {
          rooms.add(RoomSidebarEntry(room, order: getRoomOrder(room)));
        }
      }
    }

    return [...spaces, ...rooms, ...folders.values];
  }

  String getOrder(Space space) {
    if (SidebarEntriesComponent.idToOrder.containsKey(space.localId) == false) {
      var defaultOrder =
          "__" + space.client.identifier + "_" + space.identifier;
      SidebarEntriesComponent.idToOrder.set(space.localId, defaultOrder);
    }

    return SidebarEntriesComponent.idToOrder.get(space.localId)!;
  }

  String getGroupOrder(String key) {
    if (SidebarEntriesComponent.idToOrder.containsKey(key) == false) {
      var defaultOrder = "__" + key;
      SidebarEntriesComponent.idToOrder.set(key, defaultOrder);
    }

    return SidebarEntriesComponent.idToOrder.get(key)!;
  }

  @override
  String createFolder(SidebarEntry target) {
    var folderId = Uuid().v4();

    var order =
        SidebarEntriesComponent.idToOrder.get(target.id) ?? target.order;
    addToFolder(target, folderId, 0);
    SidebarEntriesComponent.idToOrder.set(folderId, order);

    return folderId;
  }

  @override
  addToFolder(SidebarEntry entry, String folderId, int index) {
    String? previous;
    switch (entry) {
      case SpaceSidebarEntry e:
        previous = spaceToFolder[e.space.identifier];
        spaceToFolder[e.space.identifier] = folderId;
      case RoomSidebarEntry e:
        previous = roomToFolder[e.room.identifier];
        roomToFolder[e.room.identifier] = folderId;
      default:
        return;
    }

    SidebarEntriesComponent.idToOrder.remove(entry.id);
    var order = SidebarEntriesComponent.getFolderOrder(folderId);

    order.setIndex(entry.id, index);

    // Vommet: moved from another folder, which may now hold only one item.
    if (previous != null && previous != folderId) {
      SidebarEntriesComponent.getFolderOrder(previous).remove(entry.id);
      SidebarEntriesComponent.tidyFolder(
          previous, clientManager?.clients ?? [client]);
    }
  }

  @override
  removeFromFolder(SidebarEntry entry, String folderId) {
    SidebarEntriesComponent.getFolderOrder(folderId).remove(entry.id);

    switch (entry) {
      case SpaceSidebarEntry e:
        spaceToFolder.remove(e.space.identifier);
        getOrder(e.space);
      case RoomSidebarEntry e:
        roomToFolder.remove(e.room.identifier);
        getRoomOrder(e.room);
    }
  }

  @override
  void save() {
    serializeDebouncer.run(serialize);
  }
}
