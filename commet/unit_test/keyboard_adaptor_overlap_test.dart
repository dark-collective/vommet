// Vommet issue 974: on iPad (and desktop/tablet multi-pane layouts),
// the message composer is offset by headers and caulked tiles.
// When the on-screen keyboard opens, KeyboardAdaptor must size its bottom
// spacer to the actual overlap with the keyboard rather than the window's
// full viewInsets.bottom, so the composer sits directly above the keyboard
// with no empty gap.

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/keyboard_adaptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets(
      "KeyboardAdaptor sizes spacer to actual overlap when offset by header",
      (tester) async {
    tester.view.physicalSize = const Size(1210, 834);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    tester.view.padding = FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    const headerHeight = 98.0;
    const composerHeight = 50.0;
    const keyboardHeight = 428.0; // keyboard from y=406 to y=834

    // A layout mimicking RoomChatLayout: a 98 pt header, then a chat column
    // with a timeline filling available height and a composer at the bottom.
    Widget buildTree() => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: headerHeight),
                Expanded(
                  child: Column(
                    children: [
                      const Expanded(
                        child: SizedBox.expand(),
                      ),
                      KeyboardAdaptor(
                        child: const SizedBox(
                          key: ValueKey("composer-box"),
                          height: composerHeight,
                          width: double.infinity,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();

    final composerBox = find.byKey(const ValueKey("composer-box"));
    final closedRect = tester.getRect(composerBox);
    // Closed keyboard: composer sits at the bottom of the screen (y = 834 - 50 = 784).
    expect(closedRect.bottom, equals(834.0));
    expect(closedRect.top, equals(834.0 - composerHeight));

    // Open keyboard (height = 428 pt, top of keyboard is at y = 406.0).
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();

    final openRect = tester.getRect(composerBox);
    // Composer must sit directly above the keyboard top (y = 406.0) with no gap.
    expect(openRect.bottom, equals(834.0 - keyboardHeight));
    expect(openRect.top, equals(834.0 - keyboardHeight - composerHeight));
  });

  testWidgets(
      "KeyboardAdaptor uses full inset when edge-to-edge at screen bottom",
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    tester.view.padding = FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    const composerHeight = 50.0;
    const keyboardHeight = 336.0;

    Widget buildTree() => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox.expand()),
                KeyboardAdaptor(
                  child: const SizedBox(
                    key: ValueKey("composer-box"),
                    height: composerHeight,
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();

    final composerBox = find.byKey(const ValueKey("composer-box"));
    expect(tester.getRect(composerBox).bottom, equals(852.0));

    // Open keyboard
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();

    final openRect = tester.getRect(composerBox);
    expect(openRect.bottom, equals(852.0 - keyboardHeight));
  });
}
