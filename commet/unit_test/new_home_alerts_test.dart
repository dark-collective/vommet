// Vommet: New Home has no Alerts panel, so the app's alerts show as banners
// atop its main area (option A of the encryption mockups): the encryption
// offer with Set up, and closing it answers Not now.
import 'package:commet/client/alert.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/main.dart';
import 'package:commet/security/local_data_keys.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/security/local_data_strings.dart';
import 'package:commet/ui/organisms/new_home/new_home_alerts.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:commet/ui/pages/local_data/local_data_notices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ClientManager manager;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    LocalDataSetting.debugOverride = LocalDataSetting.byDefault;
    manager = ClientManager();
    clientManager = manager;
  });

  tearDown(() {
    LocalDataSetting.debugOverride = null;
    clientManager = null;
  });

  testWidgets(
      "New Home shows the encryption offer as a banner; closing it answers "
      "Not now", (tester) async {
    preferences.addRegisteredMatrixClient("account-a");
    LocalDataNotices.add(manager);
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: NewHomeMain(home: const SizedBox(), phone: false))));
    await tester.pump();
    expect(find.byType(NewHomeAlerts), findsOneWidget);
    expect(find.text(localDataOfferEncryptTitle), findsOneWidget);
    expect(find.widgetWithText(FilledButton, localDataOfferEncryptAction),
        findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(NewHomeAlerts), matching: find.byIcon(Icons.close)));
    await tester.pump();
    expect(find.text(localDataOfferEncryptTitle), findsNothing);
    expect(LocalDataKeys.chosen, isTrue);
    expect(LocalDataKeys.encrypt, isFalse);
    expect(
        LocalDataSetting.debugOverride,
        const LocalDataSetting(
            encrypt: false, chosen: true, source: "notice", offer: 2));
  });

  testWidgets(
      "every app alert shows, and one closed is hidden for the session in "
      "every layout", (tester) async {
    final alert = Alert(AlertType.warning,
        titleGetter: () => "Signed out", messageGetter: () => "Sign in again");
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NewHomeAlerts(manager: manager.alertManager))));
    expect(find.text("Signed out"), findsNothing);
    manager.alertManager.addAlert(alert);
    await tester.pump();
    expect(find.text("Signed out"), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text("Signed out"), findsNothing);
    // Still in the manager; hidden in the unified list too.
    expect(manager.alertManager.alerts, contains(alert));
    expect(UnifiedChatSource.visibleAlerts(manager.alertManager),
        isNot(contains(alert)));
  });
}
