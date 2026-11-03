// Vommet issues 32 and 100: messages that failed to decrypt before this
// device was verified are asked for again (from the other devices and the
// backup) once it is, so they decrypt without "Retry Decrypt".

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/components/utd_retry/matrix_utd_retry_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

class _Request {
  _Request(this.sessionId, this.tryOnlineBackup, this.onlineKeyBackupOnly);
  final String sessionId;
  final bool tryOnlineBackup;
  final bool onlineKeyBackupOnly;
}

class _FakeKeyManager extends Fake implements KeyManager {
  bool cached = false;
  final List<_Request> requests = [];

  @override
  Future<bool> isCached() async => cached;

  @override
  Future<void> request(matrix.Room room, String sessionId, String? senderKey,
      {bool tryOnlineBackup = true, bool onlineKeyBackupOnly = false}) async {
    requests.add(_Request(sessionId, tryOnlineBackup, onlineKeyBackupOnly));
  }
}

class _FakeEncryption extends Fake implements Encryption {
  _FakeEncryption(this.keyManager);

  @override
  final KeyManager keyManager;
}

class _FakeSdkClient extends Fake implements matrix.Client {
  _FakeSdkClient(this.encryption);

  @override
  final Encryption? encryption;

  @override
  bool get encryptionEnabled => true;

  bool unknownSession = true;

  @override
  bool get isUnknownSession => unknownSession;
}

class _FakeSdkRoom extends Fake implements matrix.Room {
  @override
  final String id = "!room:example.org";
}

class _FakeSdkTimeline extends Fake implements matrix.Timeline {
  _FakeSdkTimeline(this.room, this.events);

  @override
  final matrix.Room room;

  @override
  final List<matrix.Event> events;
}

class _FakeTimeline extends Fake implements MatrixTimeline {
  _FakeTimeline(this.matrixTimeline);

  @override
  final matrix.Timeline? matrixTimeline;
}

class _FakeRoom extends Fake implements MatrixRoom {
  _FakeRoom(this.timeline);

  @override
  Timeline? timeline;
}

class _FakeMatrixClient extends Fake implements MatrixClient {
  _FakeMatrixClient(this.matrixClient, List<Room> rooms)
      : rooms = NotifyingList.from(rooms);

  @override
  final matrix.Client matrixClient;

  @override
  final NotifyingList<Room> rooms;
}

matrix.Event _event(matrix.Room room, String id,
        {String type = matrix.EventTypes.Encrypted,
        String? sessionId,
        bool requestable = true}) =>
    matrix.Event(
      type: type,
      content: {
        if (sessionId != null) "session_id": sessionId,
        "sender_key": "senderkey",
        "can_request_session": requestable,
      },
      eventId: id,
      senderId: "@alice:example.org",
      originServerTs: DateTime(2026, 10, 20),
      room: room,
    );

void main() {
  late _FakeKeyManager keys;
  late _FakeSdkClient mx;
  late MatrixUtdRetryComponent component;
  late _FakeRoom openRoom;

  setUp(() {
    keys = _FakeKeyManager();
    mx = _FakeSdkClient(_FakeEncryption(keys));
    final room = _FakeSdkRoom();
    final timeline = _FakeSdkTimeline(room, [
      _event(room, "\$a", sessionId: "s1"),
      _event(room, "\$b", sessionId: "s1"),
      _event(room, "\$c", sessionId: "s2"),
      _event(room, "\$d", sessionId: "s3", requestable: false),
      _event(room, "\$e", type: matrix.EventTypes.Message),
    ]);
    openRoom = _FakeRoom(_FakeTimeline(timeline));
    component = MatrixUtdRetryComponent(_FakeMatrixClient(mx, [openRoom]),
        listenToSync: false);
  });

  test("undecryptable sessions are distinct and requestable only", () {
    final room = _FakeSdkRoom();
    final sessions = MatrixUtdRetryComponent.undecryptableSessions([
      _event(room, "\$a", sessionId: "s1"),
      _event(room, "\$b", sessionId: "s1"),
      _event(room, "\$c", sessionId: "s2", requestable: false),
      _event(room, "\$d"),
      _event(room, "\$e", sessionId: "s3", type: matrix.EventTypes.Message),
    ]);
    expect(sessions.map((s) => s.sessionId), ["s1"]);
  });

  test("nothing is asked while the device stays unverified", () async {
    await component.check();
    await component.check();
    expect(keys.requests, isEmpty);
  });

  test("becoming verified asks the other devices once per session", () async {
    await component.check();
    mx.unknownSession = false;
    await component.check();
    expect(keys.requests.map((r) => r.sessionId), ["s1", "s2"]);
    expect(keys.requests.every((r) => !r.onlineKeyBackupOnly), isTrue);

    await component.check();
    expect(keys.requests, hasLength(2), reason: "asked only once");
  });

  test("the backup key is looked for at most every 30 s", () async {
    await component.check();
    keys.cached = true;
    await component.check();
    expect(keys.requests, isEmpty);
  });

  test("a device verified with the backup key cached tries both", () async {
    keys.cached = true;
    await component.check();
    // The backup key was found on the first look: asked from the backup.
    expect(keys.requests.map((r) => r.sessionId), ["s1", "s2"]);
    expect(keys.requests.every((r) => r.onlineKeyBackupOnly), isTrue);

    mx.unknownSession = false;
    await component.check();
    expect(keys.requests.skip(2).map((r) => r.sessionId), ["s1", "s2"]);
    expect(
        keys.requests
            .skip(2)
            .every((r) => r.tryOnlineBackup && !r.onlineKeyBackupOnly),
        isTrue);
  });

  test("a room opened while unverified without the backup asks nothing",
      () async {
    await component.roomOpened(openRoom);
    expect(keys.requests, isEmpty);
  });

  test(
      "a room that wasn't open when the device was verified is asked for "
      "when it's opened", () async {
    final timeline = openRoom.timeline;
    openRoom.timeline = null;
    await component.check();
    mx.unknownSession = false;
    await component.check();
    expect(keys.requests, isEmpty, reason: "no room was open");

    openRoom.timeline = timeline;
    await component.roomOpened(openRoom);
    expect(keys.requests.map((r) => r.sessionId), ["s1", "s2"]);
    expect(keys.requests.every((r) => !r.onlineKeyBackupOnly), isTrue);

    await component.roomOpened(openRoom);
    expect(keys.requests, hasLength(2), reason: "asked only once");
  });

  test("asking the devices before the backup key came still asks the backup",
      () async {
    mx.unknownSession = false;
    await component.roomOpened(openRoom);
    expect(keys.requests.every((r) => !r.tryOnlineBackup), isTrue);

    // The backup key arrives while the room is closed, then it's opened.
    final timeline = openRoom.timeline;
    openRoom.timeline = null;
    keys.cached = true;
    await component.check();
    openRoom.timeline = timeline;
    await component.roomOpened(openRoom);
    expect(keys.requests.skip(2).map((r) => r.sessionId), ["s1", "s2"]);
    expect(keys.requests.skip(2).every((r) => r.onlineKeyBackupOnly), isTrue);
  });
}
