import 'package:commet/config/global_config.dart';
import 'package:commet/ui/pages/login/login_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 305: the login form offers password manager autofill.
void main() {
  setUp(() => GlobalConfig.data = {});

  Widget form({bool hasPasswordSupport = true}) => MaterialApp(
        home: LoginPageView(
            isLoggingIn: false, hasPasswordSupport: hasPasswordSupport),
      );

  TextField field(WidgetTester tester, int index) =>
      tester.widgetList<TextField>(find.byType(TextField)).elementAt(index);

  testWidgets("username and password fields carry autofill hints",
      (tester) async {
    await tester.pumpWidget(form());

    // homeserver, username, password
    expect(find.byType(TextField), findsNWidgets(3));
    expect(field(tester, 0).autofillHints, isEmpty);
    expect(field(tester, 1).autofillHints, [AutofillHints.username]);
    expect(field(tester, 2).autofillHints, [AutofillHints.password]);
  });

  testWidgets("both fields share one autofill group", (tester) async {
    await tester.pumpWidget(form());

    final group = find.byType(AutofillGroup);
    expect(group, findsOneWidget);
    for (final i in [1, 2]) {
      expect(
          find.ancestor(of: find.byWidget(field(tester, i)), matching: group),
          findsOneWidget);
    }
    expect(find.ancestor(of: find.byWidget(field(tester, 0)), matching: group),
        findsNothing);
  });

  testWidgets("leaving the form without signing in doesn't offer to save",
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, null));

    await tester.pumpWidget(form());
    await tester.enterText(find.byType(TextField).at(1), "alice");
    await tester.enterText(find.byType(TextField).at(2), "hunter2");

    // e.g. the server stops offering password login, or the page closes
    await tester.pumpWidget(form(hasPasswordSupport: false));
    expect(find.byType(AutofillGroup), findsNothing);

    final finishes =
        calls.where((c) => c.method == "TextInput.finishAutofillContext");
    expect(finishes, isNotEmpty);
    expect(finishes.every((c) => c.arguments == false), isTrue);
  });
}
