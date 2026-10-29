// Vommet issue 321: Manage Accounts says why an account failed to load, and
// its Sign out button takes it off the list.
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/error_profile.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/account/account_management/account_management_tab.dart';
import 'package:commet/ui/pages/settings/categories/account/account_management/sign_out_dialog.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // MatrixClient's calls component listens for WebRTC events
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(const EventChannel("FlutterWebRTC.Event"),
            MockStreamHandler.inline(onListen: (_, __) {}));
  });

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  Future<(ClientManager, MatrixClient)> failedAccount(
      WidgetTester tester, String reason) async {
    return (await tester.runAsync(() async {
      final manager = ClientManager();
      final database = await MatrixSdkDriftDatabase.init(
          NativeDatabase.memory(), "failed-account");
      final client =
          MatrixClient(identifier: "failed-account", database: database);
      client.self = ErrorProfile(reason: reason);
      manager.addClient(client);
      await pumpEventQueue();
      return (manager, client);
    }))!;
  }

  Widget view(ClientManager manager) => MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: Provider<ClientManager>.value(
            value: manager,
            child: AccountManagementSettingsTab(clientManager: manager),
          ),
        ),
      );

  testWidgets("the Error account shows why it failed to load", (tester) async {
    final (manager, _) =
        await failedAccount(tester, "Exception: database is locked");
    await tester.pumpWidget(view(manager));

    expect(find.text("Error"), findsOneWidget);
    expect(
        find.text("Couldn't load this account: Exception: database is locked"),
        findsOneWidget);
  });

  testWidgets("a long reason fits next to Sign out on a phone", (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (manager, _) = await failedAccount(
        tester, "Exception: ${"the account could not be loaded " * 6}");
    await tester.pumpWidget(view(manager));

    expect(tester.takeException(), isNull);
    expect(find.text("Sign out"), findsOneWidget);
  });

  testWidgets("Sign out takes the Error account off the list", (tester) async {
    final (manager, _) =
        await failedAccount(tester, "Exception: database is locked");
    await tester.pumpWidget(view(manager));

    await tester.tap(find.text("Sign out"));
    await tester.runAsync(() => pumpEventQueue(times: 50));
    await tester.pumpAndSettle();
    // Not signed in: no keys to lose, a plain confirmation (Vommet issue 72).
    await tester.tap(find.byKey(SignOutDialog.confirmKey));
    await tester.runAsync(() => pumpEventQueue(times: 50));
    await tester.pumpAndSettle();

    expect(manager.clients, isEmpty);
    expect(find.text("Sign out"), findsNothing);
  });
}
