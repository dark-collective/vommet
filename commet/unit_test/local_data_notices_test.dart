// Vommet local data encryption (phase 6): existing users are offered it
// once, in a notice that shows in the Home Alerts panel (Discord layout)
// and as a banner above the chat list (Telegram and Custom mix). Its close
// button answers "Not now" for good; its button opens the settings.
import 'package:commet/client/alert.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/main.dart';
import 'package:commet/security/local_data_keys.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/security/local_data_strings.dart';
import 'package:commet/ui/molecules/alert_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/ui/pages/local_data/local_data_notices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: child)));

List<Alert> _offers(ClientManager manager) => manager.alertManager.alerts
    .where((a) => a.title == localDataOfferTitle)
    .toList();

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

  testWidgets("no offer on a device without accounts (a new install)",
      (tester) async {
    LocalDataNotices.add(manager);
    expect(_offers(manager), isEmpty);
  });

  testWidgets(
      "the offer shows once with Set up and a close button; closing it "
      "answers Not now", (tester) async {
    preferences.addRegisteredMatrixClient("account-a");
    expect(LocalDataKeys.chosen, isFalse);
    LocalDataNotices.add(manager);
    final offer = _offers(manager).single;
    expect(offer.message, localDataOfferBody);
    expect(offer.actionLabel?.call(), localDataOfferAction);
    expect(offer.action, isNotNull);

    // Home Alerts panel (Discord layout): its own close button.
    await tester.pumpWidget(_app(AlertView(offer)));
    expect(find.text(localDataOfferTitle), findsOneWidget);
    expect(
        find.widgetWithText(TextButton, localDataOfferAction), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Banner above the chat list (Telegram and Custom mix): one close
    // button, the banner's, which still answers for the alert.
    var bannerClosed = false;
    await tester.pumpWidget(
        _app(AlertBanner(offer, onDismiss: () => bannerClosed = true)));
    expect(find.text(localDataOfferTitle), findsOneWidget);
    expect(
        find.widgetWithText(TextButton, localDataOfferAction), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(bannerClosed, isTrue);
    expect(_offers(manager), isEmpty);
    expect(LocalDataKeys.chosen, isTrue);
    expect(LocalDataKeys.encrypt, isFalse);
    expect(LocalDataSetting.debugOverride,
        const LocalDataSetting(encrypt: false, chosen: true));

    // Answered: not offered again.
    final next = ClientManager();
    LocalDataNotices.add(next);
    expect(_offers(next), isEmpty);
  });

  test("the key-file explanation claims no erase on sign-out", () {
    // With the key in a file next to the data, signing out deletes files;
    // it doesn't make a copy someone already has unreadable.
    final text = localDataKeyFileDialogFile.toLowerCase();
    expect(text, isNot(contains("erase")));
    expect(text, isNot(contains("for good")));
    expect(text, contains("open the key too"));
  });
}
