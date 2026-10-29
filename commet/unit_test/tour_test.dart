// Vommet issue 758: the Getting started tour over the real app. A small
// stand-in for the rail (spaces column, a space with its menu, Home) carries
// the same anchors as the real one, and the test walks every step.

// unit_test/ isn't a directory the analyzer counts as tests.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:commet/main.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:commet/ui/pages/guides/tour/tour.dart';
import 'package:commet/ui/pages/guides/tour/tour_host.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Rail extends StatefulWidget {
  const _Rail({required this.counts});

  final Map<String, int> counts;

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  bool showHome = true;
  bool showSpace = true;

  void hideHome() => setState(() => showHome = false);
  void hideSpace() => setState(() => showSpace = false);

  void count(String what) =>
      widget.counts.update(what, (n) => n + 1, ifAbsent: () => 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          TourAnchor(
            id: TourAnchors.spaces,
            child: SizedBox(
              width: 72,
              child: Column(
                children: [
                  if (showHome)
                    TourAnchor(
                      id: TourAnchors.home,
                      child: IconButton(
                        key: const ValueKey("home"),
                        icon: const Icon(Icons.home),
                        onPressed: () => count("home"),
                      ),
                    ),
                  if (showSpace)
                    Builder(
                      builder: (context) => TourAnchor(
                        id: TourAnchors.space,
                        child: GestureDetector(
                          key: const ValueKey("space"),
                          onSecondaryTapUp: (_) => showEntryMenu(
                              context,
                              [
                                SpaceMenuEntry("Browse the rooms",
                                    Icons.travel_explore, () => count("browse"),
                                    tourAnchor: TourAnchors.browseRooms),
                                SpaceMenuEntry(
                                    "Leave space", Icons.logout, () {}),
                              ],
                              anchor: const Rect.fromLTWH(0, 120, 260, 0)),
                          child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: ColoredBox(color: Colors.green)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.bottomRight,
              child: TextButton(
                key: const ValueKey("outside"),
                onPressed: () => count("outside"),
                child: const Text("outside"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await experimentGuides.set(true);
    Tour.instance.reset();
  });

  tearDown(() => Tour.instance.reset());

  Future<Map<String, int>> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final counts = <String, int>{};
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      builder: (context, child) =>
          TourHost(touch: false, child: child ?? const SizedBox()),
      home: _Rail(counts: counts),
    ));
    await tester.pump();
    return counts;
  }

  // Text in the tour's bubble (not the menu).
  Finder bubble(String text) => find.descendant(
      of: find.byKey(const ValueKey("tour-bubble")), matching: find.text(text));

  // The tour's ticker keeps frames coming, so pumpAndSettle never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets("the offer starts the tour, and every step can be done",
      (tester) async {
    final counts = await pumpApp(tester);
    await tourOfferPending.set(true);
    Tour.instance.offerIfPending();
    await settle(tester);
    expect(find.text(tourOfferTitle), findsOneWidget);
    await tester.tap(find.text(tourStart));
    await settle(tester);
    expect(tourOfferPending.value, isFalse);

    // 1: the spaces column, a look step.
    expect(find.text(tourStepOf(1, 6)), findsOneWidget);
    expect(bubble(tourSpacesTitle), findsOneWidget);
    await tester.tap(find.text(tourNext));
    await settle(tester);

    // 2: open the space's menu. Taps elsewhere do nothing, and there's no
    // Next: the user does it.
    expect(bubble(tourBrowseTitle), findsOneWidget);
    expect(find.text(tourNext), findsNothing);
    await tester.tap(find.byKey(const ValueKey("outside")),
        warnIfMissed: false);
    await settle(tester);
    expect(counts["outside"], isNull);
    await tester.tap(find.byKey(const ValueKey("space")),
        buttons: kSecondaryButton);
    await settle(tester);

    // 2, its second part: Browse rooms in the open menu.
    expect(bubble(tourBrowseMenuTitle), findsOneWidget);
    expect(find.text(tourStepOf(2, 6)), findsOneWidget);
    // Closing the menu (a tap outside it) goes on.
    await tester.tapAt(const Offset(900, 400));
    await settle(tester);
    expect(find.text("Leave space"), findsNothing);

    // 3 and 4: in the middle, nothing dimmed or blocked.
    expect(bubble(tourChatTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("outside")));
    await settle(tester);
    expect(counts["outside"], 1);
    await tester.tap(find.text(tourNext));
    await settle(tester);
    expect(bubble(tourVoiceTitle), findsOneWidget);
    await tester.tap(find.text(tourNext));
    await settle(tester);

    // 5: tap Home; the tap reaches Home itself too.
    expect(bubble(tourHomeTitle), findsOneWidget);
    expect(find.text(tourNext), findsNothing);
    await tester.tap(find.byKey(const ValueKey("home")));
    await settle(tester);
    expect(counts["home"], 1);

    // 6: opening a guide finishes the tour; Done does too.
    expect(bubble(tourHelpTitle), findsOneWidget);
    expect(find.text(tourDone), findsOneWidget);
    Tour.instance.guideOpened();
    await settle(tester);
    expect(Tour.instance.state, TourState.idle);
    expect(find.byKey(const ValueKey("tour-bubble")), findsNothing);
    expect(gettingStartedDone.value, isTrue);
  });

  testWidgets("Browse rooms opened from the menu goes on too", (tester) async {
    final counts = await pumpApp(tester);
    Tour.instance.start();
    await settle(tester);
    await tester.tap(find.text(tourNext));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey("space")),
        buttons: kSecondaryButton);
    await settle(tester);
    await tester.tap(find.text("Browse the rooms"));
    await settle(tester);
    expect(counts["browse"], 1);
    expect(bubble(tourChatTitle), findsOneWidget);
  });

  testWidgets("without a space, the menu steps are left out", (tester) async {
    await pumpApp(tester);
    tester.state<_RailState>(find.byType(_Rail)).hideSpace();
    await settle(tester);
    Tour.instance.start();
    await settle(tester);
    await tester.tap(find.text(tourNext));
    await settle(tester);
    expect(bubble(tourChatTitle), findsOneWidget);
    expect(find.text(tourStepOf(3, 6)), findsOneWidget);
    // Back skips the left-out step too.
    await tester.tap(find.text(tourBack));
    await settle(tester);
    expect(bubble(tourSpacesTitle), findsOneWidget);
  });

  testWidgets("Home going away pauses the tour; resuming shows it centered",
      (tester) async {
    await pumpApp(tester);
    Tour.instance.start();
    await settle(tester);
    for (var i = 0;
        i < 10 && find.text(tourHomeTitle).evaluate().isEmpty;
        i++) {
      final next = find.text(tourNext);
      if (next.evaluate().isEmpty) {
        // The menu step: skip past it from the code side.
        Tour.instance.next();
      } else {
        await tester.tap(next);
      }
      await settle(tester);
    }
    tester.state<_RailState>(find.byType(_Rail)).hideHome();
    await settle(tester);
    await tester.pump(TourHost.pauseAfter);
    await settle(tester);
    expect(Tour.instance.state, TourState.paused);
    expect(find.text(tourResume(5, 6)), findsOneWidget);

    await tester.tap(find.text(tourResume(5, 6)));
    await settle(tester);
    expect(bubble(tourHomeTitle), findsOneWidget);
    // No Home to tap, so Next it is.
    expect(find.text(tourNext), findsOneWidget);
  });

  testWidgets("Skip ends the tour, and Not now declines the offer",
      (tester) async {
    await pumpApp(tester);
    await tourOfferPending.set(true);
    Tour.instance.offerIfPending();
    await settle(tester);
    await tester.tap(find.text(tourNotNow));
    await settle(tester);
    expect(Tour.instance.state, TourState.idle);
    expect(tourOfferPending.value, isFalse);
    Tour.instance.offerIfPending();
    expect(Tour.instance.state, TourState.idle, reason: "offered once");

    Tour.instance.start();
    await settle(tester);
    await tester.tap(find.text(tourSkip));
    await settle(tester);
    expect(Tour.instance.state, TourState.idle);
    expect(find.byKey(const ValueKey("tour-bubble")), findsNothing);
  });

  test("the bubble sits beside its element and stays on screen", () {
    const screen = Size(1000, 600);
    const bubble = Size(300, 150);
    // Room on the right: right of it, top-aligned.
    expect(bubblePosition(screen, bubble, const Rect.fromLTWH(0, 100, 80, 40)),
        const Offset(80, 100));
    // At the right edge: left of it.
    expect(
        bubblePosition(screen, bubble, const Rect.fromLTWH(900, 100, 80, 40)),
        const Offset(600, 100));
    // Low down: pulled up to stay on screen.
    expect(
        bubblePosition(screen, bubble, const Rect.fromLTWH(0, 560, 80, 30)).dy,
        600 - 150 - 12);
    // No element: in the middle.
    expect(bubblePosition(screen, bubble, null), const Offset(350, 225));
  });

  test("Getting started's tour has six steps, the menu one in two parts", () {
    final steps = tourSteps();
    expect(Tour(steps: steps).total, 6);
    expect(steps.where((s) => s.number == 2).length, 2);
    expect(steps.last.kind, TourStepKind.untilGuide);
  });
}
