import 'package:commet/utils/notification_diagnostics/diagnostic_check.dart';
import 'package:commet/utils/notification_diagnostics/notification_diagnostic_reader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart' as matrix;

class FixtureReads extends NotificationDiagnosticReads {
  bool? allowed = true;
  List<String> installed = ['io.heckel.ntfy'];
  String? selected = 'io.heckel.ntfy';
  List<AndroidNotificationChannel>? found = [];
  final calls = <String>[];
  Future<T> record<T>(String name, T value) async {
    calls.add(name);
    return value;
  }

  @override
  Future<bool?> androidPermission() => record('permission', allowed);
  @override
  Future<List<AndroidNotificationChannel>?> androidChannels() =>
      record('channels', found);
  @override
  Future<List<String>> distributors() => record('distributors', installed);
  @override
  Future<String?> distributor() => record('distributor', selected);
}

DiagnosticEnvironment fixtureEnvironment(
        {DiagnosticPlatform platform = DiagnosticPlatform.android,
        DiagnosticProvider provider = DiagnosticProvider.unifiedPush,
        bool enabled = true,
        String? key = 'secret-key',
        String? device = 'device-one'}) =>
    DiagnosticEnvironment(
        platform: platform,
        provider: provider,
        enabled: enabled,
        key: key,
        gateway: Uri.parse('https://gateway.invalid/_matrix/push/v1/notify'),
        deviceId: device,
        accountId: 'private-account',
        channels: const {
          'messages_custom': 'Messages',
          'mentions_custom': 'Mentions and replies',
          'chat_invites': 'Chat invitations'
        });

matrix.Pusher fixturePusher(
        {String key = 'secret-key',
        String? device = 'device-one',
        String app = 'chat.commet.commetapp.android',
        String gateway = 'https://gateway.invalid/_matrix/push/v1/notify'}) =>
    matrix.Pusher(
        appId: app,
        pushkey: key,
        kind: 'http',
        lang: 'en',
        appDisplayName: 'Vommet',
        deviceDisplayName: 'private-name',
        data: matrix.PusherData(url: Uri.parse(gateway), additionalProperties: {
          'local_client_id': 'private-account',
          if (device != null) 'im.nether.vommet.device_id': device
        }));

AppNotificationDiagnosticReader fixtureReader(
    {DiagnosticEnvironment? environment,
    FixtureReads? reads,
    Future<List<matrix.Pusher>?> Function()? pushers}) {
  final env = environment ?? fixtureEnvironment();
  return AppNotificationDiagnosticReader(
      environment: env,
      currentEnvironment: () => env,
      reads: reads ?? FixtureReads(),
      readPushers: pushers ?? () async => [fixturePusher()]);
}

class FixtureReader implements NotificationDiagnosticReader {
  FixtureReader(this.checks);
  @override
  final List<DiagnosticCheck> checks;
  @override
  bool isCurrent = true;
}
