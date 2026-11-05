import 'dart:async';

import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/matrix/components/push_notifications/pusher_housekeeping.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/notification_troubleshooter.dart';
import 'package:commet/utils/notification_diagnostics/diagnostic_check.dart';
import 'package:commet/utils/notification_diagnostics/notification_diagnostic_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'helpers/notification_diagnostic_fixtures.dart';

class _SdkClient extends Fake implements matrix.Client {
  @override
  String get deviceID => 'fixture-device';
}

class _Account extends Fake implements MatrixClient {
  @override
  String get identifier => 'fixture-account';

  @override
  matrix.Client getMatrixClient() => _SdkClient();
}

const _fixtureKey = 'fixture-registration-key';

Future<UnifiedPushNotifier> _unifiedPush() async {
  await preferences.unifiedPushEnabled.set(true);
  await preferences.unifiedPushEndpoint.set(_fixtureKey);
  final notifier = UnifiedPushNotifier();
  addTearDown(notifier.onEndpointChanged.close);
  return notifier;
}

DiagnosticEnvironment _androidEnvironment(
    _Account account, UnifiedPushNotifier notifier) {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    return DiagnosticEnvironment.current(account, notifier: notifier);
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

// Mirror the registration contract of updatePushers: default gateway,
// event_id_only, the app's HTTP pusher ID, and device/account routing tags.
matrix.Pusher _registeredPusher(_Account account) => matrix.Pusher(
    appId: 'chat.commet.commetapp.android',
    pushkey: _fixtureKey,
    kind: 'http',
    lang: 'en',
    appDisplayName: 'Vommet',
    deviceDisplayName: 'Fixture device',
    data: matrix.PusherData(
        format: 'event_id_only',
        url: Uri.https(preferences.pushGateway, '/_matrix/push/v1/notify'),
        additionalProperties: {
          'local_client_id': account.identifier,
          PusherHousekeeping.deviceIdKey: account.getMatrixClient().deviceID,
        }));

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

  test('Current UnifiedPush settings match a production-shaped pusher',
      () async {
    final account = _Account();
    final notifier = await _unifiedPush();
    final environment = _androidEnvironment(account, notifier);
    expect(environment.provider, DiagnosticProvider.unifiedPush);
    expect(
        environment.channels.keys,
        unorderedEquals(
            ['messages', 'chat_invites', 'incoming_calls_channel_1']));
    final reader = AppNotificationDiagnosticReader(
        environment: environment,
        currentEnvironment: () => _androidEnvironment(account, notifier),
        reads: FixtureReads(),
        readPushers: () async => [_registeredPusher(account)]);
    expect((await reader.provider()).single.status, DiagnosticStatus.passed);
    expect(
        (await reader.registration()).single.status, DiagnosticStatus.passed);
  });

  testWidgets('Real reader renders configuration and delivery at both widths',
      (tester) async {
    addTearDown(tester.view.reset);
    final account = _Account();
    final notifier = await _unifiedPush();
    DiagnosticEnvironment current() => _androidEnvironment(account, notifier);
    final reads = FixtureReads()
      ..found = [
        const AndroidNotificationChannel('messages', 'Messages',
            importance: Importance.none)
      ];
    for (final width in [360.0, 1200.0]) {
      await pumpDiagnostic(tester,
          width: width,
          scale: 1.8,
          create: () => AppNotificationDiagnosticReader(
              environment: current(),
              currentEnvironment: current,
              reads: reads,
              readPushers: () async => [_registeredPusher(account)]));
      expect(find.text(NotificationTroubleshooterPage.title), findsOneWidget);
      expect(find.textContaining('Passed · Android allows'), findsOneWidget);
      expect(find.textContaining('Failed · This category is blocked'),
          findsOneWidget);
      expect(find.textContaining('Passed · UnifiedPush'), findsOneWidget);
      expect(find.textContaining('Passed · A registration matches'),
          findsOneWidget);
      expect(find.textContaining('Not available ·'), findsOneWidget);
      expect(find.text('Send test notification'), findsNothing);
      expect(find.text('Copy report'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Resuming refreshes permission after opening Android settings',
      (tester) async {
    addTearDown(tester.view.reset);
    final reads = FixtureReads();
    await pumpDiagnostic(tester, create: () => fixtureReader(reads: reads));
    expect(find.textContaining('Passed · Android allows'), findsOneWidget);
    await tester.ensureVisible(find.text('Open Android app settings').first);
    await tester.tap(find.text('Open Android app settings').first);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    reads.allowed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed · Android blocks'), findsOneWidget);
    expect(find.textContaining('Passed · Android allows'), findsNothing);
    await tester.pumpWidget(const SizedBox());
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
