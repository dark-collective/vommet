// Vommet issue 72: signing out warns first on the account's last device
// with its message keys, and offers to keep them.
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/settings/categories/account/account_management/sign_out_check.dart';
import 'package:commet/ui/pages/settings/categories/account/account_management/sign_out_dialog.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group("SignOutCheck.decide", () {
    final now = DateTime(2026, 10, 26, 12);
    SignOutSession session(String id,
            {Duration? ago, bool verified = true, String? name}) =>
        SignOutSession(
            deviceId: id,
            displayName: name,
            lastSeen: ago == null ? null : now.subtract(ago),
            verified: verified);

    test("no encryption: a plain confirmation", () {
      final a = SignOutCheck.decide(
          encryption: false, others: [], backupRecoverable: false, now: now);
      expect(a.kind, SignOutCase.plain);
    });

    test("a verified session seen recently keeps the keys; the latest wins",
        () {
      final a = SignOutCheck.decide(
          encryption: true,
          others: [
            session("OLD", ago: const Duration(days: 3)),
            session("NEW", ago: const Duration(hours: 2)),
            session("UNVERIFIED", ago: Duration.zero, verified: false),
          ],
          backupRecoverable: false,
          now: now);
      expect(a.kind, SignOutCase.otherSession);
      expect(a.keeper!.deviceId, "NEW");
    });

    test("unverified, unseen or long-unused sessions don't count", () {
      for (final backup in [false, true]) {
        final a = SignOutCheck.decide(
            encryption: true,
            others: [
              session("UNVERIFIED", ago: Duration.zero, verified: false),
              session("NEVER"),
              session("STALE", ago: const Duration(days: 15)),
            ],
            backupRecoverable: backup,
            now: now);
        expect(
            a.kind,
            backup
                ? SignOutCase.lastDeviceBackedUp
                : SignOutCase.lastDeviceNoBackup);
      }
    });

    test("sessions that couldn't be loaded count as the last device", () {
      final a = SignOutCheck.decide(
          encryption: true, others: null, backupRecoverable: false, now: now);
      expect(a.kind, SignOutCase.lastDeviceNoBackup);
    });
  });

  group("SignOutDialog", () {
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

    Future<MatrixClient> client(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final database = await MatrixSdkDriftDatabase.init(
              NativeDatabase.memory(), "sign-out-dialog");
          return MatrixClient(identifier: "sign-out", database: database);
        }))!;

    /// Opens the dialog; the returned list gets its result once it closes.
    Future<List<bool?>> open(WidgetTester tester, SignOutCase kind,
        {SignOutSession? keeper,
        Future<bool> Function(String)? checkKey,
        Future<bool> Function(BuildContext)? saveKeyFile}) async {
      // Tall enough for the whole last-device warning.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await client(tester);
      final results = <bool?>[];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(await showDialog<bool>(
                    context: context,
                    builder: (_) => Dialog(
                          child: SingleChildScrollView(
                            child: SignOutDialog(c,
                                load: () async =>
                                    SignOutAssessment(kind, keeper: keeper),
                                checkKey: checkKey ?? (_) async => false,
                                saveKeyFile: saveKeyFile ?? (_) async => false,
                                setUpBackup: (_) async {},
                                method: RecoveryMethod.key),
                          ),
                        )));
              },
              child: const Text("open"),
            ),
          ),
        ),
      ));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
      return results;
    }

    Future<void> tapConfirm(WidgetTester tester) async {
      await tester.tap(find.byKey(SignOutDialog.confirmKey),
          warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    testWidgets("another session: a plain confirmation naming it",
        (tester) async {
      final results = await open(tester, SignOutCase.otherSession,
          keeper: SignOutSession(
              deviceId: "LAPTOP",
              displayName: "Vommet on Linux laptop",
              lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
              verified: true));
      expect(find.text("Vommet on Linux laptop"), findsOneWidget);
      expect(find.text(signOutLastDeviceTitle), findsNothing);
      await tapConfirm(tester);
      expect(results, [true]);
    });

    testWidgets("last device, no backup: Sign out anyway needs the tick box",
        (tester) async {
      final results = await open(tester, SignOutCase.lastDeviceNoBackup);
      expect(find.text(signOutLastDeviceTitle), findsOneWidget);
      expect(find.text(signOutAnyway), findsOneWidget);

      await tapConfirm(tester);
      expect(results, isEmpty, reason: "not ticked yet: stays open");

      await tester.tap(find.text(signOutUnderstood));
      await tester.pumpAndSettle();
      await tapConfirm(tester);
      expect(results, [true]);
    });

    testWidgets("last device, no backup: a saved key file allows sign-out",
        (tester) async {
      final results = await open(tester, SignOutCase.lastDeviceNoBackup,
          saveKeyFile: (_) async => true);
      await tester.tap(find.text(signOutSaveKeyFile));
      await tester.pumpAndSettle();

      expect(find.text(signOutKeysSavedTitle), findsOneWidget);
      expect(find.text(signOutUnderstood), findsNothing);
      expect(find.text(signOutConfirm), findsOneWidget);
      await tapConfirm(tester);
      expect(results, [true]);
    });

    testWidgets("last device with backup: the recovery key is checked first",
        (tester) async {
      final results = await open(tester, SignOutCase.lastDeviceBackedUp,
          checkKey: (key) async => key == "right key");
      expect(find.text(signOutKeyLabelKey), findsOneWidget);

      await tester.enterText(find.byType(TextField), "old key");
      await tester.tap(find.text(signOutCheckKey));
      await tester.pumpAndSettle();
      await tapConfirm(tester);
      expect(results, isEmpty, reason: "a wrong key doesn't unlock sign-out");

      await tester.enterText(find.byType(TextField), "right key");
      await tester.tap(find.text(signOutCheckKey));
      await tester.pumpAndSettle();
      expect(find.text(signOutKeyPassed), findsOneWidget);
      await tapConfirm(tester);
      expect(results, [true]);
    });

    testWidgets("last device with backup: skipping the check needs the tick",
        (tester) async {
      final results = await open(tester, SignOutCase.lastDeviceBackedUp);
      await tester.tap(find.text(signOutWithoutChecking));
      await tester.pumpAndSettle();
      expect(find.text(signOutAnyway), findsOneWidget);

      await tapConfirm(tester);
      expect(results, isEmpty);
      await tester.tap(find.text(signOutUnderstood));
      await tester.pumpAndSettle();
      await tapConfirm(tester);
      expect(results, [true]);
    });

    testWidgets("Cancel keeps the account", (tester) async {
      final results = await open(tester, SignOutCase.lastDeviceNoBackup);
      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });
  });
}
