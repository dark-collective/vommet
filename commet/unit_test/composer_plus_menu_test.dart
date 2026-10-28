import 'package:commet/main.dart';
import 'package:commet/ui/molecules/composer_plus_menu.dart';
import 'package:commet/ui/molecules/message_effect_picker.dart';
import 'package:commet/ui/molecules/composer_ring_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRoomTranslation extends ChangeNotifier
    implements ComposerPlusRoomTranslation {
  @override
  bool readingOn = false;
  @override
  bool writingOn = false;
  @override
  String? language = "es";
  @override
  String? writingLanguage = "es";
  String? pickedTitle;

  @override
  Future<void> setWritingLanguage(String code) async {
    writingLanguage = code;
    notifyListeners();
  }

  @override
  Future<void> setReading(bool on) async {
    readingOn = on;
    notifyListeners();
  }

  @override
  Future<void> setWriting(bool on) async {
    writingOn = on;
    notifyListeners();
  }

  @override
  Future<void> setLanguage(String code) async {
    language = code;
    notifyListeners();
  }

  @override
  Future<List<String>> shortList() async => ["es", "fr", "de"];

  @override
  Future<String?> pickMore(BuildContext context, {String? title}) async {
    pickedTitle = title;
    return "ja";
  }
}

// Vommet composer round 5: + holds SEND, IN THIS ROOM and THIS MESSAGE.
void main() {
  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  Future<void> pumpMenu(WidgetTester tester,
      {ComposerPlusRoomTranslation? translation,
      bool phone = true,
      List<String>? sent,
      void Function(MessageEffectOption?)? onEffect,
      MessageEffectOption? effect,
      void Function()? onSchedule}) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ComposerPlusMenu(
            phone: phone,
            send: [
              for (final label in ["Photo or video", "Camera", "File", "Poll"])
                ComposerPlusAction(
                    icon: Icons.attach_file,
                    label: label,
                    onTap: () => sent?.add(label)),
            ],
            translation: translation,
            showFormattingToolbar: phone,
            onSchedule: onSchedule ?? () {},
            effects: MessageEffectPicker.all,
            effect: effect,
            onEffect: onEffect ?? (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets("the three sections, in order", (tester) async {
    await pumpMenu(tester, translation: FakeRoomTranslation());
    final send = tester.getTopLeft(find.text(ComposerPlusMenu.labelSend)).dy;
    final room =
        tester.getTopLeft(find.text(ComposerPlusMenu.labelInThisRoom)).dy;
    final message =
        tester.getTopLeft(find.text(ComposerPlusMenu.labelThisMessage)).dy;
    expect(send, lessThan(room));
    expect(room, lessThan(message));

    for (final label in ["Photo or video", "Camera", "File", "Poll"]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(const ValueKey("composer-plus-translate-room")),
        findsOneWidget);
    expect(find.byKey(const ValueKey("composer-plus-translate-writing")),
        findsOneWidget);
    expect(find.byKey(const ValueKey("composer-formatting-toolbar-switch")),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey("composer-plus-schedule")), findsOneWidget);
    expect(find.byKey(const ValueKey("composer-plus-effect")), findsOneWidget);
    // No "Send with effect" anywhere.
    expect(find.textContaining("Send with effect"), findsNothing);
  });

  testWidgets("no translation = no translate rows", (tester) async {
    await pumpMenu(tester);
    expect(find.byKey(const ValueKey("composer-plus-translate-room")),
        findsNothing);
    expect(find.text(ComposerPlusMenu.labelInThisRoom), findsOneWidget);
  });

  testWidgets("desktop: no formatting toolbar switch", (tester) async {
    await pumpMenu(tester, phone: false);
    expect(find.byKey(const ValueKey("composer-formatting-toolbar-switch")),
        findsNothing);
    expect(find.text("File"), findsOneWidget);
  });

  testWidgets("translate switches; writing works without reading",
      (tester) async {
    final t = FakeRoomTranslation();
    await pumpMenu(tester, translation: t);
    Switch writing() => tester.widget<Switch>(
        find.byKey(const ValueKey("composer-plus-translate-writing-switch")));
    expect(writing().onChanged, isNotNull, reason: "usable in any room");
    expect(writing().value, isFalse);
    expect(find.text("into Spanish"), findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey("composer-plus-translate-writing-switch")));
    await tester.pump();
    expect((t.readingOn, t.writingOn), (false, true));
    expect(t.pickedTitle, isNull, reason: "a language is known");

    await tester
        .tap(find.byKey(const ValueKey("composer-plus-translate-room-switch")));
    await tester.pump();
    expect(t.readingOn, isTrue);
    expect(writing().value, isTrue);

    await tester.tap(
        find.byKey(const ValueKey("composer-plus-translate-writing-switch")));
    await tester.pump();
    expect(t.writingOn, isFalse);
  });

  testWidgets("writing with no language known asks for one first",
      (tester) async {
    final t = FakeRoomTranslation()..writingLanguage = null;
    await pumpMenu(tester, translation: t);
    await tester.tap(
        find.byKey(const ValueKey("composer-plus-translate-writing-switch")));
    await tester.pumpAndSettle();
    expect(t.pickedTitle, ComposerPlusMenu.labelWriteIn);
    expect((t.writingLanguage, t.writingOn), ("ja", true));
    expect(find.text("into Japanese"), findsOneWidget);
  });

  test("pills name each side's language", () {
    expect(
        ComposerStatePills.label(ComposerRingState.writing, "de"), "✎ German");
    expect(ComposerStatePills.label(ComposerRingState.reading, "es"),
        "文A Spanish");
  });

  testWidgets("the language chip opens the short list in place",
      (tester) async {
    final t = FakeRoomTranslation();
    await pumpMenu(tester, translation: t);
    expect(find.byKey(const ValueKey("composer-plus-language-list")),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey("composer-plus-language-chip")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("composer-plus-language-list")),
        findsOneWidget);
    expect(find.text(ComposerPlusMenu.labelMessagesAreIn), findsOneWidget);
    expect(find.byKey(const ValueKey("composer-plus-more-languages")),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("composer-plus-language-fr")));
    await tester.pumpAndSettle();
    expect(t.language, "fr");
    expect(find.byKey(const ValueKey("composer-plus-language-list")),
        findsNothing);
  });

  testWidgets("Effect opens the grid in place; picking sets it",
      (tester) async {
    MessageEffectOption? picked;
    var called = false;
    await pumpMenu(tester, onEffect: (e) {
      called = true;
      picked = e;
    });
    expect(find.text("None ▸"), findsOneWidget);
    expect(find.byKey(const ValueKey("effect-grid")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("composer-plus-effect")));
    await tester.pump();
    expect(find.byKey(const ValueKey("effect-grid")), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("effect-confetti")));
    await tester.pump();
    expect(called, isTrue);
    expect(picked?.command, "confetti");
  });

  testWidgets("picking the current effect again drops it", (tester) async {
    MessageEffectOption? picked = MessageEffectPicker.all.first;
    await pumpMenu(tester,
        effect: MessageEffectPicker.all.first, onEffect: (e) => picked = e);
    expect(find.textContaining("Confetti"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("composer-plus-effect")));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("effect-confetti")));
    await tester.pump();
    expect(picked, isNull);
  });

  testWidgets("a send action runs", (tester) async {
    final sent = <String>[];
    await pumpMenu(tester, sent: sent);
    await tester.tap(find.text("File"));
    await tester.pump();
    expect(sent, ["File"]);
  });
}
