import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _on = UserPresenceStatus.online;
const _away = UserPresenceStatus.unavailable;
const _off = UserPresenceStatus.offline;
const _unknown = UserPresenceStatus.unknown;

InviteFacts _invite(String room, String? from,
        {bool direct = true, int? minutesAgo, String? group}) =>
    InviteFacts(
        clientKey: "a",
        roomId: room,
        inviterId: from,
        isDirect: direct,
        groupName: group,
        invitedAt: minutesAgo == null
            ? null
            : DateTime(2026, 10, 22, 12)
                .subtract(Duration(minutes: minutesAgo)));

void main() {
  group("contacts", () {
    test("sort online, then away, then offline and unknown together", () {
      final people = [
        ("@zed:x", "Zed", _on),
        ("@amy:x", "amy", _off),
        ("@bob:x", "Bob", _unknown),
        ("@cat:x", "Cat", _away),
        ("@ann:x", "Ann", _on),
      ]..sort((a, b) =>
          PeopleModel.compareContacts(a.$3, a.$2, a.$1, b.$3, b.$2, b.$1));
      expect(people.map((p) => p.$2), ["Ann", "Zed", "Cat", "amy", "Bob"]);
    });

    test("equal names keep a stable order by Matrix ID", () {
      expect(
          PeopleModel.compareContacts(_on, "Sam", "@b:x", _on, "sam", "@a:x"),
          greaterThan(0));
    });

    test("a dot only for online and away; unknown never looks offline", () {
      expect(PeopleModel.showsPresenceDot(_on), isTrue);
      expect(PeopleModel.showsPresenceDot(_away), isTrue);
      expect(PeopleModel.showsPresenceDot(_off), isFalse);
      expect(PeopleModel.showsPresenceDot(_unknown), isFalse);
    });

    test("second line: status message, else Online/Away, else nothing", () {
      expect(PeopleModel.contactSubtitle(_off, " brb, dinner "), "brb, dinner");
      expect(PeopleModel.contactSubtitle(_on, null), "Online");
      expect(PeopleModel.contactSubtitle(_away, ""), "Away");
      expect(PeopleModel.contactSubtitle(_off, null), isNull);
      expect(PeopleModel.contactSubtitle(_unknown, "  "), isNull);
    });

    test("search matches name or Matrix ID, any case", () {
      expect(PeopleModel.matchesPerson("jun", "Juniper", "@j:x"), isTrue);
      expect(PeopleModel.matchesPerson("moss:", "Mossy", "@moss:x"), isTrue);
      expect(PeopleModel.matchesPerson("zz", "Mossy", "@moss:x"), isFalse);
      expect(PeopleModel.matchesPerson("", "Mossy", "@moss:x"), isTrue);
    });
  });

  group("received invites", () {
    test("only direct-message invites, newest first, unknown times last", () {
      final received = PeopleModel.receivedInvites([
        _invite("!old", "@a:x", minutesAgo: 600),
        _invite("!room", "@b:x", direct: false, minutesAgo: 1),
        _invite("!new", "@c:x", minutesAgo: 5),
        _invite("!when", "@d:x"),
      ], {}, "@me:x");
      expect(received.map((r) => r.facts.roomId), ["!new", "!old", "!when"]);
    });

    test("invites from non-contacts are tagged; contacts aren't", () {
      final received = PeopleModel.receivedInvites([
        _invite("!1", "@friend:x", minutesAgo: 1),
        _invite("!2", "@stranger:x", minutesAgo: 2),
        _invite("!3", null, minutesAgo: 3),
      ], {
        "@friend:x"
      }, "@me:x");
      expect(received.map((r) => r.notAContact), [false, true, true]);
    });

    test("an invite you sent yourself (another device) isn't received", () {
      expect(PeopleModel.receivedInvites([_invite("!1", "@me:x")], {}, "@me:x"),
          isEmpty);
    });

    test("the badge counts received invites only", () {
      final received = PeopleModel.receivedInvites([
        _invite("!1", "@a:x"),
        _invite("!2", "@b:x"),
        _invite("!3", "@c:x", direct: false),
      ], {}, "@me:x");
      expect(PeopleModel.badgeCount(received), 2);
      expect(PeopleModel.badgeCount(const []), 0);
    });

    test("lines say what and when", () {
      final now = DateTime(2026, 10, 22, 12);
      final dm = PeopleModel.receivedInvites(
              [_invite("!1", "@a:x", minutesAgo: 120)], {}, "@me:x")
          .single;
      expect(PeopleModel.receivedLine(dm, now),
          "Invited you to a direct message · 2h ago");
      final group = PeopleModel.receivedInvites(
              [_invite("!2", "@a:x", group: "Plant swap")], {}, "@me:x")
          .single;
      expect(PeopleModel.receivedLine(group, now),
          "Invited you to a group DM “Plant swap”");
    });
  });

  group("sent invites", () {
    final at = DateTime(2026, 10, 21);
    test("people you invited who haven't joined, in DMs you're in", () {
      final sent = PeopleModel.sentInvites([
        DmMembershipFacts(roomId: "!dm", selfJoined: true, members: [
          const MemberFacts("@me:x", "join"),
          MemberFacts("@a:x", "invite", invitedBy: "@me:x", at: at),
        ]),
        // They joined: nothing pending.
        const DmMembershipFacts(roomId: "!done", selfJoined: true, members: [
          MemberFacts("@me:x", "join"),
          MemberFacts("@b:x", "join", invitedBy: "@b:x"),
        ]),
        // Someone else invited them.
        const DmMembershipFacts(roomId: "!other", selfJoined: true, members: [
          MemberFacts("@me:x", "join"),
          MemberFacts("@c:x", "invite", invitedBy: "@d:x"),
          MemberFacts("@d:x", "join"),
        ]),
        // You left.
        const DmMembershipFacts(roomId: "!left", selfJoined: false, members: [
          MemberFacts("@e:x", "invite", invitedBy: "@me:x"),
        ]),
      ], "@me:x");
      expect(sent.map((s) => "${s.roomId} ${s.userId}"), ["!dm @a:x"]);
      expect(sent.single.leaveOnCancel, isTrue);
      expect(sent.single.invitedAt, at);
    });

    test("cancel keeps the room when someone else is in it", () {
      final sent = PeopleModel.sentInvites([
        const DmMembershipFacts(
            roomId: "!group",
            selfJoined: true,
            groupName: "Plant swap",
            members: [
              MemberFacts("@me:x", "join"),
              MemberFacts("@a:x", "invite", invitedBy: "@me:x"),
              MemberFacts("@b:x", "join"),
            ]),
      ], "@me:x");
      expect(sent.single.leaveOnCancel, isFalse);
      expect(PeopleModel.sentLine(sent.single, DateTime(2026)),
          "You invited them to a group DM “Plant swap”");
    });
  });

  group("relative time", () {
    final now = DateTime(2026, 10, 22, 12);
    test("reads naturally", () {
      String ago(Duration d) => PeopleModel.relativeTime(now.subtract(d), now);
      expect(ago(const Duration(seconds: 20)), "just now");
      expect(ago(const Duration(minutes: 5)), "5 min ago");
      expect(ago(const Duration(hours: 3)), "3h ago");
      expect(ago(const Duration(hours: 30)), "yesterday");
      expect(ago(const Duration(days: 4)), "4 days ago");
      expect(ago(const Duration(days: 10)), "last week");
      expect(ago(const Duration(days: 21)), "3 weeks ago");
      expect(PeopleModel.relativeTime(DateTime(2026, 3, 4), now), "Mar 4");
      expect(
          PeopleModel.relativeTime(DateTime(2025, 3, 4), now), "Mar 4, 2025");
    });
  });

  group("Active Now", () {
    test("empty when nobody is online or in a call (the panel hides)", () {
      expect(
          PeopleModel.activeNow(const [], const [
            ContactFacts("@a:x", "A", _off),
            ContactFacts("@b:x", "B", _unknown),
          ]),
          isEmpty);
    });

    test("calls first (biggest first), then online and away contacts", () {
      final entries = PeopleModel.activeNow(const [
        CallFacts(
            roomKey: "small",
            roomName: "Study",
            participants: ["@a:x"],
            contactsIn: ["@a:x"]),
        CallFacts(
            roomKey: "big",
            roomName: "Game Night",
            participants: ["@b:x", "@z:x", "@y:x"],
            contactsIn: ["@b:x"]),
        CallFacts(
            roomKey: "strangers",
            roomName: "Lobby",
            participants: ["@q:x"],
            contactsIn: []),
      ], const [
        ContactFacts("@a:x", "A", _on),
        ContactFacts("@b:x", "B", _on),
        ContactFacts("@c:x", "C", _away, statusMessage: "reading"),
        ContactFacts("@d:x", "D", _on),
        ContactFacts("@e:x", "E", _off, statusMessage: "hidden"),
      ]);
      expect(entries.map((e) => e.userIds.join()),
          ["@b:x", "@a:x", "@d:x", "@c:x"]);
      final big = entries[0].activity as VoiceActivity;
      expect(big.roomName, "Game Night");
      expect(big.others, 2);
      expect((entries[2].activity as PresenceActivity).status, _on);
      expect((entries[3].activity as StatusActivity).message, "reading");
    });

    test("mostRecentFirst: latest call join or activity first, unknown last",
        () {
      final t = DateTime(2026, 10, 24, 12);
      final entries = PeopleModel.mostRecentFirst(
          PeopleModel.activeNow([
            CallFacts(
                roomKey: "big",
                roomName: "Game Night",
                participants: const ["@b:x", "@z:x"],
                contactsIn: const ["@b:x"],
                lastJoined: t.subtract(const Duration(minutes: 30))),
            CallFacts(
                roomKey: "small",
                roomName: "Study",
                participants: const ["@a:x"],
                contactsIn: const ["@a:x"],
                lastJoined: t.subtract(const Duration(minutes: 2))),
          ], [
            const ContactFacts("@c:x", "C", _on),
            const ContactFacts("@d:x", "D", _on),
            const ContactFacts("@e:x", "E", _away),
            const ContactFacts("@f:x", "F", _away),
          ]),
          (key) => {
                "@c:x": t.subtract(const Duration(minutes: 10)),
                "@f:x": t
              }[key]);
      expect(entries.map((e) => e.userIds.join()),
          ["@f:x", "@a:x", "@c:x", "@b:x", "@d:x", "@e:x"]);
    });

    test("titles", () {
      expect(PeopleModel.activeNowTitle(["Juni"], 0), "Juni");
      expect(
          PeopleModel.activeNowTitle(["Juni", "Mossy"], 0), "Juni and Mossy");
      expect(PeopleModel.activeNowTitle(["Juni"], 1), "Juni and 1 other");
      expect(PeopleModel.activeNowTitle(["Juni", "Mossy"], 1),
          "Juni and 2 others");
      expect(PeopleModel.activeNowTitle([], 3), "");
    });
  });
}
