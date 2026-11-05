// Vommet: invite preview + invite blocking (pure logic).
import 'package:commet/client/matrix/components/invitation/invite_details.dart';
import 'package:commet/client/matrix/components/invitation/invite_permission_config.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> ev(String type, Map<String, dynamic> content,
        {String stateKey = "", String sender = "@juniper:hollow.example"}) =>
    {"type": type, "state_key": stateKey, "sender": sender, "content": content};

void main() {
  const me = "@me:nether.im";

  group("InviteDetails.fromStrippedState", () {
    test("space invite with everything Tuwunel sends", () {
      final d = InviteDetails.fromStrippedState("!s:hollow.example", me, [
        ev("m.room.create", {"type": "m.space", "room_version": "11"}),
        ev("m.room.join_rules", {"join_rule": "invite"}),
        ev("m.room.canonical_alias",
            {"alias": "#lantern-hollow:hollow.example"}),
        ev("m.room.name", {"name": "Lantern Hollow"}),
        ev("m.room.avatar", {"url": "mxc://hollow.example/abc"}),
        ev("m.room.topic", {"topic": "A cosy corner"}),
        ev("m.room.encryption", {"algorithm": "m.megolm.v1.aes-sha2"}),
        ev(
            "m.room.member",
            {
              "membership": "join",
              "displayname": "Juniper Vale",
              "avatar_url": "mxc://hollow.example/j"
            },
            stateKey: "@juniper:hollow.example"),
        ev("m.room.member",
            {"membership": "invite", "reason": "Game night is Friday"},
            stateKey: me),
      ]);
      expect(d.name, "Lantern Hollow");
      expect(d.canonicalAlias, "#lantern-hollow:hollow.example");
      expect(d.topic, "A cosy corner");
      expect(d.avatarUrl, "mxc://hollow.example/abc");
      expect(d.isSpace, isTrue);
      expect(d.joinRule, "invite");
      expect(d.encrypted, isTrue);
      expect(d.inviterId, "@juniper:hollow.example");
      expect(d.inviterDisplayName, "Juniper Vale");
      expect(d.inviterAvatarUrl, "mxc://hollow.example/j");
      expect(d.inviterServer, "hollow.example");
      expect(d.reason, "Game night is Friday");
      expect(d.isDirect, isFalse);
    });

    test("DM invite, unencrypted, port in the inviter's server", () {
      final d = InviteDetails.fromStrippedState("!d:fedi.example", me, [
        ev("m.room.member", {"membership": "invite", "is_direct": true},
            stateKey: me, sender: "@rowan:Fedi.Example:8448"),
      ]);
      expect(d.isDirect, isTrue);
      expect(d.inviterId, "@rowan:Fedi.Example:8448");
      expect(d.inviterServer, "fedi.example");
      expect(d.encrypted, isFalse);
      expect(d.name, isNull);
      expect(d.inviterDisplayName, isNull);
      expect(d.isSpace, isFalse);
    });

    test("missing own membership falls back to the known sender", () {
      final d = InviteDetails.fromStrippedState(
          "!x:a",
          me,
          [
            ev("m.room.name", {"name": "  "}),
            ev("m.room.join_rules", {"join_rule": "public"}),
          ],
          fallbackInviterId: "@prize:giveaway.example");
      expect(d.name, isNull, reason: "blank names don't count");
      expect(d.inviterId, "@prize:giveaway.example");
      expect(d.reason, isNull);
      expect(d.isPublic, isTrue);
    });

    test("malformed content is ignored, not thrown", () {
      final d = InviteDetails.fromStrippedState("!x:a", me, [
        {"type": "m.room.name", "state_key": "", "content": "nope"},
        ev("m.room.topic", {"topic": 42}),
        ev("m.room.member", {"membership": "invite", "is_direct": "yes"},
            stateKey: me),
      ]);
      expect(d.name, isNull);
      expect(d.topic, isNull);
      expect(d.isDirect, isFalse);
    });

    test("an invite we sent ourselves has no inviter", () {
      final d = InviteDetails.fromStrippedState("!x:a", me, [
        ev("m.room.member", {"membership": "invite"}, stateKey: me, sender: me),
      ]);
      expect(d.inviterId, isNull);
    });
  });

  group("InvitePermissionConfig", () {
    test("blocksAll reads every slot the server honours", () {
      expect(const InvitePermissionConfig().blocksAll, isFalse);
      expect(
          const InvitePermissionConfig(stable: {"default_action": "block"})
              .blocksAll,
          isTrue);
      expect(
          const InvitePermissionConfig(blanket: {"block_all": true}).blocksAll,
          isTrue);
      expect(
          const InvitePermissionConfig(lists: {"default_action": "block"})
              .blocksAll,
          isTrue);
      expect(
          const InvitePermissionConfig(stable: {"default_action": "allow"})
              .blocksAll,
          isFalse);
    });

    test("Nobody writes the stable slot and keeps its other keys", () {
      const c = InvitePermissionConfig(stable: {"x.other": 1});
      expect(c.setBlocksAll(true), {
        InvitePermissionConfig.stableType: {
          "x.other": 1,
          "default_action": "block"
        }
      });
      // Already blocking: nothing to write.
      expect(
          const InvitePermissionConfig(blanket: {"block_all": true})
              .setBlocksAll(true),
          isEmpty);
    });

    test("Anyone clears the block in every slot, keeps the lists", () {
      const c = InvitePermissionConfig(
        stable: {"default_action": "block", "x.other": 1},
        blanket: {"block_all": true},
        lists: {
          "default_action": "block",
          "blocked_servers": ["spam.example"]
        },
      );
      final w = c.setBlocksAll(false);
      expect(w[InvitePermissionConfig.stableType], {"x.other": 1});
      expect(w[InvitePermissionConfig.blanketType], {"block_all": false});
      expect(w[InvitePermissionConfig.listsType], {
        "blocked_servers": ["spam.example"]
      });
      final after = InvitePermissionConfig(
          stable: w[InvitePermissionConfig.stableType],
          blanket: w[InvitePermissionConfig.blanketType],
          lists: w[InvitePermissionConfig.listsType]);
      expect(after.blocksAll, isFalse);
      expect(after.blockedServers, ["spam.example"]);
    });

    test("Anyone on a fresh account writes upstream's empty stable slot", () {
      expect(const InvitePermissionConfig().setBlocksAll(false),
          {InvitePermissionConfig.stableType: <String, dynamic>{}});
    });

    test("blocking a server merges into the MSC4155 lists slot", () {
      const c = InvitePermissionConfig(
        stable: {"default_action": "block"},
        lists: {
          "blocked_users": ["@a:b"],
          "blocked_servers": ["old.example"],
          "allowed_servers": ["friends.example"],
        },
      );
      final w = c.withBlockedServer(" Giveaway.Example:8448 ");
      expect(w, {
        "blocked_users": ["@a:b"],
        "blocked_servers": ["old.example", "giveaway.example"],
        "allowed_servers": ["friends.example"],
      });
      // The stable slot is never part of it.
      expect(c.stable, {"default_action": "block"});
    });

    test("blocking twice is a no-op; a malformed list is replaced", () {
      const c = InvitePermissionConfig(lists: {
        "blocked_servers": ["spam.example"]
      });
      expect(c.withBlockedServer("SPAM.example"), isNull);
      const broken = InvitePermissionConfig(lists: {"blocked_servers": "x"});
      expect(broken.blockedServers, isEmpty);
      expect(broken.withBlockedServer("spam.example"), {
        "blocked_servers": ["spam.example"]
      });
    });

    test("blocking turns lists another app switched off back on", () {
      const c = InvitePermissionConfig(lists: {
        "enabled": false,
        "blocked_servers": ["spam.example"]
      });
      expect(c.listsDisabled, isTrue);
      expect(c.withBlockedServer("spam.example"), {
        "blocked_servers": ["spam.example"]
      });
    });

    test("unblocking removes only that server", () {
      const c = InvitePermissionConfig(lists: {
        "blocked_servers": ["a.example", "*.spamfarm.example"],
        "ignored_users": ["@x:y"],
      });
      expect(c.withoutBlockedServer("*.SPAMFARM.example"), {
        "blocked_servers": ["a.example"],
        "ignored_users": ["@x:y"],
      });
      expect(c.withoutBlockedServer("nope.example"), isNull);
    });

    test("normaliseServer accepts names, globs, IDs and links", () {
      expect(
          InvitePermissionConfig.normaliseServer("Example.ORG"), "example.org");
      expect(InvitePermissionConfig.normaliseServer("*.spam.example"),
          "*.spam.example");
      expect(InvitePermissionConfig.normaliseServer("@bob:evil.example"),
          "evil.example");
      expect(InvitePermissionConfig.normaliseServer("https://x.example/path"),
          "x.example");
      expect(InvitePermissionConfig.normaliseServer("x.example:8448"),
          "x.example");
      expect(InvitePermissionConfig.normaliseServer(""), isNull);
      expect(InvitePermissionConfig.normaliseServer("two words"), isNull);
      expect(InvitePermissionConfig.normaliseServer("bad_name!"), isNull);
      expect(() => const InvitePermissionConfig().withBlockedServer("a b"),
          throwsArgumentError);
    });

    test("serverOf strips the port", () {
      expect(InvitePermissionConfig.serverOf("@a:Nether.im"), "nether.im");
      expect(InvitePermissionConfig.serverOf("@a:h.example:8448"), "h.example");
      expect(InvitePermissionConfig.serverOf("@a:[::1]:8448"), "[::1]");
      expect(InvitePermissionConfig.serverOf("nocolon"), isNull);
      expect(InvitePermissionConfig.serverOf(null), isNull);
    });

    test("matches globs like the server does", () {
      expect(InvitePermissionConfig.matches("*.spam.example", "a.spam.example"),
          isTrue);
      expect(InvitePermissionConfig.matches("*.spam.example", "spam.example"),
          isFalse);
      expect(InvitePermissionConfig.matches("*", "nether.im"), isTrue);
      expect(InvitePermissionConfig.matches("nether.i?", "nether.im"), isTrue);
      expect(InvitePermissionConfig.matches("Nether.IM", "nether.im"), isTrue);
      expect(InvitePermissionConfig.matches("a.b", "axb"), isFalse);
    });
  });
}
