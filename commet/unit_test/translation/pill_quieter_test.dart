// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_translation_views.dart';
import 'package:commet/ui/molecules/settings_entry_bool.dart';
import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_fakes.dart';

class _Client implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Room implements Room {
  @override
  String get identifier => "!a";

  @override
  Client get client => _Client();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Timeline implements Timeline {
  @override
  Room get room => _Room();

  @override
  Client get client => _Client();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Someone else's text message, not yet synced (keeps the menu's other
/// entries from asking the room about permissions).
class _Message implements TimelineEventMessage {
  _Message(this.text, {this.html});

  final String text;
  final String? html;

  @override
  String get eventId => r"$m";

  @override
  String get senderId => "@b:example.org";

  @override
  TimelineEventStatus get status => TimelineEventStatus.sending;

  @override
  List<Attachment>? get attachments => null;

  @override
  String? get formattedBody => html;

  @override
  String getPlaintextBody(Timeline timeline) => text;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => Text(text);

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Quieter Translate pills: no pill on short messages in a room you read,
// and "Hide in this room".
void main() {
  late Directory dir;
  late List<TranslationModelSpec> specs;
  late MessageTranslation t;
  late RoomTranslation rooms;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    dir = Directory.systemTemp.createTempSync("vommet-pill-quieter-test");
    final blobs = <String, List<int>>{};
    specs = [
      spec("es", "en", blobs),
      spec("en", "es", blobs),
      spec("sv", "en", blobs),
      spec("en", "sv", blobs),
    ];
    t = MessageTranslation(
      engine: FakeEngine(),
      baseDirectory: () async => dir,
      specs: specs,
      android: false,
      systemLanguage: () => "en",
    );
    rooms = RoomTranslation(translation: t);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group("rule", () {
    bool pill(String text, String? roomLanguage) => translatePillAllowed(
          language: t.translatableLanguage("ev$text", text),
          text: text,
          roomId: "!a",
          roomLanguage: () => roomLanguage,
          translation: t,
          rooms: rooms,
        );

    test("counts words and letters", () {
      expect(MessageTranslation.longEnoughForPill("Stockholm syndrome"), false);
      expect(MessageTranslation.longEnoughForPill("a b c d"), false);
      expect(
        MessageTranslation.longEnoughForPill("¿Dónde está la biblioteca?"),
        true,
      );
      expect(
        MessageTranslation.longEnoughForPill(
          "Stockholm syndrome is 12345 67890 !!",
        ),
        false,
      );
    });

    test("scripts without spaces: 8 of their characters are enough", () {
      expect(MessageTranslation.longEnoughForPill("我今天去图书馆看书了"), true);
      expect(MessageTranslation.longEnoughForPill("今日は雨が降っています"), true);
      expect(MessageTranslation.longEnoughForPill("วันนี้ฝนตกหนักมาก"), true);
      expect(MessageTranslation.longEnoughForPill("你好吗"), false);
      expect(
        translatePillAllowed(
          language: "zh",
          text: "我今天去图书馆看书了",
          roomId: "!a",
          roomLanguage: () => "en",
          translation: t,
          rooms: rooms,
        ),
        true,
      );
      expect(pill("[sv] Stockholm syndrome", "en"), false);
    });

    test("a short message in a room you read gets no pill", () {
      expect(pill("[sv] Stockholm syndrome", "en"), false);
    });

    test("a long message in a room you read still gets one", () {
      expect(pill("[es] ¿Dónde está la biblioteca, por favor?", "en"), true);
    });

    test("a room of unknown language or one you don't read: as before", () {
      expect(pill("[sv] Stockholm syndrome", null), true);
      expect(pill("[sv] Stockholm syndrome", "es"), true);
    });
  });

  group("settings", () {
    Map<String, dynamic> stored() => jsonDecode(
          Preference.preferences!.getString("message_translation_rooms")!,
        ) as Map<String, dynamic>;

    test("hide and undo keep the room's other settings", () async {
      await rooms.setOn("!a", true);
      await rooms.setFrom("!a", "es");
      await rooms.setPills("!a", false);
      expect(rooms.pillsShown("!a"), false);
      expect(rooms.isOn("!a"), true);
      expect(stored()["!a"], {
        "on": true,
        "from": "es",
        "write": true,
        "pills": false,
      });

      await rooms.setPills("!a", true);
      expect(rooms.pillsShown("!a"), true);
      expect(stored()["!a"], {"on": true, "from": "es", "write": true});
    });

    test(
      "old JSON without the field shows pills; unknown fields are kept",
      () async {
        await Preference.preferences!.setString(
          "message_translation_rooms",
          jsonEncode({
            "!a": {"on": false, "write": false, "later": 1},
          }),
        );
        expect(rooms.pillsShown("!a"), true);
        await rooms.setPills("!a", false);
        expect(stored()["!a"], {
          "later": 1,
          "on": false,
          "write": false,
          "pills": false,
        });
        expect(rooms.settingsFor("!a").translateWriting, false);
      },
    );
  });

  group("message menu", () {
    bool shows(String text, {String? html}) => eventShowsTranslatePill(
          _Timeline(),
          _Message(text, html: html),
          translation: t,
          rooms: rooms,
        );

    test("true on a message with a pill", () async {
      await rooms.setFrom("!a", "es");
      expect(shows("[sv] Stockholm syndrome"), true);
    });

    test("false in a hidden room", () async {
      await rooms.setFrom("!a", "es");
      await rooms.setPills("!a", false);
      expect(shows("[sv] Stockholm syndrome"), false);
    });

    test("false on a short message in a room you read", () async {
      await rooms.setFrom("!a", "en");
      expect(shows("[sv] Stockholm syndrome"), false);
      expect(shows("[es] ¿Dónde está la biblioteca, por favor?"), true);
    });

    test("room mode: true on a code block, which keeps its pill", () async {
      await rooms.setFrom("!a", "es");
      await rooms.setOn("!a", true);
      expect(shows("[es] ```hola```"), true);
      expect(shows("[es] hola", html: "<pre>hola</pre>"), true);
      t.stateFor(MessageTranslationFold.keyFor(r"$m", "[es] hola")).value =
          const TranslationDone("hello", from: "es", to: "en");
      expect(shows("[es] hola"), false);
    });

    testWidgets("an open translation: false; folded away: true", (
      tester,
    ) async {
      await tester.runAsync(() => rooms.setFrom("!a", "es"));
      const text = "[es] hola";
      t.stateFor(MessageTranslationFold.keyFor(r"$m", text)).value =
          const TranslationDone("hello", from: "es", to: "en");
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageTranslationFold.wrap(
              eventId: r"$m",
              text: text,
              roomId: "!a",
              roomLanguage: () => "es",
              translation: t,
              rooms: rooms,
              child: const Text(text),
            ),
          ),
        ),
      );
      expect(find.text("Show translation"), findsNothing);
      expect(shows(text), false);

      await tester.tap(find.byTooltip("Hide translation"));
      await tester.pump();
      expect(find.text("Show translation"), findsOneWidget);
      expect(shows(text), true);
    });

    testWidgets("the menu item follows the predicate", (tester) async {
      await tester.runAsync(() async {
        await preferences.init();
        await rooms.setFrom("!a", "en");
      });
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      TimelineEventMenu menu(String text) => TimelineEventMenu(
            timeline: _Timeline(),
            event: _Message(text),
            translation: t,
            rooms: rooms,
            context: context,
          );
      bool hasItem(TimelineEventMenu m) => m.secondaryActions.any(
            (e) => e.name == "Hide Translate in this room",
          );

      expect(hasItem(menu("[es] ¿Dónde está la biblioteca, por favor?")), true);
      expect(hasItem(menu("[sv] Stockholm syndrome")), false);

      // Asked again when the menu opens (desktop builds it ahead).
      final ahead = menu("[es] ¿Dónde está la biblioteca, por favor?");
      await tester.runAsync(() => rooms.setPills("!a", false));
      expect(ahead.showsTranslatePill(), false);
      expect(
        hasItem(menu("[es] ¿Dónde está la biblioteca, por favor?")),
        false,
      );
    });
  });

  group("voice transcripts", () {
    Widget transcript() => MaterialApp(
          home: Scaffold(
            // As TranscribableVoiceMessage wraps a transcript.
            body: MessageTranslationFold.wrap(
              eventId: "voice-transcript:f",
              text: "[es] hola",
              roomId: "!a",
              roomLanguage: () => rooms.knownLanguage("!a"),
              autoTranslatable: false,
              followsRoomMode: false,
              translation: t,
              rooms: rooms,
              child: const Text("[es] hola"),
            ),
          ),
        );

    testWidgets("hidden with the room, with Hide in this room in the menu", (
      tester,
    ) async {
      await tester.pumpWidget(transcript());
      expect(find.text("Translate"), findsOneWidget);
      await tester.longPress(find.text("Translate"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Hide in this room"));
      await tester.pumpAndSettle();
      expect(rooms.pillsShown("!a"), false);
      expect(find.text("Translate"), findsNothing);
    });

    testWidgets("short in a room you read: no pill", (tester) async {
      await tester.runAsync(() => rooms.setFrom("!a", "en"));
      await tester.pumpWidget(transcript());
      expect(find.text("Translate"), findsNothing);
    });

    testWidgets("the room mode leaves them alone", (tester) async {
      await tester.runAsync(() async {
        await rooms.setFrom("!a", "es");
        await rooms.setOn("!a", true);
      });
      await tester.pumpWidget(transcript());
      await tester.pump();
      expect(find.text("Translate"), findsOneWidget);
      expect(
        t
            .stateFor(
              MessageTranslationFold.keyFor("voice-transcript:f", "[es] hola"),
            )
            .value,
        isA<TranslationIdle>(),
      );
    });
  });

  group("widgets", () {
    testWidgets("the fold hides its pill in a hidden room, back after undo", (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageTranslationFold.wrap(
              eventId: "ev",
              text: "[es] hola",
              roomId: "!a",
              roomLanguage: () => null,
              translation: t,
              rooms: rooms,
              child: const Text("[es] hola"),
            ),
          ),
        ),
      );
      expect(find.text("Translate"), findsOneWidget);

      await tester.runAsync(() => rooms.setPills("!a", false));
      await tester.pump();
      expect(find.text("Translate"), findsNothing);
      expect(find.text("[es] hola"), findsOneWidget);

      await tester.runAsync(() => rooms.setPills("!a", true));
      await tester.pump();
      expect(find.text("Translate"), findsOneWidget);
    });

    testWidgets("the pill's long-press menu hides it with Undo", (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageTranslationFold.wrap(
              eventId: "ev",
              text: "[es] hola",
              roomId: "!a",
              roomLanguage: () => null,
              translation: t,
              rooms: rooms,
              child: const Text("[es] hola"),
            ),
          ),
        ),
      );
      await tester.longPress(find.text("Translate"));
      await tester.pumpAndSettle();
      expect(find.text("Turn off everywhere…"), findsOneWidget);
      await tester.tap(find.text("Hide in this room"));
      await tester.pumpAndSettle();
      expect(rooms.pillsShown("!a"), false);
      expect(find.text("Translate"), findsNothing);
      expect(find.text("Translate hidden in this room"), findsOneWidget);

      await tester.tap(find.text("Undo"));
      await tester.pumpAndSettle();
      expect(rooms.pillsShown("!a"), true);
      expect(find.text("Translate"), findsOneWidget);
    });

    testWidgets("a right-click on the pill opens its menu", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageTranslationFold.wrap(
              eventId: "ev",
              text: "[es] hola",
              roomId: "!a",
              roomLanguage: () => null,
              translation: t,
              rooms: rooms,
              child: const Text("[es] hola"),
            ),
          ),
        ),
      );
      await tester.tap(find.text("Translate"), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text("Hide in this room"), findsOneWidget);
      expect(find.text("Turn off everywhere…"), findsOneWidget);
    });

    testWidgets("the sheet's switch hides with the global button", (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoomTranslationSheet(room: _Room(), rooms: rooms),
            ),
          ),
        ),
      );
      expect(find.text("Translate buttons in this room"), findsOneWidget);
      await tester.runAsync(
        () => MessageTranslation.buttonPreference.set(false),
      );
      await tester.pump();
      expect(find.text("Translate buttons in this room"), findsNothing);
      await tester.runAsync(
        () => MessageTranslation.buttonPreference.set(true),
      );
      await tester.pump();
      expect(find.text("Translate buttons in this room"), findsOneWidget);
    });

    testWidgets("the sheet's switch follows the room", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoomTranslationSheet(room: _Room(), rooms: rooms),
            ),
          ),
        ),
      );
      bool row() => tester
          .widget<SettingsEntryBool>(
            find.ancestor(
              of: find.text("Translate buttons in this room"),
              matching: find.byType(SettingsEntryBool),
            ),
          )
          .state;
      expect(find.text("Translate buttons in this room"), findsOneWidget);
      expect(row(), true);

      await tester.runAsync(() => rooms.setPills("!a", false));
      await tester.pump();
      expect(row(), false);
    });
  });
}
