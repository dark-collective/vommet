// Vommet issue 974: on iPad (and desktop/tablet multi-pane layouts),
// the message composer does not end at the bottom of the screen.
// When the on-screen keyboard opens, KeyboardAdaptor must size its bottom
// spacer to the actual overlap with the keyboard rather than the window's
// full viewInsets.bottom, so the composer sits directly above the keyboard
// with no empty gap.
//
// No resizing Scaffold wraps the adaptor: Scaffold's
// resizeToAvoidBottomInset strips viewInsets from its body's MediaQuery,
// which would hide the keyboard from the adaptor entirely.

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/keyboard_adaptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const composerKey = ValueKey("composer-box");
const composerHeight = 50.0;

void setUpView(WidgetTester tester, Size size, {double homeIndicator = 0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding(bottom: homeIndicator);
  tester.view.padding = FakeViewPadding(bottom: homeIndicator);
  addTearDown(tester.view.reset);
}

// Like the engine, padding loses the part of viewPadding the keyboard covers.
Future<void> setKeyboard(WidgetTester tester, double height,
    {double homeIndicator = 0}) async {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  tester.view.padding = FakeViewPadding(bottom: height > 0 ? 0 : homeIndicator);
  await tester.pumpAndSettle();
}

// A timeline filling the available height, the adaptor holding the
// composer, then [below] points of fixed-height content under the adaptor.
Widget buildTree({double below = 0, KeyboardAdaptorController? controller}) =>
    MaterialApp(
      home: Column(
        children: [
          const Expanded(child: SizedBox.expand()),
          KeyboardAdaptor(
            controller: controller,
            // Like the composer when no picker search field is focused.
            shouldPushContent: () => false,
            child: const SizedBox(
              key: composerKey,
              height: composerHeight,
              width: double.infinity,
            ),
          ),
          SizedBox(height: below),
        ],
      ),
    );

void main() {
  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets("iPad: composer ending above the screen bottom meets keyboard",
      (tester) async {
    setUpView(tester, const Size(1210, 834));
    const below = 98.0;
    const keyboardHeight = 428.0; // keyboard from y=406 to y=834

    await tester.pumpWidget(buildTree(below: below));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(composerKey)).bottom, 834.0 - below);

    await setKeyboard(tester, keyboardHeight);
    expect(
        tester.getRect(find.byKey(composerKey)).bottom, 834.0 - keyboardHeight);
  });

  testWidgets("phone: adaptor at the screen bottom uses the full inset",
      (tester) async {
    setUpView(tester, const Size(393, 852));
    const keyboardHeight = 336.0;

    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(composerKey)).bottom, 852.0);

    await setKeyboard(tester, keyboardHeight);
    expect(
        tester.getRect(find.byKey(composerKey)).bottom, 852.0 - keyboardHeight);
  });

  testWidgets("home indicator leaves no gap above the keyboard",
      (tester) async {
    const homeIndicator = 20.0;
    const keyboardHeight = 428.0; // keyboard top at y=406

    for (final below in [98.0, 420.0]) {
      setUpView(tester, const Size(1210, 834), homeIndicator: homeIndicator);
      await tester.pumpWidget(buildTree(below: below));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(composerKey)).bottom,
          834.0 - below - homeIndicator,
          reason: "closed, below=$below");

      // below=420 overlaps the keyboard by only 8 pt, less than the
      // home indicator padding.
      await setKeyboard(tester, keyboardHeight, homeIndicator: homeIndicator);
      expect(tester.getRect(find.byKey(composerKey)).bottom,
          834.0 - keyboardHeight,
          reason: "open, below=$below");

      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets("iPad: emoji picker replacing the keyboard keeps its height",
      (tester) async {
    setUpView(tester, const Size(1210, 834));
    const below = 98.0;
    const keyboardHeight = 428.0;
    final controller = KeyboardAdaptorController();

    await tester.pumpWidget(buildTree(below: below, controller: controller));
    await tester.pumpAndSettle();
    await setKeyboard(tester, keyboardHeight);
    expect(
        tester.getRect(find.byKey(composerKey)).bottom, 834.0 - keyboardHeight);

    controller.keepCurrentSize!();
    expect(preferences.emojiPickerHeight.value, keyboardHeight - below);

    // The keyboard hides; the picker takes its place at the same height.
    await setKeyboard(tester, 0);
    expect(controller.hasOverride!(), isTrue);
    expect(
        tester.getRect(find.byKey(composerKey)).bottom, 834.0 - keyboardHeight);
  });

  testWidgets("phone: partial inset over the home indicator keeps it",
      (tester) async {
    setUpView(tester, const Size(393, 852), homeIndicator: 34);

    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(composerKey)).bottom, 852.0 - 34);

    // Mid-animation: the keyboard covers half of the home indicator.
    tester.view.viewInsets = FakeViewPadding(bottom: 17);
    tester.view.padding = FakeViewPadding(bottom: 17);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(composerKey)).bottom, 852.0 - 34);
  });

  testWidgets("iPad: small overlap with a full keyboard stores the overlap",
      (tester) async {
    setUpView(tester, const Size(1210, 834));
    const below = 200.0;
    const keyboardHeight = 428.0; // overlap 228, under the 300 minimum
    final controller = KeyboardAdaptorController();

    await tester.pumpWidget(buildTree(below: below, controller: controller));
    await tester.pumpAndSettle();
    await setKeyboard(tester, keyboardHeight);

    controller.keepCurrentSize!();
    expect(preferences.emojiPickerHeight.value, keyboardHeight - below);

    await setKeyboard(tester, 0);
    expect(
        tester.getRect(find.byKey(composerKey)).bottom, 834.0 - keyboardHeight);
  });

  testWidgets("iPad: composer above the keyboard keeps the stored height",
      (tester) async {
    setUpView(tester, const Size(1210, 834));
    const below = 500.0; // above the keyboard top: no overlap
    const keyboardHeight = 428.0;
    final controller = KeyboardAdaptorController();
    final stored = preferences.emojiPickerHeight.value;

    await tester.pumpWidget(buildTree(below: below, controller: controller));
    await tester.pumpAndSettle();
    await setKeyboard(tester, keyboardHeight);

    controller.keepCurrentSize!();
    expect(preferences.emojiPickerHeight.value, stored);
    expect(stored, greaterThan(0));
  });

  testWidgets("iPad portrait: composer meets the keyboard", (tester) async {
    const keyboardHeight = 320.0;

    for (final below in [0.0, 100.0]) {
      setUpView(tester, const Size(820, 1180));
      await tester.pumpWidget(buildTree(below: below));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(composerKey)).bottom, 1180.0 - below,
          reason: "closed, below=$below");

      await setKeyboard(tester, keyboardHeight);
      expect(tester.getRect(find.byKey(composerKey)).bottom,
          1180.0 - keyboardHeight,
          reason: "open, below=$below");

      await tester.pumpWidget(const SizedBox());
    }
  });
}
