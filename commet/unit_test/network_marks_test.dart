// Vommet network marks: when a bridge mark is verified, and how name safety
// uses the marks.
import 'package:commet/client/matrix/nicknames/name_safety.dart';
import 'package:commet/utils/bridged_user_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BridgedUser? classify(String id,
          {BridgeTrust trust = const BridgeTrust(),
          Iterable<SeenBridge> room = const [],
          List<UserBridgePattern> patterns = const [],
          DeclaredBridge? declared,
          String? override}) =>
      classifyBridgedUser(id,
          trust: trust,
          room: room,
          patterns: patterns,
          declared: declared,
          override: override);

  group("trust", () {
    test("t2bot.io Telegram and Discord are verified", () {
      final telegram = classify("@telegram_123:t2bot.io")!;
      expect(telegram.network, BridgeNetwork.telegram);
      expect(telegram.verified, isTrue);
      final discord = classify("@_discord_81234567890:t2bot.io")!;
      expect(discord.network, BridgeNetwork.discord);
      expect(discord.verified, isTrue);
    });

    test("matrix.org: OFTC IRC is verified, a Telegram lookalike is not", () {
      final irc = classify("@_oftc_wren:matrix.org")!;
      expect(irc.network, BridgeNetwork.irc);
      expect(irc.verified, isTrue);
      final fake = classify("@telegram_1:matrix.org")!;
      expect(fake.network, BridgeNetwork.telegram);
      expect(fake.verified, isFalse);
    });

    test("a spoof server is not verified", () {
      final user = classify("@telegram_5550124:spoof.example")!;
      expect(user.network, BridgeNetwork.telegram);
      expect(user.verified, isFalse);
      expect(user.server, "spoof.example");
    });

    test("own server: only for networks whose bridge bot was seen there", () {
      expect(classify("@telegram_1:example.org")!.verified, isFalse);
      final seen = [
        SeenBridge.from(
            protocol: "telegram", bridgeBot: "@telegrambot:example.org")!,
        SeenBridge.from(
            protocol: "whatsapp", bridgeBot: "@whatsappbot:other.example")!,
      ];
      final trust = BridgeTrust(
          ownServer: "example.org",
          ownNetworks: networksOnServer("example.org", seen));
      expect(trust.ownNetworks, {BridgeNetwork.telegram});
      expect(
          classify("@telegram_1:example.org", trust: trust)!.verified, isTrue);
      expect(classify("@whatsapp_1555:example.org", trust: trust)!.verified,
          isFalse);
    });

    test("a room's m.bridge trusts its server in that room only", () {
      final room = [
        SeenBridge.from(
            protocol: "discordgo", bridgeBot: "@discordbot:bridge.example")!
      ];
      expect(classify("@discord_8123:bridge.example", room: room)!.verified,
          isTrue);
      expect(classify("@discord_8123:bridge.example")!.verified, isFalse);
      expect(classify("@discord_8123:else.example", room: room)!.verified,
          isFalse);
    });

    test("a profile declaration alone is not proof", () {
      final user = classify("@bob:spoof.example",
          declared: const DeclaredBridge(network: "telegram"))!;
      expect(user.network, BridgeNetwork.telegram);
      expect(user.verified, isFalse);
    });

    test("user entry with a pattern", () {
      final entry = UserBridgePattern("@signal_*", BridgeNetwork.signal,
          server: "chat.friend.example");
      final user =
          classify("@signal_abc:chat.friend.example", patterns: [entry])!;
      expect(user.network, BridgeNetwork.signal);
      expect(user.verified, isTrue);
      expect(classify("@signal_abc:other.example", patterns: [entry]), isNull);
    });

    test("user entry without a pattern uses the network's usual IDs", () {
      const entry =
          UserBridgePattern("", BridgeNetwork.telegram, server: "tg.example");
      expect(classify("@telegram_42:tg.example", patterns: [entry])!.verified,
          isTrue);
      // Not an ID the Telegram bridge makes: not trusted, not bridged.
      expect(classify("@alice:tg.example", patterns: [entry]), isNull);
    });

    test("a disabled built-in is no longer trusted", () {
      final user = classify("@telegram_123:t2bot.io",
          trust: const BridgeTrust(disabledBuiltIns: {"t2bot-telegram"}))!;
      expect(user.network, BridgeNetwork.telegram);
      expect(user.verified, isFalse);
    });

    test("the user's own pick counts as verified", () {
      final user = classify("@telegram_1:spoof.example", override: "discord")!;
      expect(user.network, BridgeNetwork.discord);
      expect(user.verified, isTrue);
    });

    test("old stored patterns still decode and match", () {
      final old = UserBridgePattern.decode("@irc_*:example.org\tirc\t1")!;
      expect(old.network, BridgeNetwork.irc);
      expect(old.dmsReach, isTrue);
      expect(old.server, isNull);
      expect(old.serverName, "example.org");
      expect(old.matches("@irc_wren:example.org"), isTrue);
      expect(old.matches("@irc_wren:spoof.example"), isFalse);
      expect(old.encode(), "@irc_*:example.org\tirc\t1");
      final user = classify("@irc_wren:example.org", patterns: [old])!;
      expect(user.verified, isTrue);

      final entry = UserBridgePattern("", BridgeNetwork.signal,
          server: "chat.friend.example");
      final back = UserBridgePattern.decode(entry.encode())!;
      expect(back.server, "chat.friend.example");
      expect(back.pattern, "");
      expect(back.network, BridgeNetwork.signal);
    });

    test("protocol ids real bridges send", () {
      expect(networkFromName("telegram"), BridgeNetwork.telegram);
      expect(networkFromName("discordgo"), BridgeNetwork.discord);
      expect(networkFromName("discord"), BridgeNetwork.discord);
      expect(networkFromName("whatsapp"), BridgeNetwork.whatsapp);
      expect(networkFromName("signal"), BridgeNetwork.signal);
      expect(networkFromName("irc"), BridgeNetwork.irc);
      // The voice bridge's m.bridge protocol id, despite containing "discord".
      expect(networkFromName("discord-voice"), BridgeNetwork.voiceBridge);
    });

    test("tchncs.de bridges and Nether's voice bridge are verified", () {
      final telegram = classify("@telegram_42:tchncs.de")!;
      expect(telegram.network, BridgeNetwork.telegram);
      expect(telegram.verified, isTrue);
      final whatsapp = classify("@whatsapp_15551234567:tchncs.de")!;
      expect(whatsapp.network, BridgeNetwork.whatsapp);
      expect(whatsapp.verified, isTrue);
      final signal =
          classify("@signal_0f8fad5b-d9cb-469f-a165-70867728950e:tchncs.de")!;
      expect(signal.network, BridgeNetwork.signal);
      expect(signal.verified, isTrue);
      final voice = classify("@nether-voicebridge_81234567890:nether.im")!;
      expect(voice.network, BridgeNetwork.voiceBridge);
      expect(voice.verified, isTrue);
      expect(
          classify("@nether-voicebridge_1:spoof.example")!.verified, isFalse);
    });
  });

  group("name safety with marks", () {
    const plain = "@wren:example.org";
    const verifiedTelegram = "@telegram_1:t2bot.io";
    const spoof = "@telegram_2:spoof.example";

    Map<String, String> groups(List<String> ids,
            {bool marksOn = true, Set<BridgeNetwork> hidden = const {}}) =>
        {
          for (final id in ids)
            id: markGroup(classify(id), marksOn: marksOn, hidden: hidden)
        };

    Set<String> flag(List<String> ids, Map<String, String>? groups) =>
        NameSafety.flag(
            [for (final id in ids) NameSafetyEntry(id, "Wren")], const [],
            groups: groups);

    test("Matrix Wren vs verified Telegram Wren: no ID", () {
      final ids = [plain, verifiedTelegram];
      expect(flag(ids, groups(ids)), isEmpty);
    });

    test("Matrix Wren vs an unverified lookalike: both keep the ID", () {
      final ids = [plain, spoof];
      expect(flag(ids, groups(ids)), {plain, spoof});
    });

    test("two verified Telegram Wrens keep the ID", () {
      final ids = [verifiedTelegram, "@telegram_9:t2bot.io"];
      expect(flag(ids, groups(ids)), ids.toSet());
    });

    test("same picture across groups doesn't clash", () {
      final entries = [
        const NameSafetyEntry(plain, "Wren", "mxc://x/a"),
        const NameSafetyEntry(verifiedTelegram, "Robin", "mxc://x/a"),
      ];
      expect(
          NameSafety.flag(entries, const [],
              groups: groups([plain, verifiedTelegram])),
          isEmpty);
      expect(NameSafety.flag(entries, const []), {plain, verifiedTelegram});
    });

    test("marks off: as before", () {
      final ids = [plain, verifiedTelegram];
      expect(flag(ids, null), ids.toSet());
      expect(flag(ids, groups(ids, marksOn: false)), ids.toSet());
    });

    test("network switch off: ID kept", () {
      final ids = [plain, verifiedTelegram];
      expect(flag(ids, groups(ids, hidden: {BridgeNetwork.telegram})),
          ids.toSet());
    });

    test("role words are still flagged", () {
      expect(NameSafety.claimsRole("Admin"), isTrue);
      expect(markGroup(classify(verifiedTelegram), marksOn: true),
          isNot(plainMarkGroup));
    });
  });
}
