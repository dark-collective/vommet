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
      bool tablet = false,
      double width = 412,
      List<String>? sent,
      void Function(MessageEffectOption?)? onEffect,
      MessageEffectOption? effect,
      void Function()? onSchedule}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ComposerPlusMenu(
            phone: phone,
            tablet: tablet,
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

  Future<void> pumpPills(WidgetTester tester,
      {required bool compact, required void Function() onTap}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: ComposerStatePills(
                    states: const [
                      ComposerRingState.reading,
                      ComposerRingState.writing
                    ],
                    language: "es",
                    writingLanguage: "de",
                    compact: compact,
                    colors: const [Color(0xFF8B7CF6), Color(0xFF2BB3A3)],
                    onTap: onTap)))));
  }

  testWidgets("phone pills are just the colored icons", (tester) async {
    var taps = 0;
    await pumpPills(tester, compact: true, onTap: () => taps++);
    expect(find.text("文A"), findsOneWidget);
    expect(find.text("✎"), findsOneWidget);
    expect(find.textContaining("Spanish"), findsNothing);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey("composer-pill-writing")))
            .style
            ?.color,
        const Color(0xFF2BB3A3));
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel("文A Spanish, ✎ German"), findsOneWidget);
    semantics.dispose();
    await tester.tap(find.text("✎"));
    expect(taps, 1);
  });

  testWidgets("desktop pills keep the language names", (tester) async {
    await pumpPills(tester, compact: false, onTap: () {});
    expect(find.text("文A Spanish"), findsOneWidget);
    expect(find.text("✎ German"), findsOneWidget);
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

  // Vommet issue 943: on an iPad the keyboard closes when the menu opens,
  // and the menu has to move down with +.
  testWidgets("desktop menu follows + when the keyboard closes",
      (tester) async {
    tester.view.physicalSize = const Size(1210, 834);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    addTearDown(tester.view.reset);
    final plusKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const Expanded(child: SizedBox()),
          Row(children: [
            const SizedBox(width: 260),
            Builder(
                builder: (context) => IconButton(
                    key: plusKey,
                    icon: const Icon(Icons.add),
                    onPressed: () => showComposerPlusMenu(context,
                        anchor: plusKey.currentContext,
                        builder: (context, phone) => ComposerPlusMenu(
                              phone: phone,
                              send: [
                                ComposerPlusAction(
                                    icon: Icons.attach_file,
                                    label: "File",
                                    onTap: () {}),
                              ],
                            )))),
          ]),
        ]),
      ),
    ));

    Rect menu() =>
        tester.getRect(find.byKey(const ValueKey("composer-plus-menu")).first);
    void expectAbovePlus() {
      final plus = tester.getRect(find.byKey(plusKey));
      final material = tester.getRect(find
          .ancestor(
              of: find.byKey(const ValueKey("composer-plus-menu")),
              matching: find.byType(Material))
          .first);
      expect(material.bottom, plus.top - ComposerPlusPopover.gap);
      expect(material.left, plus.left);
    }

    await tester.tap(find.byKey(plusKey));
    await tester.pumpAndSettle();
    expect(menu().top, greaterThan(0));
    expectAbovePlus();

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(plusKey)).top, greaterThan(700));
    expectAbovePlus();
  });

  testWidgets("tablet: SEND tiles and touch-sized rows", (tester) async {
    // The narrowest tablet menu, with every row: nothing may overflow.
    await pumpMenu(tester,
        phone: false,
        tablet: true,
        width: ComposerPlusPopover.tabletMinWidth,
        translation: FakeRoomTranslation());
    expect(find.byType(CircleAvatar), findsNWidgets(4));
    expect(
        tester
            .getSize(find.byKey(const ValueKey("composer-plus-schedule")))
            .height,
        52);
    expect(find.byKey(const ValueKey("composer-formatting-toolbar-switch")),
        findsNothing);
  });

  testWidgets("desktop keeps rows for SEND", (tester) async {
    await pumpMenu(tester, phone: false);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(
        tester
            .getSize(find.byKey(const ValueKey("composer-plus-schedule")))
            .height,
        44);
  });

  test("tablet menu width follows the screen's shorter side", () {
    double width(Size size, {bool tablet = true}) =>
        ComposerPlusPopover.widthFor(size, tablet: tablet);
    expect(width(const Size(1210, 834), tablet: false), 320);
    // iPad Pro 11": the same in landscape and portrait.
    expect(width(const Size(1210, 834)), closeTo(375.3, 0.1));
    expect(width(const Size(834, 1210)), closeTo(375.3, 0.1));
    // iPad mini and iPad Pro 13" hit the limits.
    expect(width(const Size(1133, 744)), 360);
    expect(width(const Size(1376, 1032)), 440);
  });
}
