// The recovery key check-in's "That's the one. Keep it safe." is the
// dialog's own success state, not a snack bar: the main page has no
// Scaffold (the snack bar tripped a debug assertion there and didn't show in
// release builds). It closes by itself after ~1.5 s or on Done, once.

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Stand-in: with a check given, the dialog never touches the client.
class _MatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _title = "Still have your recovery key?";
const _ok = "That's the one. Keep it safe.";
const _wrong = "That's not it. Check your password manager has the whole key.";

void main() {
  late List<String?> results;
  late int passes;
  late int wrongs;

  /// A page without a Scaffold (like the main page) under a second plain
  /// page, so a second pop would show as the first page coming back.
  Future<void> open(WidgetTester tester,
      {bool keyIsRight = true, Future<bool> Function(String)? check}) async {
    results = [];
    passes = 0;
    wrongs = 0;
    // Tall enough for the whole dialog (its file option makes it taller
    // than the default 800x600 test window, where it scrolls).
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: TextButton(
                      onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (context) {
                            return ColoredBox(
                              color: Colors.black,
                              child: Center(
                                child: TextButton(
                                    onPressed: () async => results.add(
                                        await showCheckInDialogForTest(
                                            context, _MatrixClient(),
                                            method: RecoveryMethod.key,
                                            check: check ??
                                                (_) async => keyIsRight,
                                            onPassed: () => passes++,
                                            onWrong: () => wrongs++)),
                                    child: const Text("second page")),
                              ),
                            );
                          })),
                      child: const Text("first page")),
                ),
              )),
    ));
    await tester.tap(find.text("first page"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("second page"));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsOneWidget);
    await tester.enterText(find.byType(TextField), "EsTb Rk9x Wq2L mN7c");
    await tester.tap(find.text("Check"));
    await tester.pump();
  }

  void stillOnSecondPage() {
    expect(find.text("second page"), findsOneWidget);
    expect(find.text("first page"), findsNothing);
  }

  testWidgets("passed: success state in the dialog, closes by itself",
      (tester) async {
    await open(tester, keyIsRight: true);
    expect(find.text(_ok), findsOneWidget);
    expect(find.text("Done"), findsOneWidget);
    expect(find.text(_title), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(passes, 1);
    expect(results, isEmpty);

    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text(_ok), findsOneWidget, reason: "still showing at 1.4 s");
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text(_ok), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(results, ["ok"]);
    expect(passes, 1);
    stillOnSecondPage();
    expect(tester.takeException(), isNull);
  });

  testWidgets("Done closes at once; the timer doesn't pop again",
      (tester) async {
    await open(tester, keyIsRight: true);
    await tester.tap(find.text("Done"));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(results, ["ok"]);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(results, ["ok"]);
    expect(passes, 1);
    stillOnSecondPage();
    expect(tester.takeException(), isNull);
  });

  testWidgets("a tap outside the success state still counts as passed",
      (tester) async {
    await open(tester, keyIsRight: true);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(results, ["ok"], reason: "not null (= Remind me later)");
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(results, ["ok"]);
    stillOnSecondPage();
    expect(tester.takeException(), isNull);
  });

  testWidgets("wrong key: stays on the question", (tester) async {
    await open(tester, keyIsRight: false);
    await tester.pumpAndSettle();
    expect(find.text(_wrong), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_ok), findsNothing);
    expect(passes, 0);
    expect(wrongs, 1, reason: "resets the check-in streak");
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(Dialog), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets("the check itself failed: not counted as a wrong key",
      (tester) async {
    await open(tester, check: (_) async => throw Exception("offline"));
    await tester.pumpAndSettle();
    expect(find.text(_wrong), findsOneWidget);
    expect(wrongs, 0);
    expect(passes, 0);
  });
}
