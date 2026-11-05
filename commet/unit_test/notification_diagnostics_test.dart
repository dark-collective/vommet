import 'dart:async';

import 'package:commet/utils/notification_diagnostics/diagnostic_check.dart';
import 'package:commet/utils/notification_diagnostics/notification_diagnostic_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/notification_diagnostic_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android adapter only invokes permission and channel reads', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final methods = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'areNotificationsEnabled') return true;
      if (call.method == 'getNotificationChannels') return <dynamic>[];
      fail('Unexpected mutation: ${call.method}');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    expect(await NotificationDiagnosticReads().androidPermission(), true);
    expect(await NotificationDiagnosticReads().androidChannels(), isEmpty);
    expect(methods, ['areNotificationsEnabled', 'getNotificationChannels']);
  });
  test(
      'Permission and current channel states distinguish blocked, quiet and unknown',
      () async {
    final reads = FixtureReads();
    final reader = fixtureReader(reads: reads);
    for (final (allowed, status) in [
      (true, DiagnosticStatus.passed),
      (false, DiagnosticStatus.failed),
      (null, DiagnosticStatus.unknown)
    ]) {
      reads.allowed = allowed;
      expect((await reader.permission()).single.status, status);
    }
    reads.found = [
      const AndroidNotificationChannel('messages', 'Old',
          importance: Importance.high),
      const AndroidNotificationChannel('messages_custom', 'private name',
          importance: Importance.low, playSound: false),
      const AndroidNotificationChannel('mentions_custom', 'Private',
          importance: Importance.none),
    ];
    expect((await reader.channels()).map((r) => r.status), [
      DiagnosticStatus.attention,
      DiagnosticStatus.failed,
      DiagnosticStatus.unknown
    ]);
    for (final (channel, state) in [
      (
        const AndroidNotificationChannel('a', 'A', importance: Importance.high),
        DiagnosticStatus.passed
      ),
      (
        const AndroidNotificationChannel('a', 'A',
            groupId: 'group', importance: Importance.high),
        DiagnosticStatus.unknown
      )
    ]) {
      expect(
          AppNotificationDiagnosticReader.channelResult('Messages', channel)
              .status,
          state);
    }
  });
  test(
      'Missing distributor, selection, key and disabled provider skip server reads',
      () async {
    var serverReads = 0;
    for (final mode in ['missing', 'unselected', 'disabled', 'key']) {
      final reads = FixtureReads();
      if (mode == 'missing') reads.installed = [];
      if (mode == 'unselected') reads.selected = 'uninstalled';
      final reader = fixtureReader(
          reads: reads,
          environment: fixtureEnvironment(
              enabled: mode != 'disabled',
              key: mode == 'key' ? null : 'secret-key'),
          pushers: () async {
            serverReads++;
            return [];
          });
      expect((await reader.provider()).single.status, DiagnosticStatus.failed);
      expect((await reader.registration()).single.status,
          DiagnosticStatus.notChecked);
    }
    expect(serverReads, 0);
  });
  test(
      'Registration matches app, key, gateway, device and account without disclosing data',
      () {
    final env = fixtureEnvironment();
    for (final p in [
      fixturePusher(key: 'other'),
      fixturePusher(app: 'other'),
      fixturePusher(gateway: 'https://other.invalid/notify')
    ]) {
      expect(
          AppNotificationDiagnosticReader.registrationResult(env, [p]).status,
          DiagnosticStatus.failed);
    }
    for (final device in [null, 'other']) {
      expect(
          AppNotificationDiagnosticReader.registrationResult(
              env, [fixturePusher(device: device)]).status,
          DiagnosticStatus.unknown);
    }
    final result = AppNotificationDiagnosticReader.registrationResult(
        env, [fixturePusher()]);
    expect(result.status, DiagnosticStatus.passed);
    expect(result.detail, contains('does not prove'));
    for (final secret in [
      'secret-key',
      'private-account',
      'private-name',
      'gateway.invalid',
      'device-one'
    ]) {
      expect('${result.title} ${result.detail}', isNot(contains(secret)));
    }
    for (final value in [
      'https://user:secret@gateway.invalid',
      'file:///tmp/key',
      'https://'
    ]) {
      expect(DiagnosticEnvironment.configuredGateway(value), isNull);
    }
    expect(
        DiagnosticEnvironment.configuredGateway(
            'gateway.invalid/path?secret=key'),
        Uri.parse('https://gateway.invalid/_matrix/push/v1/notify'));
  });
  test(
      'Provider names are whitelisted and selection changes invalidate all results',
      () async {
    final reads = FixtureReads()
      ..selected = 'secret.package'
      ..installed = ['secret.package'];
    final reader = fixtureReader(
        reads: reads,
        pushers: () async {
          reads.selected = 'changed';
          return [fixturePusher()];
        });
    final provider = (await reader.provider()).single;
    expect(provider.status, DiagnosticStatus.passed);
    expect(provider.detail, isNot(contains('secret')));
    await reader.registration();
    expect(reader.isCurrent, false);
  });
  test(
      'Other platforms avoid OS and push APIs; Firebase does not refresh tokens',
      () async {
    for (final platform in DiagnosticPlatform.values
        .where((p) => p != DiagnosticPlatform.android)) {
      final reads = FixtureReads();
      final reader = fixtureReader(
          environment: fixtureEnvironment(
              platform: platform, provider: DiagnosticProvider.local),
          reads: reads,
          pushers: () async => throw StateError('must not read'));
      expect(
          (await reader.permission()).single.status, DiagnosticStatus.unknown);
      expect((await reader.channels()).single.status,
          DiagnosticStatus.unavailable);
      expect((await reader.provider()).single.status,
          DiagnosticStatus.unavailable);
      expect((await reader.registration()).single.status,
          DiagnosticStatus.unavailable);
      expect(reads.calls, isEmpty);
    }
    final reader = fixtureReader(
        environment: fixtureEnvironment(provider: DiagnosticProvider.firebase),
        pushers: () async => null);
    expect((await reader.provider()).single.status, DiagnosticStatus.unknown);
    expect(
        (await reader.registration()).single.status, DiagnosticStatus.unknown);
  });
  test('Cancel and retry discard late results and stop subsequent checks',
      () async {
    final pending = Completer<List<DiagnosticResult>>();
    var calls = 0, later = 0;
    final c = NotificationDiagnosticController(() => FixtureReader([
          DiagnosticCheck(
              'First',
              () => ++calls == 1
                  ? pending.future
                  : Future.value(one('First', DiagnosticStatus.passed, 'new'))),
          DiagnosticCheck('Later', () async {
            later++;
            return [];
          })
        ]));
    addTearDown(c.dispose);
    final first = c.run();
    await c.run();
    expect(calls, 1);
    c.cancel();
    expect(c.results, isEmpty);
    await c.run();
    pending.complete(one('First', DiagnosticStatus.failed, 'old'));
    await first;
    expect(c.results.first.single.detail, 'new');
    expect(later, 1);
  });
  test(
      'Timeout, setup failure and network errors are unknown and redact exceptions',
      () async {
    final c = NotificationDiagnosticController(
        () => FixtureReader([
              DiagnosticCheck(
                  'Timeout', () => Completer<List<DiagnosticResult>>().future),
              DiagnosticCheck('Network', () async => throw StateError('secret'))
            ]),
        timeout: const Duration(milliseconds: 1));
    addTearDown(c.dispose);
    await c.run();
    expect(
        c.results.expand((r) => r).every((r) =>
            r.status == DiagnosticStatus.unknown &&
            !r.detail.contains('secret')),
        true);
    final failed =
        NotificationDiagnosticController(() => throw StateError('secret'));
    addTearDown(failed.dispose);
    await failed.run();
    expect(failed.results.single.single.status, DiagnosticStatus.unknown);
    expect(failed.results.single.single.detail, isNot(contains('secret')));
    final changed = NotificationDiagnosticController(() =>
        FixtureReader([DiagnosticCheck('One', () async => [])])
          ..isCurrent = false);
    addTearDown(changed.dispose);
    await changed.run();
    expect(changed.results, isEmpty);
    expect(changed.notice, contains('Configuration changed'));
  });
}
