// A pack the other person stored in a shared direct chat
// showed in our Library's "rooms and spaces" section, since both people can
// usually edit a DM's state. In a DM only packs we stored or turned on
// count as ours; other rooms and spaces we may edit are unchanged.

import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/client/matrix/components/emoticon/library_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const _me = "@me:example.org";
const _them = "@them:example.org";

class _Client extends matrix.Client {
  _Client(super.name, {required super.database});

  @override
  String? get userID => _me;

  @override
  final Map<String, List<String>> directChats = {};
}

matrix.Room _room(_Client client, String id) {
  final room =
      matrix.Room(id: id, client: client, membership: matrix.Membership.join);
  room.setState(matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomPowerLevels,
      content: {
        "users": {_me: 100, _them: 100}
      },
      senderId: _them,
      stateKey: ""));
  client.rooms.add(room);
  return room;
}

void _pack(matrix.Room room, String key, String sender,
        {String type = ImagePackTypes.roomPack}) =>
    room.setState(matrix.StrippedStateEvent(
        type: type,
        content: {
          "pack": {"display_name": key},
          "images": {
            "cat": {"url": "mxc://example.org/$key"}
          },
        },
        senderId: sender,
        stateKey: key));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _Client client;
  late matrix.Room dm;
  late matrix.Room group;

  setUp(() async {
    client = _Client("library-dm-packs-test",
        database: await MatrixSdkDriftDatabase.init(
            NativeDatabase.memory(), "library dm packs test"));
    dm = _room(client, "!dm:example.org");
    group = _room(client, "!group:example.org");
    client.directChats[_them] = [dm.id];
  });

  List<String> listed(matrix.Room room) => [
        for (final r in LibraryStore(client).editableRooms)
          if (r.room.id == room.id) ...r.packs.map((p) => p.stateKey),
      ];

  test("the other person's pack in a shared DM isn't listed", () {
    _pack(dm, "theirs", _them);
    expect(dm.isDirectChat, isTrue);
    expect(listed(dm), isEmpty);
  });

  test("our own pack in a DM is still listed", () {
    _pack(dm, "theirs", _them);
    _pack(dm, "mine", _me);
    expect(listed(dm), ["mine"]);
  });

  test("a DM pack we turned on everywhere is listed", () {
    _pack(dm, "theirs", _them);
    client.accountData[ImagePackTypes.enabledRooms] =
        matrix.BasicEvent(type: ImagePackTypes.enabledRooms, content: {
      "rooms": {
        dm.id: {"theirs": {}}
      }
    });
    expect(listed(dm), ["theirs"]);
  });

  test("packs in other rooms we may edit are listed whoever wrote them", () {
    _pack(group, "theirs", _them);
    expect(listed(group), ["theirs"]);
  });

  test("a DM pack we stored under the legacy type is listed", () {
    _pack(dm, "mine", _me, type: ImagePackTypes.legacyRoomPack);
    expect(listed(dm), ["mine"]);
  });

  test("the newer of the two pack types decides who stored it", () {
    matrix.Event event(String type, String sender, int ts) => matrix.Event(
        type: type,
        content: {
          "images": {
            "cat": {"url": "mxc://example.org/cat"}
          }
        },
        eventId: "\$$type-$ts",
        senderId: sender,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
        stateKey: "both",
        room: dm);
    dm.setState(event(ImagePackTypes.roomPack, _them, 1000));
    dm.setState(event(ImagePackTypes.legacyRoomPack, _me, 2000));
    expect(listed(dm), ["both"]);
    dm.setState(event(ImagePackTypes.roomPack, _them, 3000));
    expect(listed(dm), isEmpty);
  });

  // Known limit: only the current state event's sender is known, so a pack
  // we made in a DM drops out once the other person edits it (unless it is
  // turned on everywhere).
  test("our DM pack edited by the other person is no longer listed", () {
    _pack(dm, "mine", _me);
    expect(listed(dm), ["mine"]);
    _pack(dm, "mine", _them);
    expect(listed(dm), isEmpty);
  });
}
