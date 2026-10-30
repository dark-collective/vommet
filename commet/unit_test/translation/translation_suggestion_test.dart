// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_fakes.dart';

// Vommet issue 834: the "This room is mostly in Spanish. Translate it?"
// banner can be turned off in every room.
void main() {
  late Directory dir;
  late Map<String, List<int>> blobs;
  late List<TranslationModelSpec> specs;

  MessageTranslation service() => MessageTranslation(
        engine: FakeEngine(),
        baseDirectory: () async => dir,
        specs: specs,
        android: false,
        systemLanguage: () => "en",
      );

  ComposerTranslation make(String room) {
    final t = service();
    return ComposerTranslation(
        roomId: room,
        translation: t,
        rooms: RoomTranslation(translation: t),
        recentTextsFromOthers: () => ["[es] hola", "[es] ¿qué tal?"]);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    dir = Directory.systemTemp.createTempSync("vommet-suggest-test");
    blobs = {};
    specs = [spec("es", "en", blobs), spec("en", "es", blobs)];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test("suggested by default; not in this room keeps other rooms", () async {
    expect(ComposerTranslationPrefs.suggestPreference.value, isTrue);
    final a = make("!a");
    expect(a.suggestedLanguage, "es");
    await a.dismissSuggestion();
    expect(a.suggestedLanguage, isNull);
    expect(make("!b").suggestedLanguage, "es");
  });

  test("don't suggest in any room, until turned back on", () async {
    final a = make("!a");
    var changes = 0;
    a.addListener(() => changes++);
    await a.stopSuggesting();
    expect(changes, 1);
    expect(ComposerTranslationPrefs.suggestPreference.value, isFalse);
    expect(a.suggestedLanguage, isNull);
    expect(make("!b").suggestedLanguage, isNull);

    await ComposerTranslationPrefs.suggestPreference.set(true);
    expect(make("!b").suggestedLanguage, "es");
  });

  test("no suggestion for a language you read", () async {
    await MessageTranslation.readPreference.set(["es"]);
    expect(make("!a").suggestedLanguage, isNull);
    await MessageTranslation.readPreference.set([]);
    expect(make("!a").suggestedLanguage, "es");
  });

  test("no suggestion while translation is off", () async {
    await MessageTranslation.enabledPreference.set(false);
    expect(make("!a").suggestedLanguage, isNull);
    await MessageTranslation.enabledPreference.set(true);
    expect(make("!a").suggestedLanguage, "es");
  });

  test("a room in a language you read: readsRoom, picked language first",
      () async {
    final t = service();
    final rooms = RoomTranslation(translation: t);
    expect(rooms.readsRoom("!a", () => "en"), isTrue);
    expect(rooms.readsRoom("!a", () => "es"), isFalse);
    expect(rooms.readsRoom("!a", () => null), isFalse);
    await MessageTranslation.readPreference.set(["es"]);
    expect(rooms.readsRoom("!a", () => "es"), isTrue);
  });

  group("the banner's ✕", () {
    Future<(int, int)> pick(WidgetTester tester, String item,
        {VoidCallback? onStop}) async {
      var dismissed = 0, stopped = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ComposerTranslationSuggestion(
                  language: "es",
                  onTranslate: () {},
                  onDismiss: () => dismissed++,
                  onStopSuggesting: onStop == null
                      ? null
                      : () {
                          stopped++;
                          onStop();
                        }))));
      expect(find.textContaining("mostly in Spanish"), findsOneWidget);
      await tester.tap(
          find.byKey(const ValueKey("composer-translate-suggestion-close")));
      await tester.pumpAndSettle();
      expect(find.text("Not in this room"), findsOneWidget);
      expect(find.text("Don't suggest in any room"), findsOneWidget);
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
      return (dismissed, stopped);
    }

    testWidgets("not in this room", (tester) async {
      expect(await pick(tester, "Not in this room"), (1, 0));
      expect(ComposerTranslationPrefs.suggestPreference.value, isTrue);
    });

    testWidgets("in no room: turns the setting off, then dismisses",
        (tester) async {
      await tester.runAsync(() async {
        await pick(tester, "Don't suggest in any room");
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(ComposerTranslationPrefs.suggestPreference.value, isFalse);
    });

    testWidgets("in no room calls the given handler", (tester) async {
      expect(await pick(tester, "Don't suggest in any room", onStop: () {}),
          (0, 1));
    });
  });
}
