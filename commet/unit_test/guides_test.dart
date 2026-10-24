// Vommet: in-app guides, their pictures and links, the Settings filter, the
// right-click help and Getting started.
import 'dart:io';

import 'package:commet/main.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/pages/guides/getting_started.dart';
import 'package:commet/ui/pages/guides/guide_page.dart';
import 'package:commet/ui/pages/guides/guide_pictures.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:commet/ui/pages/guides/guides_settings_page.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:commet/ui/pages/setup/setup_page.dart';
import 'package:commet/utils/first_time_setup.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';

String guideText(String id) =>
    File("assets/guides/en/$id.md").readAsStringSync();

class _Other implements SetupMenu {
  @override
  Widget builder(BuildContext context) => const Text("other page");

  @override
  Stream<SetupMenuState> get onStateChanged => const Stream.empty();

  @override
  SetupMenuState get state => SetupMenuState.canProgress;

  @override
  Future<void> submit() async {}
}

void main() {
  setUp(() async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  Widget app(Widget child, {ThemeData? theme}) => MaterialApp(
        theme: theme ?? ThemeDark.theme,
        home: Scaffold(body: child),
      );

  test("every guide has its text, and its pictures and links exist", () {
    final ids = Guides.all.map((g) => g.id).toSet();
    expect(ids.length, Guides.all.length, reason: "duplicate guide id");
    for (final guide in Guides.all) {
      final text = guideText(guide.id);
      expect(text.trim(), isNotEmpty, reason: guide.id);
      for (final part in GuideText.parts(text)) {
        if (part.picture != null) {
          expect(GuidePicture.names, contains(part.picture),
              reason: "${guide.id}: unknown picture ${part.picture}");
        }
      }
      for (final link in RegExp(r"\]\((guide:[a-z-]+)\)").allMatches(text)) {
        expect(ids, contains(GuideText.guideLink(link.group(1))),
            reason: "${guide.id}: broken link ${link.group(1)}");
      }
    }
  });

  test("every guide file is listed", () {
    final files = Directory("assets/guides/en")
        .listSync()
        .map((f) => f.uri.pathSegments.last.replaceAll(".md", ""))
        .toSet();
    expect(files, Guides.all.map((g) => g.id).toSet());
  });

  test("a guide's text splits into Markdown and pictures", () {
    final parts = GuideText.parts("Intro\n\n[[picture: rail]]\n\nMore\n");
    expect(parts.map((p) => p.markdown ?? "picture:${p.picture}"),
        ["Intro", "picture:rail", "More"]);
    expect(GuideText.guideLink("guide:rooms"), "rooms");
    expect(GuideText.guideLink("https://example.org"), isNull);
  });

  test("the filter matches keywords and the guides' text", () {
    expect(Guides.filter("").length, Guides.all.length);
    expect(Guides.filter("server").map((g) => g.id),
        containsAll([Guides.spaces, Guides.accounts]));
    expect(Guides.filter("discord SERVER").map((g) => g.id), [Guides.spaces]);
    expect(Guides.filter("zebra"), isEmpty);
    expect(
        Guides.filter("zebra", texts: {Guides.voice: "a zebra call"})
            .map((g) => g.id),
        [Guides.voice]);
  });

  testWidgets("every picture draws in dark and light themes", (tester) async {
    for (final theme in [ThemeDark.theme, ThemeLight.theme]) {
      for (final name in GuidePicture.names) {
        await tester.pumpWidget(app(GuidePicture(name), theme: theme));
        expect(tester.takeException(), isNull, reason: name);
      }
    }
  });

  testWidgets("a guide shows its question, text and picture", (tester) async {
    String? opened;
    await tester.pumpWidget(app(SingleChildScrollView(
      child: GuideBody(
        guide: Guides.byId(Guides.spaces)!,
        text: guideText(Guides.spaces),
        onOpenGuide: (id) => opened = id,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text(guideSpacesQuestion), findsOneWidget);
    expect(find.byType(GuidePicture), findsOneWidget);
    expect(opened, isNull);
  });

  test("menu items only while the experiment is on", () async {
    await experimentGuides.set(false);
    final context = _FakeContext();
    expect(Guides.menuItem(context, Guides.spaces), isNull);
    await experimentGuides.set(true);
    expect(Guides.menuItem(context, Guides.spaces)?.text, guideSpacesQuestion);
    expect(Guides.menuItem(context, "nope"), isNull);
  });

  testWidgets("right-click an area for its guide", (tester) async {
    await experimentGuides.set(true);
    await tester.pumpWidget(app(const GuideArea(
        guide: Guides.rooms,
        child: SizedBox(width: 300, height: 300, child: Text("area")))));
    await tester.tap(find.text("area"), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text(guideRoomsQuestion), findsOneWidget);
  });

  testWidgets("no right-click help while the experiment is off",
      (tester) async {
    await experimentGuides.set(false);
    await tester.pumpWidget(app(const GuideArea(
        guide: Guides.rooms,
        child: SizedBox(width: 300, height: 300, child: Text("area")))));
    await tester.tap(find.text("area"), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text(guideRoomsQuestion), findsNothing);
  });

  test("Getting started: seven pages, ending on the right-click help", () {
    final menus = GettingStarted.menus();
    expect(menus.length, 7);
    expect(menus.last.picture, "menu");
    for (final m in menus) {
      expect(GuidePicture.names, contains(m.picture));
    }
  });

  test("Getting started is queued once, only with the experiment on", () async {
    FirstTimeSetup.postLogin.clear();
    await experimentGuides.set(false);
    GettingStarted.registerIfNew();
    expect(FirstTimeSetup.postLogin, isEmpty);

    await experimentGuides.set(true);
    GettingStarted.registerIfNew();
    expect(FirstTimeSetup.postLogin.length, 7);
    GettingStarted.registerIfNew();
    expect(FirstTimeSetup.postLogin.length, 7);
    FirstTimeSetup.postLogin.clear();
  });

  testWidgets("Skip leaves Getting started for the next setup page",
      (tester) async {
    await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    SetupPage([...GettingStarted.menus(), _Other()]))),
            child: const Text("open")))));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    expect(find.text(gettingStartedWelcomeTitle), findsOneWidget);
    await tester.tap(find.text(gettingStartedSkip));
    await tester.pumpAndSettle();
    expect(find.text("other page"), findsOneWidget);
  });

  testWidgets("a long menu scrolls in the phone sheet instead of overflowing",
      (tester) async {
    await preferences.layoutOverride.set("mobile");
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = [
      for (var i = 0; i < 14; i++)
        SpaceMenuEntry("Entry $i", Icons.circle, () {}),
      SpaceMenuEntry(guideSpacesQuestion, Icons.help_outline, () {}),
    ];
    await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
            onPressed: () => showEntryMenu(context, items, anchor: Rect.zero),
            child: const Text("open")))));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text(guideSpacesQuestion), 100,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    expect(find.text(guideSpacesQuestion), findsOneWidget);
  });

  testWidgets("Settings lists the guides and filters them", (tester) async {
    guidesRead.add(Guides.spaces);
    await tester.pumpWidget(app(SingleChildScrollView(
        child: GuidesSettingsPage(texts: {
      for (final g in Guides.all) g.id: guideText(g.id),
    }))));
    await tester.pumpAndSettle();
    expect(find.text(gettingStartedCardTitle), findsOneWidget);
    // The Getting started picture has its own labels, so look in the list.
    Finder listed(String title) =>
        find.descendant(of: find.byType(ListTile), matching: find.text(title));
    for (final g in Guides.all) {
      expect(listed(g.title), findsOneWidget);
    }
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey("guides-filter")), "guild");
    await tester.pumpAndSettle();
    expect(find.text(gettingStartedCardTitle), findsNothing);
    expect(find.text(guidesFilterCount(1, "guild")), findsOneWidget);
    expect(listed(guideSpacesTitle), findsOneWidget);
    expect(listed(guideVoiceTitle), findsNothing);
  });
}

class _FakeContext extends Fake implements BuildContext {}
