// Vommet local data encryption (phase 6; on by default since 10-30):
// existing users who never answered are offered it in a notice that shows
// in the Home Alerts panel (Discord layout) and as a banner above the chat
// list (Telegram and Custom mix), Encrypt recommended. Its close button and
// Not now answer "Not now" for good; a "Not now" to the opt-in question is
// asked once more, one from the settings switch never.
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
    .where((a) => a.title == localDataOfferEncryptTitle)
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
      "the offer shows Encrypt as the main button and Not now; closing it "
      "answers Not now", (tester) async {
    preferences.addRegisteredMatrixClient("account-a");
    expect(LocalDataKeys.chosen, isFalse);
    LocalDataNotices.add(manager);
    final offer = _offers(manager).single;
    expect(offer.message, localDataOfferEncryptBody);
    expect(offer.message, startsWith("Recommended."));
    expect(offer.actionLabel?.call(), localDataOfferEncryptAction);
    expect(offer.actionIsPrimary, isTrue);
    expect(offer.secondaryActionLabel?.call(), localDataOfferNotNow);

    // Home Alerts panel (Discord layout): its own close button.
    await tester.pumpWidget(_app(AlertView(offer)));
    expect(find.text(localDataOfferEncryptTitle), findsOneWidget);
    expect(find.widgetWithText(FilledButton, localDataOfferEncryptAction),
        findsOneWidget);
    expect(
        find.widgetWithText(TextButton, localDataOfferNotNow), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Banner above the chat list (Telegram and Custom mix): one close
    // button, the banner's, which still answers for the alert.
    var bannerClosed = false;
    await tester.pumpWidget(
        _app(AlertBanner(offer, onDismiss: () => bannerClosed = true)));
    expect(find.text(localDataOfferEncryptTitle), findsOneWidget);
    expect(find.widgetWithText(FilledButton, localDataOfferEncryptAction),
        findsOneWidget);
    expect(
        find.widgetWithText(TextButton, localDataOfferNotNow), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(bannerClosed, isTrue);
    expect(_offers(manager), isEmpty);
    expect(LocalDataKeys.chosen, isTrue);
    expect(LocalDataKeys.encrypt, isFalse);
    expect(
        LocalDataSetting.debugOverride,
        const LocalDataSetting(
            encrypt: false, chosen: true, source: "notice", offer: 2));

    // Answered: not offered again.
    final next = ClientManager();
    LocalDataNotices.add(next);
    expect(_offers(next), isEmpty);
  });

  testWidgets("Encrypt on the offer turns it on from the next start",
      (tester) async {
    preferences.addRegisteredMatrixClient("account-a");
    LocalDataNotices.add(manager);
    final offer = _offers(manager).single;
    await tester.pumpWidget(_app(AlertView(offer)));
    await tester
        .tap(find.widgetWithText(FilledButton, localDataOfferEncryptAction));
    await tester.pump();
    await tester.pump();
    expect(_offers(manager), isEmpty);
    expect(
        LocalDataSetting.debugOverride,
        const LocalDataSetting(
            encrypt: true, chosen: true, source: "notice", offer: 2));
    expect(find.text(localDataOfferEncryptDone), findsOneWidget);

    final next = ClientManager();
    LocalDataNotices.add(next);
    expect(_offers(next), isEmpty);
  });

  testWidgets("Not now on the offer answers it for good", (tester) async {
    preferences.addRegisteredMatrixClient("account-a");
    LocalDataNotices.add(manager);
    final offer = _offers(manager).single;
    await tester.pumpWidget(_app(AlertBanner(offer)));
    await tester.tap(find.widgetWithText(TextButton, localDataOfferNotNow));
    await tester.pump();
    expect(_offers(manager), isEmpty);
    expect(
        LocalDataSetting.debugOverride,
        const LocalDataSetting(
            encrypt: false, chosen: true, source: "notice", offer: 2));
  });

  group("asked once more after the opt-in question", () {
    // What builds before 10-30 wrote: no "offer" (generation 1), and from
    // before the source was kept, no "source" either.
    for (final (name, source) in [
      ("the first-run page", "first_run"),
      ("the notice", "notice"),
      ("a build that didn't record where", null),
    ]) {
      testWidgets("Not now from $name is asked again, then never",
          (tester) async {
        preferences.addRegisteredMatrixClient("account-a");
        LocalDataSetting.debugOverride = LocalDataSetting(
            encrypt: false, chosen: true, source: source, offer: 1);
        LocalDataNotices.add(manager);
        final offer = _offers(manager).single;
        offer.onDismiss!();
        expect(
            LocalDataSetting.debugOverride,
            const LocalDataSetting(
                encrypt: false, chosen: true, source: "notice", offer: 2));

        // No third ask.
        final next = ClientManager();
        LocalDataNotices.add(next);
        expect(_offers(next), isEmpty);
      });
    }

    testWidgets("turned off in Settings: not asked again", (tester) async {
      preferences.addRegisteredMatrixClient("account-a");
      LocalDataSetting.debugOverride = const LocalDataSetting(
          encrypt: false, chosen: true, source: "settings", offer: 1);
      LocalDataNotices.add(manager);
      expect(_offers(manager), isEmpty);
    });

    testWidgets("turned off in Settings since: not asked", (tester) async {
      preferences.addRegisteredMatrixClient("account-a");
      LocalDataSetting.debugOverride = const LocalDataSetting(
          encrypt: false, chosen: true, source: "settings");
      LocalDataNotices.add(manager);
      expect(_offers(manager), isEmpty);
    });

    testWidgets("Not now to the current question: not asked", (tester) async {
      preferences.addRegisteredMatrixClient("account-a");
      LocalDataSetting.debugOverride = const LocalDataSetting(
          encrypt: false, chosen: true, source: "first_run");
      LocalDataNotices.add(manager);
      expect(_offers(manager), isEmpty);
    });

    testWidgets("encrypted (chosen or not): never asked", (tester) async {
      preferences.addRegisteredMatrixClient("account-a");
      for (final setting in const [
        LocalDataSetting(encrypt: true, chosen: true, offer: 1),
        LocalDataSetting(encrypt: true, chosen: false),
        LocalDataSetting.newInstall,
      ]) {
        LocalDataSetting.debugOverride = setting;
        final m = ClientManager();
        LocalDataNotices.add(m);
        expect(_offers(m), isEmpty, reason: "$setting");
      }
    });
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
