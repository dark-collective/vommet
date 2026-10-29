import 'package:commet/client/matrix/nicknames/name_history.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:test/test.dart';

matrix.MatrixEvent member(String userId, int ts, String? name,
        {String membership = "join", String? sender}) =>
    matrix.MatrixEvent.fromJson({
      "event_id": "\$$userId$ts",
      "room_id": "!room:a.org",
      "sender": sender ?? userId,
      "origin_server_ts": ts,
      "type": "m.room.member",
      "state_key": userId,
      "content": {
        "membership": membership,
        if (name != null) "displayname": name,
      },
    });

void main() {
  // Vommet identity per place, phase 4: moderator name history (R7).
  const who = "@wren:a.org";

  test('one entry per name change, newest first', () {
    final changes = NameHistory.changesFrom([
      member(who, 3000, "Admin"),
      member(who, 1000, "Wren"),
      member(who, 2000, "Wren"),
      member(who, 4000, "Admin"),
    ], who);
    expect(changes.map((c) => c.name), ["Admin", "Wren"]);
    expect(changes.first.time.millisecondsSinceEpoch, 3000);
  });

  test('a cleared name shows as no name', () {
    final changes = NameHistory.changesFrom([
      member(who, 1000, "Wren"),
      member(who, 2000, null),
      member(who, 3000, " "),
    ], who);
    expect(changes.map((c) => c.name), [null, "Wren"]);
  });

  test('leaves and other people are left out', () {
    final changes = NameHistory.changesFrom([
      member(who, 1000, "Wren"),
      member(who, 2000, "Gone", membership: "leave"),
      member("@other:a.org", 3000, "Other"),
    ], who);
    expect(changes.map((c) => c.name), ["Wren"]);
  });
}
