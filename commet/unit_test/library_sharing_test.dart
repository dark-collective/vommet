// Vommet issue 731, phase 2: sharing a collection.
import 'package:commet/utils/library_sharing.dart';
import 'package:flutter_test/flutter_test.dart';

const marker = "im.nether.vommet.sticker_room";

void main() {
  group("mode", () {
    test("stored mode wins", () {
      expect(
          LibrarySharing.modeOf(
              modeContent: {"mode": "community"}, joinRule: "invite"),
          CollectionMode.community);
    });

    test("derived: public is followers, with contributors community", () {
      expect(
          LibrarySharing.modeOf(joinRule: "public"), CollectionMode.followers);
      expect(
          LibrarySharing.modeOf(joinRule: "public", powerLevels: {
            "users": {"@a:x": 100, "@b:x": 50}
          }),
          CollectionMode.community);
    });

    test("derived: anything else is private", () {
      expect(LibrarySharing.modeOf(joinRule: "invite"), CollectionMode.private);
      expect(LibrarySharing.modeOf(joinRule: "knock"), CollectionMode.private);
      expect(LibrarySharing.modeOf(modeContent: {"mode": "odd"}),
          CollectionMode.private);
    });

    test("join rules", () {
      expect(LibrarySharing.joinRuleFor(CollectionMode.private), "invite");
      expect(LibrarySharing.joinRuleFor(CollectionMode.followers), "public");
      expect(LibrarySharing.joinRuleFor(CollectionMode.community), "public");
      expect(
          LibrarySharing.joinRuleFor(CollectionMode.community,
              anyoneCanFollow: false),
          "invite");
    });
  });

  group("power levels", () {
    final current = {
      "ban": 50,
      "events_default": 0,
      "redact": 50,
      "users_default": 10,
      "events": {"m.room.name": 0, "org.example.custom": 30},
      "users": {"@me:x": 100, "@old:x": 50, "@mod:x": 75},
    };

    test("forces the pack-room map and keeps the rest", () {
      final pl = LibrarySharing.powerLevelsFor(
          current: current, markerType: marker, mode: CollectionMode.private);
      final events = pl["events"] as Map;
      expect(pl["ban"], 50);
      expect(pl["events_default"], 100);
      expect(pl["redact"], 100);
      expect(pl["users_default"], 0);
      expect(events["m.room.image_pack"], 50);
      expect(events["im.ponies.room_emotes"], 50);
      expect(events["m.room.name"], 50);
      expect(events["org.example.custom"], 30);
      expect(events[LibrarySharing.modeType], 100);
      expect(events[marker], 100);
    });

    test("private and followers drop contributors, keep admins", () {
      for (final mode in [CollectionMode.private, CollectionMode.followers]) {
        final pl = LibrarySharing.powerLevelsFor(
            current: current,
            markerType: marker,
            mode: mode,
            contributors: ["@new:x"]);
        expect(pl["users"], {"@me:x": 100, "@mod:x": 75});
      }
    });

    test("community sets exactly the contributors to 50", () {
      final pl = LibrarySharing.powerLevelsFor(
          current: current,
          markerType: marker,
          mode: CollectionMode.community,
          contributors: ["@new:x", "@me:x", "@mod:x"]);
      // @old:x was not picked again; admins and higher levels stay.
      expect(pl["users"], {"@me:x": 100, "@mod:x": 75, "@new:x": 50});
    });

    test("version 12: creators stay out of users", () {
      final pl = LibrarySharing.powerLevelsFor(
          current: {
            "users": {"@me:x": 100, "@b:x": 50}
          },
          markerType: marker,
          mode: CollectionMode.community,
          contributors: ["@b:x", "@me:x"],
          creators: {"@me:x"},
          creatorsRankHighest: true);
      expect(pl["users"], {"@b:x": 50});
    });

    test("older versions keep the creator in users", () {
      final pl = LibrarySharing.powerLevelsFor(
          current: {
            "users": {"@me:x": 100}
          },
          markerType: marker,
          mode: CollectionMode.followers,
          creators: {"@me:x"});
      expect(pl["users"], {"@me:x": 100});
    });

    test("does not change its input", () {
      final input = {
        "users": {"@b:x": 50}
      };
      LibrarySharing.powerLevelsFor(
          current: input, markerType: marker, mode: CollectionMode.private);
      expect(input["users"], {"@b:x": 50});
    });

    test("creators rank highest from version 12", () {
      expect(LibrarySharing.creatorsRankHighest("12"), isTrue);
      expect(LibrarySharing.creatorsRankHighest("13"), isTrue);
      expect(LibrarySharing.creatorsRankHighest("11"), isFalse);
      expect(LibrarySharing.creatorsRankHighest(null), isFalse);
      expect(LibrarySharing.creatorsRankHighest("org.example.v"), isFalse);
    });
  });

  group("admins", () {
    test("contributors and admins", () {
      final pl = {
        "users": {"@a:x": 100, "@b:x": 50, "@c:x": 0, "@d:x": "50"}
      };
      expect(LibrarySharing.contributorsOf(pl), {"@b:x"});
      expect(LibrarySharing.adminsOf(pl), {"@a:x"});
      expect(
          LibrarySharing.adminsOf(pl,
              creators: {"@z:x"}, creatorsRankHighest: true),
          {"@a:x", "@z:x"});
      expect(LibrarySharing.adminsOf(null, creators: {"@z:x"}), {"@z:x"});
    });

    test("only admin with other members", () {
      expect(LibrarySharing.isOnlyAdmin("@me:x", {"@me:x"}, 2), isTrue);
      expect(LibrarySharing.isOnlyAdmin("@me:x", {"@me:x"}, 1), isFalse);
      expect(
          LibrarySharing.isOnlyAdmin("@me:x", {"@me:x", "@b:x"}, 2), isFalse);
      expect(LibrarySharing.isOnlyAdmin("@me:x", {"@b:x"}, 2), isFalse);
    });
  });

  group("links", () {
    test("matrix.to link", () {
      expect(LibrarySharing.matrixToLink("!r:x", via: ["x", "y.org"]),
          "https://matrix.to/#/!r:x?via=x&via=y.org");
      expect(LibrarySharing.matrixToLink("#packs:x", via: ["x"]),
          "https://matrix.to/#/#packs:x");
      expect(LibrarySharing.matrixToLink("!r:x"), "https://matrix.to/#/!r:x");
    });

    test("parses matrix.to links", () {
      final a = LibrarySharing.parseLink(
          " https://matrix.to/#/!r:x?via=x&via=y.org ");
      expect(a?.idOrAlias, "!r:x");
      expect(a?.via, ["x", "y.org"]);

      final b = LibrarySharing.parseLink("https://matrix.to/#/%23packs%3Ax");
      expect(b?.idOrAlias, "#packs:x");
      expect(b?.isAlias, isTrue);
      expect(b?.via, isEmpty);

      final c =
          LibrarySharing.parseLink("https://matrix.to/#/!r:x/\$event?via=z");
      expect(c?.idOrAlias, "!r:x");
      expect(c?.via, ["z"]);
    });

    test("parses aliases, room ids and matrix: URIs", () {
      expect(LibrarySharing.parseLink("#packs:x")?.idOrAlias, "#packs:x");
      final id = LibrarySharing.parseLink("!r:x");
      expect(id?.idOrAlias, "!r:x");
      expect(id?.via, ["x"]);
      final v12 = LibrarySharing.parseLink("!abcdef?via=s.org");
      expect(v12?.idOrAlias, "!abcdef");
      expect(v12?.via, ["s.org"]);
      expect(
          LibrarySharing.parseLink("matrix:r/packs:x")?.idOrAlias, "#packs:x");
      final uri = LibrarySharing.parseLink("matrix:roomid/r:x?via=y");
      expect(uri?.idOrAlias, "!r:x");
      expect(uri?.via, ["y"]);
    });

    test("rejects anything else", () {
      for (final bad in [
        "",
        "packs",
        "#packs",
        "#:x",
        "@user:x",
        "https://example.org/#/!r:x",
        "matrix:u/user:x",
        "! r:x",
      ]) {
        expect(LibrarySharing.parseLink(bad), isNull, reason: bad);
      }
    });
  });

  group("seen", () {
    final seen = {
      "!r:x": {"p": "\$1"},
    };

    test("changed when the event differs", () {
      expect(
          LibrarySharing.isChanged(seen, "!r:x", "p",
              eventId: "\$2", sender: "@b:x", me: "@me:x"),
          isTrue);
      expect(
          LibrarySharing.isChanged(seen, "!r:x", "p",
              eventId: "\$1", sender: "@b:x", me: "@me:x"),
          isFalse);
      // A new pack in a room you looked at.
      expect(
          LibrarySharing.isChanged(seen, "!r:x", "q",
              eventId: "\$3", sender: "@b:x", me: "@me:x"),
          isTrue);
    });

    test("your own edits and unseen rooms are not changes", () {
      expect(
          LibrarySharing.isChanged(seen, "!r:x", "p",
              eventId: "\$2", sender: "@me:x", me: "@me:x"),
          isFalse);
      expect(
          LibrarySharing.isChanged(seen, "!other:x", "p",
              eventId: "\$2", sender: "@b:x", me: "@me:x"),
          isFalse);
      expect(
          LibrarySharing.isChanged(seen, "!r:x", "p",
              eventId: null, sender: "@b:x", me: "@me:x"),
          isFalse);
    });

    test("mark seen writes only on change", () {
      expect(LibrarySharing.markSeen(seen, "!r:x", {"p": "\$1"}), isNull);
      expect(LibrarySharing.markSeen(seen, "!r:x", {"p": "\$2"}), {
        "!r:x": {"p": "\$2"}
      });
      expect(LibrarySharing.markSeen(seen, "!n:x", {}), {
        "!r:x": {"p": "\$1"},
        "!n:x": {},
      });
      // The input is left alone.
      expect(seen["!r:x"], {"p": "\$1"});
    });

    test("forget rooms", () {
      expect(LibrarySharing.forgetRooms(seen, {"!r:x"}), isNull);
      expect(LibrarySharing.forgetRooms(seen, {}), <String, dynamic>{});
    });
  });
}
