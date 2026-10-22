import 'package:commet/ui/pages/matrix/verification/matrix_verification_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

Widget _view(KeyVerificationState state,
        {String? code, bool here = false, bool own = true}) =>
    MaterialApp(
      // Inside AlertDialog like the desktop popup: it asks for intrinsic
      // sizes, which some layouts (LayoutBuilder) can't give.
      home: AlertDialog(
        content: SingleChildScrollView(
            child: MatrixVerificationPageView(
          state: state,
          sasTypes: const ["decimal"],
          sasNumbers: const [4127, 938, 6605],
          sasEmoji: const [],
          userID: "@mira:example.org",
          ownUser: own,
          otherName: "Pixel 8",
          otherDetail: "OKWBNXJTFE",
          canceledCode: code,
          cancelledHere: here,
        )),
      ),
    );

void main() {
  test("cancel codes map to the screens the user sees", () {
    expect(verificationEndFor("m.accepted", here: false),
        VerificationEnd.handledElsewhere);
    expect(verificationEndFor("m.user", here: false),
        VerificationEnd.cancelledThere);
    expect(verificationEndFor("m.user", here: true),
        VerificationEnd.cancelledHere);
    expect(
        verificationEndFor("m.timeout", here: false), VerificationEnd.expired);
    for (final c in [
      "m.mismatched_sas",
      "m.key_mismatch",
      "m.mismatched_commitment"
    ]) {
      expect(verificationEndFor(c, here: false), VerificationEnd.mismatch);
    }
    expect(verificationEndFor("m.unknown_method", here: false),
        VerificationEnd.failed);
    expect(verificationEndFor(null, here: false), VerificationEnd.failed);
  });

  testWidgets("no state shows a raw state name", (tester) async {
    for (final state in KeyVerificationState.values) {
      await tester.pumpWidget(_view(state, code: "m.accepted"));
      expect(find.textContaining("KeyVerificationState"), findsNothing,
          reason: "$state");
      expect(tester.takeException(), isNull, reason: "$state");
    }
  });

  testWidgets("another device answering is explained, not an error",
      (tester) async {
    await tester
        .pumpWidget(_view(KeyVerificationState.error, code: "m.accepted"));
    expect(find.text("Handled on another device"), findsOneWidget);
  });

  testWidgets("numbers are shown when the other app can't show emoji",
      (tester) async {
    await tester.pumpWidget(_view(KeyVerificationState.askSas));
    expect(find.text("Compare numbers"), findsOneWidget);
    expect(find.text("0938"), findsOneWidget);
  });

  testWidgets("a mismatch warns", (tester) async {
    await tester.pumpWidget(
        _view(KeyVerificationState.error, code: "m.mismatched_sas"));
    expect(find.text("The emoji didn't match"), findsOneWidget);
  });

  testWidgets("the emoji fit a narrow phone", (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MatrixVerificationPageView(
          state: KeyVerificationState.askSas,
          sasTypes: const ["emoji", "decimal"],
          sasNumbers: const [4127, 938, 6605],
          sasEmoji: [
            for (final n in [0, 13, 31, 36, 46, 59, 23]) KeyVerificationEmoji(n)
          ],
          userID: "@me:example.org",
          ownUser: true,
          otherName: "Pixel 8",
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text("Compare emoji"), findsOneWidget);
  });
}
