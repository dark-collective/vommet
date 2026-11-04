import 'dart:convert';

import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _custom(SoundEvent e, String file, String name) async {
  final all = jsonDecode(preferences.soundChoices.value) as Map;
  all[e.name] = SoundChoice(SoundMode.custom, file: file, name: name).toJson();
  await preferences.soundChoices.set(jsonEncode(all));
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("every event sounds as before until changed", () {
    expect(AppSounds.describe(SoundEvent.message), "Default");
    expect(AppSounds.describe(SoundEvent.mention), "Same as new message");
    expect(AppSounds.describe(SoundEvent.peerJoin), "Same as you join");
    expect(AppSounds.describe(SoundEvent.deafen), "Same as mute");
    expect(AppSounds.describe(SoundEvent.callNotAnswered), "Same as you leave");
    expect(AppSounds.describe(SoundEvent.connectionLost), "Same as you leave");
    expect(AppSounds.source(SoundEvent.connectionLost),
        AppSounds.source(SoundEvent.selfLeave));
    expect(AppSounds.describe(SoundEvent.screenShareStart),
        "Same as someone joins");
    expect(AppSounds.source(SoundEvent.screenShareStart),
        AppSounds.source(SoundEvent.selfJoin));
    expect(AppSounds.source(SoundEvent.screenShareStop),
        AppSounds.source(SoundEvent.selfLeave));
    expect(AppSounds.source(SoundEvent.peerJoin),
        AppSounds.source(SoundEvent.selfJoin));
  });

  test("shared sounds follow the sound they share", () async {
    await AppSounds.setNone(SoundEvent.mute);
    expect(AppSounds.source(SoundEvent.deafen), isNull);
    await AppSounds.setDefault(SoundEvent.mute);
    expect(AppSounds.source(SoundEvent.deafen), isNotNull);
  });

  test("a sound can be set to a file and back to none", () async {
    await _custom(
        SoundEvent.connectionLost, "/nowhere/skitter.ogg", "skitter.ogg");
    expect(AppSounds.describe(SoundEvent.connectionLost), "skitter.ogg");
    // The file is gone, so it falls back to the default.
    expect(AppSounds.source(SoundEvent.connectionLost),
        AppSounds.source(SoundEvent.selfLeave));
    await AppSounds.setNone(SoundEvent.connectionLost);
    expect(AppSounds.choice(SoundEvent.connectionLost).mode, SoundMode.none);
    expect(AppSounds.source(SoundEvent.connectionLost), isNull);
  });

  test("screen share sounds follow the join and leave sounds", () async {
    await AppSounds.setNone(SoundEvent.peerJoin);
    expect(AppSounds.source(SoundEvent.screenShareStart), isNull);
    await AppSounds.setNone(SoundEvent.screenShareStop);
    expect(AppSounds.source(SoundEvent.screenShareStop), isNull);
    expect(AppSounds.source(SoundEvent.peerLeave), isNotNull);
  });

  test("Android channels: defaults keep upstream ids, each sound its own",
      () async {
    expect(AppSounds.androidChannelId(SoundEvent.message), "messages");
    expect(AppSounds.androidChannelId(SoundEvent.ringIncoming),
        "incoming_calls_channel_1");
    expect(AppSounds.androidChannelId(SoundEvent.mention), "messages");
    expect(
        AppSounds.androidChannel(SoundEvent.mention).name, "Message Received");

    await _custom(SoundEvent.message, "content://a", "a.ogg");
    final a = AppSounds.androidChannelId(SoundEvent.message);
    expect(a, startsWith("messages_"));
    // An unchanged mention sound shares the message channel.
    expect(AppSounds.androidChannelId(SoundEvent.mention), a);

    await _custom(SoundEvent.message, "content://b", "b.ogg");
    expect(AppSounds.androidChannelId(SoundEvent.message), isNot(a));

    await AppSounds.setNone(SoundEvent.mention);
    expect(AppSounds.androidChannelId(SoundEvent.mention),
        startsWith("mentions_"));
    expect(AppSounds.androidSound(SoundEvent.mention), isNull);
    expect(AppSounds.androidChannel(SoundEvent.mention).playSound, isFalse);
  });

  test("unreadable settings fall back to the defaults", () async {
    await preferences.soundChoices.set("not json");
    expect(AppSounds.describe(SoundEvent.message), "Default");
    await preferences.soundChoices.set(jsonEncode({
      "message": {"mode": "custom"}
    }));
    expect(AppSounds.choice(SoundEvent.message).mode, SoundMode.standard);
  });

  test("a push with the highlight tweak plays the mention sound", () {
    NotificationContent content(String id) => MessageNotificationContent(
        senderName: "Juniper",
        senderId: "@juniper:example.org",
        roomName: "Lantern Lounge",
        content: "hi",
        eventId: id,
        roomId: "!room:example.org",
        clientId: "client",
        isDirectMessage: false);

    MessageNotificationContent.notePush({
      "event_id": r"$mention",
      "devices": [
        {
          "tweaks": {"highlight": true}
        }
      ]
    });
    MessageNotificationContent.notePush({
      "event_id": r"$plain",
      "devices": [
        {"tweaks": {}}
      ]
    });
    expect(
        (content(r"$mention") as MessageNotificationContent).playsMentionSound,
        isTrue);
    expect((content(r"$plain") as MessageNotificationContent).playsMentionSound,
        isFalse);
  });

  group("the push rule decides the sound (Vommet issue 719)", () {
    MessageNotificationContent content(String id) => MessageNotificationContent(
        senderName: "Juniper",
        senderId: "@juniper:example.org",
        roomName: "Lantern Lounge",
        content: "hi",
        eventId: id,
        roomId: "!room:example.org",
        clientId: "client",
        isDirectMessage: false);

    test("a push with the sound tweak plays it", () {
      MessageNotificationContent.notePush({
        "event_id": r"$noisy",
        "devices": [
          {
            "tweaks": {"sound": "default"}
          }
        ]
      });
      expect(content(r"$noisy").playsSound, isTrue);
    });

    test("a push with other tweaks but no sound is silent", () {
      MessageNotificationContent.notePush({
        "event_id": r"$on",
        "devices": [
          {
            "tweaks": {"highlight": false}
          }
        ]
      });
      MessageNotificationContent.notePush({
        "event_id": r"$room",
        "devices": [
          {
            "tweaks": {"highlight": true}
          }
        ]
      });
      expect(content(r"$on").playsSound, isFalse);
      expect(content(r"$room").playsSound, isFalse);
    });

    test("a push without tweaks (Synapse event_id_only) plays the sound", () {
      MessageNotificationContent.notePush({
        "event_id": r"$synapse",
        "devices": [
          {"app_id": "im.nether.vommet", "tweaks": {}}
        ]
      });
      MessageNotificationContent.notePush({
        "event_id": r"$missing",
        "devices": [
          {"app_id": "im.nether.vommet"}
        ]
      });
      expect(content(r"$synapse").playsSound, isTrue);
      expect(content(r"$missing").playsSound, isTrue);
    });

    test("an unknown event plays the sound as before", () {
      expect(content(r"$unknown").playsSound, isTrue);
      MessageNotificationContent.notePush({"event_id": r"$bare"});
      expect(content(r"$bare").playsSound, isTrue);
    });

    test("a rule checked on the device wins", () {
      final quiet = content(r"$noisy")..ruleSound = false;
      expect(quiet.playsSound, isFalse);
      final loud = content(r"$on")..ruleSound = true;
      expect(loud.playsSound, isTrue);
    });
  });
}
