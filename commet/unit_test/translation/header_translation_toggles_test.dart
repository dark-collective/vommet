// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/molecules/room_translation_views.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_fakes.dart';

// Vommet issue 818: 文A / ✎ translation toggles in the room header.
void main() {
  late Directory dir;
  late List<TranslationModelSpec> specs;
  final prefs = ComposerTranslationPrefs.instance;

  RoomTranslation rooms() => RoomTranslation(
      translation: MessageTranslation(
          engine: FakeEngine(),
          baseDirectory: () async => dir,
          specs: specs,
          android: false,
          systemLanguage: () => "en"));

  RoomTranslationToggleState state(RoomTranslation r, String? detected) =>
      RoomTranslationToggleState.of(r, prefs, "!a", () => detected);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    dir = Directory.systemTemp.createTempSync("vommet-header-toggles-test");
    final blobs = <String, List<int>>{};
    specs = [
      spec("es", "en", blobs),
      spec("en", "es", blobs),
      spec("de", "en", blobs),
      spec("en", "de", blobs),
    ];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group("toggle state", () {
    test("both off and outlined by default", () {
      final s = state(rooms(), "es");
      expect((s.visible, s.reading, s.writing), (true, false, false));
      expect((s.readLanguage, s.writeLanguage), (null, null));
    });

    test("hidden while the Translation switch is off", () async {
      await MessageTranslation.enabledPreference.set(false);
      final r = rooms();
      await r.setOn("!a", true);
      expect(state(r, "es").visible, isFalse);
    });

    test("reading on names the room's language, picked over detected",
        () async {
      final r = rooms();
      await r.setOn("!a", true);
      var s = state(r, "es");
      expect((s.reading, s.readLanguage), (true, "es"));
      // Turning the room on also writes translated (saved default).
      expect((s.writing, s.writeLanguage), (true, "es"));
      await r.setFrom("!a", "de");
      s = state(r, "es");
      expect((s.readLanguage, s.writeLanguage), ("de", "de"));
    });

    test("writing on its own, in a room that isn't translated", () async {
      final r = rooms();
      await r.setTranslateWriting("!a", true);
      var s = state(r, "es");
      expect((s.reading, s.writing, s.writeLanguage), (false, true, "es"));
      // The language picked for this room wins over the detected one.
      await prefs.setTarget("!a", "de");
      s = state(r, "es");
      expect(s.writeLanguage, "de");
    });

    test("writing falls back to the last language picked", () async {
      final r = rooms();
      await prefs.setTarget("!other", "de");
      await r.setTranslateWriting("!a", true);
      expect(state(r, null).writeLanguage, "de");
    });

    test("the two toggles are independent", () async {
      final r = rooms();
      await r.setOn("!a", true);
      await r.setTranslateWriting("!a", false);
      var s = state(r, "es");
      expect((s.reading, s.writing), (true, false));
      await r.setOn("!a", false);
      await r.setTranslateWriting("!a", true);
      s = state(r, "es");
      expect((s.reading, s.writing), (false, true));
    });

    test("labels are short codes", () {
      expect(toggleLanguageLabel("es"), "ES");
      expect(toggleLanguageLabel("zh-Hant"), "ZH");
      expect(toggleLanguageLabel("pt_BR"), "PT");
    });
  });

  group("toggle button", () {
    Future<List<String>> pump(WidgetTester tester,
        {required bool on, String? label}) async {
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: RoomTranslationToggle(
              icon: Icons.translate,
              on: on,
              label: label,
              tooltip: "Translate this room (hold for settings)",
              onTap: () => calls.add("tap"),
              onSettings: () => calls.add("settings"),
            ),
          ),
        ),
      ));
      return calls;
    }

    testWidgets("off: icon only; tap toggles, no popup", (tester) async {
      final calls = await pump(tester, on: false, label: "es");
      expect(find.text("ES"), findsNothing);
      await tester.tap(find.byIcon(Icons.translate));
      expect(calls, ["tap"]);
    });

    testWidgets("on: filled with the language; long-press opens settings",
        (tester) async {
      final calls = await pump(tester, on: true, label: "es");
      expect(find.text("ES"), findsOneWidget);
      await tester.longPress(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();
      expect(calls, ["settings"]);
    });
  });
}
