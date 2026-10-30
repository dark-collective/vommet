// Vommet: local data encryption (review 1): Start over and Reset ask with a
// "Keep a copy" box that is on by default (the old data stays, with what it
// takes to open it again) and say that the recovery key brings the
// messages back. Turning encryption off doesn't claim the key leaves the
// keyring (it stays: media and kept copies still need it).
import 'package:commet/security/local_data_strings.dart';
import 'package:commet/ui/pages/local_data/local_data_startup_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool?> confirm(WidgetTester tester, {required bool untick}) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<bool>(
                context: context,
                builder: (_) => const RemoveLocalDataDialog(
                    title: "Remove?", body: "Body", confirm: "Remove"));
          },
          child: const Text("open"),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    expect(find.text(localDataRecoveryKeyLine), findsOneWidget);
    final box = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(box.value, isTrue);
    if (untick) {
      await tester.tap(find.text(localDataKeepCopy));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text("Remove"));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets("Keep a copy is on by default", (tester) async {
    expect(await confirm(tester, untick: false), isTrue);
  });

  testWidgets("unticked, the old data isn't kept", (tester) async {
    expect(await confirm(tester, untick: true), isFalse);
  });

  testWidgets("Cancel removes nothing", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => const RemoveLocalDataDialog(
                  title: "Remove?", body: "Body", confirm: "Remove")),
          child: const Text("open"),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    await tester.tap(find.text(localDataCancel));
    await tester.pumpAndSettle();
    expect(find.byType(RemoveLocalDataDialog), findsNothing);
  });

  test("turning encryption off doesn't claim the key leaves the keyring", () {
    expect(localDataConfirmOffBody.toLowerCase(), isNot(contains("keyring")));
  });
}
