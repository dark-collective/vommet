import 'package:commet/config/platform_utils.dart';
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late bool window;
  late List<bool> calls;

  setUp(() {
    window = false;
    calls = [];
    LightboxFullScreen.isWindowFullScreen = () async => window;
    LightboxFullScreen.setWindowFullScreen = (value) async {
      calls.add(value);
      window = value;
    };
  });

  // Not awaiting the window calls here: a widget test's ones belong to its
  // fake-async zone.
  tearDown(LightboxFullScreen.exit);

  group("LightboxFullScreen", () {
    test("puts the window in full screen and back", () async {
      LightboxFullScreen.enter();
      expect(LightboxFullScreen.active.value, isTrue);
      await LightboxFullScreen.settled;
      expect(window, isTrue);

      expect(LightboxFullScreen.exitIfActive(), isTrue);
      expect(LightboxFullScreen.active.value, isFalse);
      await LightboxFullScreen.settled;
      expect(window, isFalse);
      expect(calls, [true, false]);
    });

    test("leaves a window that was already full screen as it was", () async {
      window = true;
      LightboxFullScreen.enter();
      LightboxFullScreen.exit();
      await LightboxFullScreen.settled;
      expect(window, isTrue);
      expect(calls, isEmpty);
    });

    test("ESC does nothing when not full screen", () {
      expect(LightboxFullScreen.exitIfActive(), isFalse);
      expect(calls, isEmpty);
    });
  });

  // Vommet issues 755 and 756: on phones the system bars hide instead.
  group("on a phone", () {
    late List<bool> bars;

    setUp(() {
      bars = [];
      LightboxSystemBars.supported = () => true;
      LightboxSystemBars.setHidden = (hidden) async => bars.add(hidden);
    });

    tearDown(() {
      LightboxFullScreen.exit();
      LightboxSystemBars.supported =
          () => PlatformUtils.isAndroid || PlatformUtils.isIOS;
    });

    test("full screen hides the system bars, not the window", () async {
      LightboxFullScreen.enter();
      expect(LightboxSystemBars.hidden, isTrue);
      expect(bars, [true]);

      LightboxFullScreen.exit();
      expect(LightboxSystemBars.hidden, isFalse);
      expect(bars, [true, false]);
      await LightboxFullScreen.settled;
      expect(calls, isEmpty);
    });

    test("the bars come back only when nothing hides them", () async {
      final zoom = Object();
      LightboxSystemBars.hide(zoom);
      LightboxFullScreen.enter();
      LightboxSystemBars.show(zoom);
      expect(LightboxSystemBars.hidden, isTrue);
      expect(bars, [true]);

      LightboxFullScreen.exit();
      expect(bars, [true, false]);
    });

    testWidgets("back leaves full screen before it closes the viewer",
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const SizedBox.expand(),
      ));
      navigator.currentState!.push(MaterialPageRoute(
          builder: (_) => const LightboxFullScreenScope(
              child: SizedBox.expand(key: ValueKey("viewer")))));
      await tester.pumpAndSettle();

      LightboxFullScreen.enter();
      await tester.pump();
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(LightboxFullScreen.active.value, isFalse);
      expect(find.byKey(const ValueKey("viewer")), findsOneWidget);

      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("viewer")), findsNothing);
      expect(bars, [true, false]);
    });
  });

  testWidgets("the video's X hides after 3 s without mouse movement",
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LightboxFullScreenExit(child: SizedBox.expand()),
    ));
    final x = find.byKey(const ValueKey("lightbox_full_screen_exit"));
    double opacity() => tester
        .widget<AnimatedOpacity>(
            find.ancestor(of: x, matching: find.byType(AnimatedOpacity)))
        .opacity;

    expect(opacity(), 1);
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(), 1);
    await tester.pump(const Duration(seconds: 1, milliseconds: 1));
    expect(opacity(), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    await mouse.moveTo(const Offset(120, 110));
    await tester.pump();
    expect(opacity(), 1);
    await mouse.removePointer();

    LightboxFullScreen.enter();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(x);
    expect(LightboxFullScreen.active.value, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("ESC in a viewer leaves full screen; closing restores the window",
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LightboxFullScreenScope(child: SizedBox.expand()),
    ));
    LightboxFullScreen.enter();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(LightboxFullScreen.active.value, isFalse);

    LightboxFullScreen.enter();
    await tester.pumpWidget(const SizedBox());
    expect(LightboxFullScreen.active.value, isFalse);
  });
}
