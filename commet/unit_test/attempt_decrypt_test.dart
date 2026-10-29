// Vommet issue 100: attemptDecrypt checked the room against
// MatrixTimelineEvent, which a room never is, so it always returned null and
// the legacy Android notification handler never got a second chance to
// decrypt a message.

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeEncryption extends Fake implements Encryption {
  _FakeEncryption(this.decrypt);

  final matrix.Event Function(matrix.Event) decrypt;
  int calls = 0;

  @override
  Future<matrix.Event> decryptRoomEvent(matrix.Event event,
      {bool store = false,
      matrix.EventUpdateType updateType =
          matrix.EventUpdateType.timeline}) async {
    calls++;
    return decrypt(event);
  }
}

class _FakeSdkClient extends Fake implements matrix.Client {
  _FakeSdkClient(this.encryption);

  @override
  final Encryption? encryption;
}

class _FakeSdkRoom extends Fake implements matrix.Room {
  _FakeSdkRoom(this.client);

  @override
  final String id = "!room:example.org";

  @override
  final matrix.Client client;
}

class _FakeMatrixClient extends Fake implements MatrixClient {}

class _ConvertedEvent extends Fake implements TimelineEvent {
  _ConvertedEvent(this.from);

  final matrix.Event from;
}

class _FakeMatrixRoom extends Fake implements MatrixRoom {
  @override
  TimelineEvent convertEvent(matrix.Event event, {matrix.Timeline? timeline}) =>
      _ConvertedEvent(event);
}

class _OtherRoom extends Fake implements Room {}

matrix.Event _encryptedEvent(matrix.Room room) => matrix.Event(
      content: {
        "algorithm": "m.megolm.v1.aes-sha2",
        "ciphertext": "AwgAEnAC",
        "session_id": "session",
        "sender_key": "sender",
        "device_id": "DEVICE",
      },
      type: matrix.EventTypes.Encrypted,
      eventId: "\$event",
      senderId: "@alice:example.org",
      originServerTs: DateTime(2026, 10, 10),
      room: room,
    );

matrix.Event _decryptedFrom(matrix.Event event) => matrix.Event(
      content: {"msgtype": "m.text", "body": "hello"},
      type: matrix.EventTypes.Message,
      eventId: event.eventId,
      senderId: event.senderId,
      originServerTs: event.originServerTs,
      room: event.room,
    );

MatrixTimelineEventEncrypted _timelineEvent(Encryption? encryption) =>
    MatrixTimelineEventEncrypted(
        _encryptedEvent(_FakeSdkRoom(_FakeSdkClient(encryption))),
        client: _FakeMatrixClient());

void main() {
  test("a room that isn't a Matrix room gives nothing", () async {
    var encryption = _FakeEncryption(_decryptedFrom);
    var event = _timelineEvent(encryption);

    expect(await event.attemptDecrypt(_OtherRoom()), isNull);
    expect(encryption.calls, 0);
  });

  test("a Matrix room decrypts the event once the key is there", () async {
    var encryption = _FakeEncryption(_decryptedFrom);
    var event = _timelineEvent(encryption);

    var result = await event.attemptDecrypt(_FakeMatrixRoom());

    expect(encryption.calls, 1);
    expect(result, isA<_ConvertedEvent>());
    var from = (result as _ConvertedEvent).from;
    expect(from.type, matrix.EventTypes.Message);
    expect(from.eventId, "\$event");
  });

  test("an event that still can't be decrypted gives nothing", () async {
    var encryption = _FakeEncryption((event) => event);
    var event = _timelineEvent(encryption);

    expect(await event.attemptDecrypt(_FakeMatrixRoom()), isNull);
    expect(encryption.calls, 1);
  });

  test("a client without encryption gives nothing", () async {
    var event = _timelineEvent(null);

    expect(await event.attemptDecrypt(_FakeMatrixRoom()), isNull);
  });
}
