// Vommet issue 667: rooms the server dropped us from without a leave (a
// room purged by a Synapse admin) are found and can be rejoined through
// other servers.
import 'package:commet/client/matrix/matrix_removed_rooms.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

matrix.MatrixException forbidden(String message) =>
    matrix.MatrixException.fromJson({
      "errcode": "M_FORBIDDEN",
      "error": message,
    });

void main() {
  group("isNotInRoomError", () {
    test("Synapse's not-in-room refusal", () {
      expect(
          MatrixRemovedRooms.isNotInRoomError(
              forbidden("User @a:example.org not in room !r:example.org")),
          isTrue);
    });

    test("Conduit-style wording", () {
      expect(
          MatrixRemovedRooms.isNotInRoomError(
              forbidden("You are not joined to this room.")),
          isTrue);
    });

    test("other refusals don't count", () {
      expect(
          MatrixRemovedRooms.isNotInRoomError(
              forbidden("You don't have permission to post that to the room.")),
          isFalse);
      expect(
          MatrixRemovedRooms.isNotInRoomError(matrix.MatrixException.fromJson(
              {"errcode": "M_LIMIT_EXCEEDED", "error": "not in room"})),
          isFalse);
      expect(MatrixRemovedRooms.isNotInRoomError(Exception("not in room")),
          isFalse);
    });
  });

  test("notJoined lists the rooms the server doesn't have us in", () {
    expect(
        MatrixRemovedRooms.notJoined(
            ["!a:x.org", "!b:x.org", "!c:y.org"], ["!a:x.org", "!c:y.org"]),
        {"!b:x.org"});
    expect(MatrixRemovedRooms.notJoined(["!a:x.org"], ["!a:x.org", "!z:x.org"]),
        isEmpty);
  });

  group("viaServers", () {
    test("room id's server first, then the busiest member servers", () {
      expect(
          MatrixRemovedRooms.viaServers(
              "!r:origin.org",
              [
                "@me:home.org",
                "@a:big.org",
                "@b:big.org",
                "@c:small.org",
                "@d:other.org",
                "@e:other.org",
                "@f:home.org",
              ],
              ownServer: "home.org"),
          ["origin.org", "big.org", "other.org"]);
    });

    test("leaves out our own server, even as the room's server", () {
      expect(
          MatrixRemovedRooms.viaServers(
              "!r:home.org", ["@me:home.org", "@a:far.org"],
              ownServer: "home.org"),
          ["far.org"]);
    });

    test("room ids without a server (room version 12)", () {
      expect(
          MatrixRemovedRooms.viaServers("!abcdef", ["@a:far.org"],
              ownServer: "home.org"),
          ["far.org"]);
    });
  });

  test("serverOf", () {
    expect(MatrixRemovedRooms.serverOf("@a:b.org"), "b.org");
    expect(MatrixRemovedRooms.serverOf("@a:b.org:8448"), "b.org:8448");
    expect(MatrixRemovedRooms.serverOf("!abcdef"), isNull);
  });
}
