import 'dart:io';

import 'package:commet/config/app_config.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:commet/ui/pages/login/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
import 'package:path_provider/path_provider.dart';
import 'package:commet/client/matrix/matrix_client.dart' show MatrixClient;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, OpenDatabaseOptions;

import 'wait_for.dart';

extension CommonFlows on WidgetTester {
  String get homeserver =>
      const String.fromEnvironment('HOMESERVER', defaultValue: "localhost");
  String get username =>
      const String.fromEnvironment('USER1_NAME', defaultValue: "alice");
  String get password => const String.fromEnvironment('USER1_PW',
      defaultValue: "AliceInWonderland");

  String get userTwoName =>
      const String.fromEnvironment('USER2_NAME', defaultValue: "bob");
  String get userTwoPassword =>
      const String.fromEnvironment('USER2_PW', defaultValue: "CanWeFixIt");

  Future<void> clearUserData() async {
    var dir = Directory(await AppConfig.getDatabasePath());
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    dir = await getApplicationSupportDirectory();

    if (!await dir.exists()) return;

    var files = await dir.list(recursive: true).toList();
    for (var file in files) {
      try {
        if (!await file.exists()) continue;

        await file.delete();
      } catch (exception) {
        // ignore: avoid_print
        print("Could not delete file: ${file.uri.toString()}");
      }
    }
  }

  Future<void> clean() async {
    await fileCache?.close();
    await preferences.clear();
    await clearUserData();
  }

  Future<App> setupApp() async {
    await clearUserData();
    await initNecessary();
    await initGuiRequirements();
    // Vommet: clean up even when the test fails, so one failure doesn't leave
    // the next test logged in (clean() is idempotent).
    addTearDown(() async {
      await clientManager?.close();
      await clean();
    });
    return App(clientManager: clientManager!);
  }

  Future<void> login(App app) async {
    await waitFor(() => find.byType(LoginPage).evaluate().isNotEmpty);

    var button = find.widgetWithText(ElevatedButton, "Login");

    var inputs = find.byType(TextField);
    expect(inputs, findsWidgets);

    // Build our app and trigger a frame.

    await enterText(inputs.at(0), homeserver);
    await pumpAndSettle();
    await enterText(inputs.at(1), username);
    await pumpAndSettle();
    await enterText(inputs.at(2), password);
    await pumpAndSettle();

    await tap(button);

    await pumpAndSettle();

    await waitFor(() => app.clientManager.isLoggedIn(),
        timeout: const Duration(seconds: 5), skipPumpAndSettle: true);
    expect(app.clientManager.isLoggedIn(), equals(true));
  }

  Future<void> loginUser2(App app) async {
    await waitFor(() => find.byType(LoginPage).evaluate().isNotEmpty);
    var button = find.widgetWithText(ElevatedButton, "Login");

    var inputs = find.byType(TextField);
    expect(inputs, findsWidgets);

    await enterText(inputs.at(0), homeserver);
    await pumpAndSettle();
    await enterText(inputs.at(1), userTwoName);
    await pumpAndSettle();
    await enterText(inputs.at(2), userTwoPassword);
    await pumpAndSettle();

    await tap(button);

    await pumpAndSettle();

    await waitFor(() => app.clientManager.isLoggedIn(),
        timeout: const Duration(seconds: 5), skipPumpAndSettle: true);
    expect(app.clientManager.isLoggedIn(), equals(true));
  }

  /// A second, independent Matrix client in this process (an "other
  /// device"), with end-to-end encryption and its own in-memory database, so
  /// it survives the app's restarts and never touches the app's data.
  Future<Client> createTestClient({
    String? user,
    String? password,
    String deviceName = "Integration test device",
    String? server,
  }) async {
    var name = "it-${DateTime.now().microsecondsSinceEpoch}";
    var otherClient = Client(
      name,
      verificationMethods: {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers
      },
      nativeImplementations: MatrixClient.nativeImplementations,
      logLevel: Level.info,
      database: await MatrixSdkDatabase.init(
        name,
        database: await databaseFactoryFfi.openDatabase(':memory:',
            options: OpenDatabaseOptions(singleInstance: false)),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );

    var u = user ?? username;
    var pw = password ?? this.password;
    // Cross-signing uploads need the account password (user-interactive
    // auth); answer it like a user typing it in.
    otherClient.onUiaRequest.stream.listen((uia) {
      if (uia.state == UiaRequestState.waitForUser) {
        uia.completeStage(AuthenticationPassword(
          session: uia.session,
          password: pw,
          identifier: AuthenticationUserIdentifier(user: u),
        ));
      }
    });

    // An explicit server is used as is (no .well-known redirection).
    await otherClient.checkHomeserver(Uri.https(server ?? homeserver),
        checkWellKnown: server == null);
    await otherClient.login(LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: u),
        password: pw,
        initialDeviceDisplayName: deviceName);

    return otherClient;
  }

  /// Like quitting and relaunching the app: the clients are disposed and
  /// everything is loaded again from the same on-disk data (unlike
  /// [setupApp], which wipes it first).
  Future<App> restartApp() async {
    var old = clientManager;
    if (old != null) {
      for (var c in old.clients.toList()) {
        await c.close();
      }
    }
    await initNecessary();
    await initGuiRequirements();
    return App(clientManager: clientManager!);
  }

  Future<void> openSettings(App app) async {
    await dragUntilVisible(find.byKey(SideNavigationBar.settingsKey),
        find.byType(SideNavigationBar), const Offset(0, 20));

    await tap(find.byKey(SideNavigationBar.settingsKey));

    await pumpAndSettle();
  }
}
