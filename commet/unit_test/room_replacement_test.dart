// Vommet: replacing a room (m.room.tombstone): the tombstone's content, the
// space swap (same order and suggested flag), who gets invited, which rooms
// the sidebar hides, the room version choice, and the composer notice.
import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/composer_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tombstone content', () {
    test('names the replacement and keeps the message', () {
      expect(
          buildTombstoneContent(
              "!new:example.org", "  We moved! Come say hi  ", "fallback"),
          {
            "body": "We moved! Come say hi",
            "replacement_room": "!new:example.org"
          });
    });

    test('an empty message falls back', () {
      expect(
          buildTombstoneContent("!new", "   ", "This room has been replaced"),
          {"body": "This room has been replaced", "replacement_room": "!new"});
      expect(buildTombstoneContent("!new", null, "x")["body"], "x");
    });

    test('parses what it builds', () {
      final stone = parseTombstone(buildTombstoneContent("!new", "hello", "x"),
          senderId: "@ember:example.org");
      expect(stone?.replacementRoomId, "!new");
      expect(stone?.body, "hello");
      expect(stone?.senderId, "@ember:example.org");
    });

    test('a tombstone without a replacement is ignored', () {
      expect(parseTombstone(null), isNull);
      expect(parseTombstone({"body": "gone"}), isNull);
      expect(parseTombstone({"replacement_room": ""}), isNull);
      expect(parseTombstone({"replacement_room": 5}), isNull);
      expect(parseTombstone({"replacement_room": "!new"})?.body, isNull);
    });
  });

  group('predecessor', () {
    test('reads m.room.create predecessor', () {
      expect(
          parsePredecessorRoomId({
            "predecessor": {"room_id": "!old:example.org", "event_id": "\$x"}
          }),
          "!old:example.org");
    });

    test('none when missing or malformed', () {
      expect(parsePredecessorRoomId(null), isNull);
      expect(parsePredecessorRoomId({"creator": "@a:b"}), isNull);
      expect(parsePredecessorRoomId({"predecessor": "!old"}), isNull);
      expect(parsePredecessorRoomId({"predecessor": {}}), isNull);
    });
  });

  group('space swap', () {
    test('keeps order and suggested, uses the new via', () {
      expect(
          swappedSpaceChildContent({
            "via": ["old.example"],
            "order": "b0",
            "suggested": true,
          }, [
            "example.org"
          ]),
          {
            "via": ["example.org"],
            "order": "b0",
            "suggested": true,
          });
    });

    test('leaves out an order or suggested flag that was never set', () {
      expect(
          swappedSpaceChildContent({
            "via": ["old.example"],
            "order": 3,
          }, [
            "example.org"
          ]),
          {
            "via": ["example.org"]
          });
    });

    test('via: ours first, then the old ones, no repeats, at most three', () {
      expect(
          replacementVia("example.org",
              ["other.example", "example.org", "third.example", "fourth"]),
          ["example.org", "other.example", "third.example"]);
      expect(replacementVia(null, ["a.example", 7, ""]), ["a.example"]);
      expect(replacementVia("example.org", null), ["example.org"]);
    });
  });

  group('invites', () {
    test('everyone joined but you and those already there', () {
      expect(
          membersToInvite(
              ["@me:x", "@nova:x", "@ember:y", "@juniper:z", "@nova:x"],
              "@me:x",
              {"@ember:y"}),
          ["@nova:x", "@juniper:z"]);
    });

    test('ticked by default unless anyone can join', () {
      expect(defaultInviteMembers(RoomVisibilityPrivate()), isTrue);
      expect(
          defaultInviteMembers(RoomVisibilityRestricted(["!space"])), isTrue);
      expect(defaultInviteMembers(RoomVisibilityPublic()), isFalse);
    });
  });

  group('sidebar', () {
    const stone = RoomTombstone(replacementRoomId: "!new");

    test('hides a replaced room once you are in its replacement', () {
      expect(shouldHideReplacedRoom(stone, (id) => id == "!new"), isTrue);
    });

    test('keeps it while you are not', () {
      expect(shouldHideReplacedRoom(stone, (_) => false), isFalse);
    });

    test('never hides a room that was not replaced', () {
      expect(shouldHideReplacedRoom(null, (_) => true), isFalse);
    });
  });

  group('room versions', () {
    test('sorts numerically, newest first', () {
      expect(sortRoomVersions(["9", "10", "11", "1", "2"]),
          ["11", "10", "9", "2", "1"]);
      expect(compareRoomVersions("10", "9"), greaterThan(0));
    });

    test('starts on the newest stable when newer than the default', () {
      const options = RoomVersionOptions(
          defaultVersion: "10",
          stable: ["9", "10", "11"],
          unstable: ["org.example.12"]);
      expect(options.newestStable, "11");
      expect(options.initialChoice, "11");
      expect(options.all, ["11", "10", "9", "org.example.12"]);
    });

    test('otherwise on the server default', () {
      const options =
          RoomVersionOptions(defaultVersion: "12", stable: ["10", "11"]);
      expect(options.initialChoice, "12");
      const none = RoomVersionOptions(defaultVersion: "10", stable: []);
      expect(none.newestStable, isNull);
      expect(none.initialChoice, "10");
    });
  });

  group('composer notice text', () {
    test('shows the replacer\'s own message', () {
      expect(
          replacedNoticeMessage(const RoomTombstone(
              replacementRoomId: "!n", body: "We moved to the new lobby")),
          "We moved to the new lobby");
    });

    test('skips missing or stock messages', () {
      expect(replacedNoticeMessage(null), isNull);
      expect(
          replacedNoticeMessage(const RoomTombstone(replacementRoomId: "!n")),
          isNull);
      for (final body in [
        "This room has been replaced",
        "This room has been replaced.",
        "this room was upgraded!",
      ]) {
        expect(
            replacedNoticeMessage(
                RoomTombstone(replacementRoomId: "!n", body: body)),
            isNull,
            reason: body);
      }
    });
  });

  group('room picker search', () {
    test('every word matches the name or id', () {
      expect(roomMatchesQuery("lobby-2026", "!abc:example.org", ""), isTrue);
      expect(
          roomMatchesQuery("Lobby 2026", "!abc:example.org", "lob 26"), isTrue);
      expect(roomMatchesQuery("Lobby", "!abc:example.org", "example"), isTrue);
      expect(roomMatchesQuery("Lobby", "!abc:example.org", "lounge"), isFalse);
    });
  });

  group('ComposerNotice icon colour', () {
    Future<Color?> iconColor(WidgetTester tester, {Color? override}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ComposerNotice(
              icon: Icons.moving, title: "Notice", iconColor: override),
        ),
      ));
      return tester.widget<Icon>(find.byIcon(Icons.moving)).color;
    }

    testWidgets('defaults to the error colour', (tester) async {
      final color = await iconColor(tester);
      final context = tester.element(find.byType(ComposerNotice));
      expect(color, Theme.of(context).colorScheme.error);
    });

    testWidgets('takes an override', (tester) async {
      expect(await iconColor(tester, override: Colors.teal), Colors.teal);
    });
  });
}
