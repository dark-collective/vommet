import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/client/matrix/components/emoticon/library_store.dart';
import 'package:commet/utils/library_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeClient extends Fake implements matrix.Client {
  @override
  String? get userID => "@me:example.org";

  @override
  final List<matrix.Room> rooms = [];
}

void main() {
  late _FakeClient client;
  late matrix.Room room;

  setUp(() {
    client = _FakeClient();
    room = matrix.Room(id: "!room:example.org", client: client)
      ..membership = matrix.Membership.join;
    client.rooms.add(room);
    room.states[matrix.EventTypes.RoomPowerLevels] = {
      "": matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomPowerLevels,
        stateKey: "",
        senderId: client.userID!,
        content: {"state_default": 0},
      ),
    };
  });

  void putPack(String type, String key, Map<String, dynamic> content,
      {int timestamp = 1}) {
    (room.states[type] ??= {})[key] = matrix.Event(
      type: type,
      stateKey: key,
      content: content,
      eventId: "\$$type-$key-$timestamp",
      senderId: client.userID!,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(timestamp),
      room: room,
    );
  }

  for (final type in ImagePackTypes.roomPackTypes) {
    group(type, () {
      test("deleted packs and their empty room group disappear", () {
        putPack(type, "deleted", LibraryOps.deletedPack());
        expect(LibraryStore.packsOf(room), isEmpty);
        expect(LibraryStore(client).editableRooms, isEmpty);
      });

      test("named empty packs remain editable", () {
        putPack(type, "new", {
          "pack": {"display_name": "New pack"},
          "images": <String, dynamic>{},
        });
        final groups = LibraryStore(client).editableRooms;
        expect(groups, hasLength(1));
        expect(groups.single.packs.single.name, "New pack");
        expect(groups.single.packs.single.images, isEmpty);
      });

      test("packs with images need no pack metadata", () {
        putPack(type, "kept", {
          "images": {
            "cat": {"url": "mxc://example.org/cat"},
          },
        });
        putPack(type, "deleted", LibraryOps.deletedPack());
        expect(
            LibraryStore.packsOf(room).map((pack) => pack.stateKey), ["kept"]);
        expect(LibraryStore(client).editableRooms.single.packs, hasLength(1));
      });

      test("empty or malformed state content stays hidden", () {
        putPack(type, "redacted", {});
        putPack(type, "missing-images", {
          "pack": {"display_name": "Missing images"},
        });
        putPack(type, "invalid-images", {"images": []});
        expect(LibraryStore.packsOf(room), isEmpty);
      });
    });
  }

  test("a newer deletion does not revive the other event type's pack", () {
    for (final deletedType in ImagePackTypes.roomPackTypes) {
      room.states.remove(ImagePackTypes.roomPack);
      room.states.remove(ImagePackTypes.legacyRoomPack);
      for (final type in ImagePackTypes.roomPackTypes) {
        putPack(
            type,
            "cats",
            type == deletedType
                ? LibraryOps.deletedPack()
                : {
                    "pack": {"display_name": "Cats"},
                    "images": {
                      "cat": {"url": "mxc://example.org/cat"},
                    },
                  },
            timestamp: type == deletedType ? 2 : 1);
      }
      expect(LibraryStore.packsOf(room), isEmpty);
      expect(LibraryStore(client).editableRooms, isEmpty);
    }
  });
}
