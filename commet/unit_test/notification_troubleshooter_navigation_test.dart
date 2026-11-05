import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/notification_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/notification_troubleshooter.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Manager extends Fake implements ClientManager {
  _Manager(List<Client> accounts) : clients = NotifyingList.from(accounts);
  @override
  final NotifyingList<Client> clients;
}

class _Sdk extends Fake implements matrix.Client {
  _Sdk(this.deviceID);
  @override
  final String deviceID;
}

class _Account extends Fake implements MatrixClient {
  _Account(this.identifier) : sdk = _Sdk(identifier);
  @override
  final String identifier;
  final _Sdk sdk;
  int environmentReads = 0;
  @override
  Profile? get self => null;
  @override
  matrix.Client getMatrixClient() {
    environmentReads++;
    return sdk;
  }
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

Future<void> _pumpSettings(
    WidgetTester tester, double width, _Routes routes) async {
  tester.view.physicalSize = Size(width, 820);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      navigatorObservers: [routes],
      home: const Scaffold(
          body: SingleChildScrollView(child: NotificationSettingsPage()))));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  final entry = find.byType(NotificationTroubleshooterEntry);
  expect(entry, findsOneWidget);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.byType(NotificationTroubleshooterPage), findsOneWidget);
  expect(find.text('System permission'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    final previous = clientManager;
    clientManager = _Manager([]);
    addTearDown(() => clientManager = previous);
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets(
        'Notifications settings opens the real troubleshooter at $width',
        (tester) async {
      addTearDown(tester.view.reset);
      await _pumpSettings(tester, width, _Routes());
      await _open(tester);
      expect(find.byType(DiagnosticAccountPicker<Client>), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Provider action returns to existing settings at $width',
        (tester) async {
      addTearDown(tester.view.reset);
      final routes = _Routes();
      await _pumpSettings(tester, width, routes);
      await _open(tester);
      final pushes = routes.pushes;
      final action =
          find.widgetWithText(OutlinedButton, 'Notification settings');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationTroubleshooterPage), findsNothing);
      expect(find.byType(NotificationSettingsPage), findsOneWidget);
      expect(find.byType(NotificationTroubleshooterEntry), findsOneWidget);
      expect(routes.pushes, pushes);
      expect(routes.pops, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'Real page defaults to current account and rechecks on switch at $width',
        (tester) async {
      addTearDown(tester.view.reset);
      final personal = _Account('Personal');
      final work = _Account('Work');
      clientManager = _Manager([personal, work]);
      await preferences.filterClient.set(work.identifier);
      tester.view.physicalSize = Size(width, 820);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: const NotificationTroubleshooterPage()));
      await tester.pumpAndSettle();
      final picker = find.byType(DiagnosticAccountPicker<Client>);
      expect(picker, findsOneWidget);
      expect(tester.widget<DiagnosticAccountPicker<Client>>(picker).value,
          same(work));
      expect(work.environmentReads, greaterThan(0));
      expect(personal.environmentReads, 0);
      expect(find.text('Notification provider'), findsOneWidget);
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal').last);
      await tester.pumpAndSettle();
      expect(tester.widget<DiagnosticAccountPicker<Client>>(picker).value,
          same(personal));
      expect(personal.environmentReads, greaterThan(0));
      expect(find.text('Notification provider'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
