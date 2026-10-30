// Vommet issue 853: which users are bridged ghosts.
import 'package:commet/utils/bridged_user_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("built-in patterns", () {
    test("strict: prefix plus an ID", () {
      expect(classifyBridgedUser("@telegram_123456:nether.im")?.network,
          BridgeNetwork.telegram);
      expect(classifyBridgedUser("@telegram_fan:nether.im"), isNull);
      expect(classifyBridgedUser("@discord_81234567890:nether.im")?.network,
          BridgeNetwork.discord);
      expect(classifyBridgedUser("@_discord_81234567890:t2bot.io")?.network,
          BridgeNetwork.discord);
      expect(classifyBridgedUser("@whatsapp_15551234567:x.org")?.network,
          BridgeNetwork.whatsapp);
      expect(
          classifyBridgedUser(
                  "@signal_0f8a7c4e-1b2d-4e3f-9a8b-7c6d5e4f3a2b:x.org")
              ?.network,
          BridgeNetwork.signal);
      expect(classifyBridgedUser("@signal_fan:x.org"), isNull);
      expect(classifyBridgedUser("@alice:nether.im"), isNull);
    });

    test("guesses are marked as guesses", () {
      final user = classifyBridgedUser("@telegram_1:nether.im")!;
      expect(user.source, BridgeSource.guessed);
      expect(user.isGuess, isTrue);
      expect(user.dms, BridgeDmReach.mayNot);
    });

    test("voice bridge puppets: nobody reads their messages", () {
      final user =
          classifyBridgedUser("@nether-voicebridge_1234567890:nether.im")!;
      expect(user.network, BridgeNetwork.voiceBridge);
      expect(user.dms, BridgeDmReach.nobody);
    });

    test("a network whose icon is off is plain for name safety", () {
      final user = classifyBridgedUser("@telegram_1:t2bot.io",
          trust: const BridgeTrust())!;
      expect(markGroup(user, marksOn: true), "telegram");
      expect(markGroup(user, marksOn: true, hidden: {BridgeNetwork.telegram}),
          plainMarkGroup);
    });

    test("not a user ID", () {
      expect(classifyBridgedUser("telegram_1"), isNull);
      expect(classifyBridgedUser("@telegram_1"), isNull);
    });
  });

  group("user patterns", () {
    test("glob on the whole user ID", () {
      const p = UserBridgePattern("@irc_*:example.org", BridgeNetwork.irc);
      expect(p.matches("@irc_bob:example.org"), isTrue);
      expect(p.matches("@IRC_bob:example.org"), isTrue);
      expect(p.matches("@irc_bob:example.org.evil"), isFalse);
      expect(p.matches("@xirc_bob:example.org"), isFalse);
    });

    test("encode and decode", () {
      const p = UserBridgePattern("@slack_*:x.org", BridgeNetwork.other,
          dmsReach: true);
      final back = UserBridgePattern.decode(p.encode())!;
      expect(back.pattern, p.pattern);
      expect(back.network, BridgeNetwork.other);
      expect(back.dmsReach, isTrue);
      expect(UserBridgePattern.decode("garbage"), isNull);
    });

    test("beat the built-ins; 'DMs reach them' hides the warning", () {
      final user = classifyBridgedUser("@telegram_1:nether.im", patterns: [
        const UserBridgePattern("@telegram_*:nether.im", BridgeNetwork.telegram,
            dmsReach: true)
      ])!;
      expect(user.source, BridgeSource.yours);
      expect(user.dms, BridgeDmReach.reaches);
    });
  });

  group("declared on the profile", () {
    test("read from com.beeper.bridge fields", () {
      final declared = DeclaredBridge.fromProfile({
        "displayname": "Bob",
        "com.beeper.bridge.service": "telegram",
        "com.beeper.bridge.network": "telegram",
      })!;
      final user = classifyBridgedUser("@bob:nether.im", declared: declared)!;
      expect(user.network, BridgeNetwork.telegram);
      expect(user.source, BridgeSource.declared);
      expect(user.isGuess, isFalse);
    });

    test("no fields, no declaration", () {
      expect(DeclaredBridge.fromProfile({"displayname": "Bob"}), isNull);
    });

    test("an unknown network keeps its name", () {
      final user = classifyBridgedUser("@x:y.org",
          declared:
              const DeclaredBridge(service: "slackgo", network: "slack"))!;
      expect(user.network, BridgeNetwork.other);
      expect(user.networkName, "slack");
    });

    test("beats the ID guess", () {
      final user = classifyBridgedUser("@telegram_1:nether.im",
          declared: const DeclaredBridge(network: "whatsapp"))!;
      expect(user.network, BridgeNetwork.whatsapp);
    });
  });

  group("the user's choice for one person", () {
    test("not bridged wins over everything", () {
      expect(
          classifyBridgedUser("@telegram_1:nether.im",
              override: notBridgedOverride,
              declared: const DeclaredBridge(network: "telegram")),
          isNull);
    });

    test("a picked network", () {
      final user =
          classifyBridgedUser("@alice:nether.im", override: "voiceBridge")!;
      expect(user.network, BridgeNetwork.voiceBridge);
      expect(user.source, BridgeSource.yours);
      expect(user.dms, BridgeDmReach.nobody);
    });
  });

  test("networkFromName is lenient", () {
    expect(networkFromName("mautrix-telegram"), BridgeNetwork.telegram);
    expect(networkFromName("Discord"), BridgeNetwork.discord);
    expect(networkFromName("nether-voicebridge"), BridgeNetwork.voiceBridge);
    expect(networkFromName("discord-voice"), BridgeNetwork.voiceBridge);
    expect(networkFromName("matrix"), isNull);
  });
}
