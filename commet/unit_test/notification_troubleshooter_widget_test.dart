import 'dart:async';

import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/notification_troubleshooter.dart';
import 'package:commet/utils/notification_diagnostics/diagnostic_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'helpers/notification_diagnostic_fixtures.dart';

NotificationDiagnosticReader reader() => FixtureReader([
      DiagnosticCheck(
          'System permission',
          () async => [
                const DiagnosticResult('System permission',
                    DiagnosticStatus.passed, 'Android allows notifications.')
              ]),
      DiagnosticCheck(
          'Channels',
          () async => [
                const DiagnosticResult('Mentions', DiagnosticStatus.failed,
                    'This category is blocked.',
                    action: DiagnosticAction.androidSettings)
              ]),
      DiagnosticCheck(
          'Provider',
          () async => [
                const DiagnosticResult('Provider', DiagnosticStatus.unknown,
                    'Provider cannot be verified.')
              ]),
    ]);

Future<void> pumpDiagnostic(WidgetTester tester,
    {NotificationDiagnosticReader Function()? create,
    Future<bool> Function(DiagnosticAction)? action,
    double width = 390,
    double scale = 1}) async {
  tester.view.physicalSize = Size(width, 820);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 820), textScaler: TextScaler.linear(scale)),
          child: NotificationDiagnosticView(
              createReader: create ?? reader,
              onAction: action ?? (_) async => true))));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    // unit_test/ is the repository’s Flutter test directory.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  testWidgets('Account selector grows at large text and still changes accounts',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? selected;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(360, 900), textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DiagnosticAccountPicker<String>(
                        accounts: const {
                          'Personal': ('Personal', '@Personal:example.invalid'),
                          'Work': ('Work', '@Work:example.invalid')
                        },
                        value: 'Personal',
                        onChanged: (account) => selected = account))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('@Personal:example.invalid'), findsOneWidget);
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    expect(selected, 'Work');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Every style and split/unified mode uses the same accessible shared page',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final style in LayoutStyle.values) {
      await pickLayoutStyle(style);
      for (final unified in [false, true]) {
        await experimentUnifiedChatList.set(unified);
        for (final width in [360.0, 1200.0]) {
          await pumpDiagnostic(tester, width: width, scale: 1.8);
          expect(
              find.text(NotificationTroubleshooterPage.title), findsOneWidget);
          expect(find.textContaining('Passed ·'), findsOneWidget);
          expect(find.textContaining('Failed ·'), findsOneWidget);
          expect(find.textContaining('Unknown ·'), findsOneWidget);
          expect(find.textContaining('Not available ·'), findsOneWidget);
          expect(find.text('Send test notification'), findsNothing);
          expect(find.text('Copy report'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
  });

  testWidgets(
      'Settings actions only run after a tap and invalidate old success',
      (tester) async {
    addTearDown(tester.view.reset);
    final actions = <DiagnosticAction>[];
    await pumpDiagnostic(tester, action: (a) async {
      actions.add(a);
      return true;
    });
    expect(actions, isEmpty);
    await tester.ensureVisible(find.text('Open Android app settings'));
    await tester.tap(find.text('Open Android app settings'));
    await tester.pumpAndSettle();
    expect(actions, [DiagnosticAction.androidSettings]);
    expect(find.textContaining('Passed ·'), findsNothing);
    expect(
        find.textContaining('Check again for current results'), findsOneWidget);
    await tester.ensureVisible(find.text('Check again'));
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Passed ·'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Replacing account and disposing a page ignore in-flight results',
      (tester) async {
    addTearDown(tester.view.reset);
    final pending = Completer<List<DiagnosticResult>>();
    await pumpDiagnostic(tester,
        create: () => FixtureReader(
            [DiagnosticCheck('Account one', () => pending.future)]));
    await tester.pumpWidget(const SizedBox());
    await pumpDiagnostic(tester);
    pending.complete([
      const DiagnosticResult(
          'Account one', DiagnosticStatus.failed, 'stale account')
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('stale account'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
