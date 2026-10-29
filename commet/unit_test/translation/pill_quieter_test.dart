// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/molecules/room_translation_views.dart';
import 'package:commet/ui/molecules/settings_entry_bool.dart';
import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
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
