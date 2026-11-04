import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/android/firebase_push_notifier.dart';
import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/matrix/components/push_notifications/pusher_housekeeping.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/notification_diagnostics/diagnostic_check.dart';
import 'package:commet/utils/notification_diagnostics/diagnostic_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:unifiedpush/unifiedpush.dart';

typedef S = DiagnosticStrings;

enum DiagnosticPlatform { android, ios, macos, web, linux, windows, other }

enum DiagnosticProvider { unifiedPush, firebase, local, missing }

/// Secrets remain here, never in display results, reports, logs or uploads.
class DiagnosticEnvironment {
  const DiagnosticEnvironment(
      {required this.platform,
      required this.provider,
      this.enabled = true,
      this.key,
      this.gateway,
      this.deviceId,
      this.accountId,
      this.channels = const {}});
  final DiagnosticPlatform platform;
  final DiagnosticProvider provider;
  final bool enabled;
  final String? key, deviceId, accountId;
  final Uri? gateway;
  final Map<String, String> channels;
  Object get identity => (
        platform,
        provider,
        enabled,
        key,
        gateway,
        deviceId,
        accountId,
        channels.toString()
      );
  static Uri? configuredGateway(String value) {
    try {
      final u = Uri.tryParse(value.contains('://') ? value : 'https://$value');
      if (u == null ||
          !{'https', 'http'}.contains(u.scheme) ||
          u.host.isEmpty ||
          u.userInfo.isNotEmpty) return null;
      return Uri(
          scheme: u.scheme,
          host: u.host,
          port: u.hasPort ? u.port : null,
          path: '/_matrix/push/v1/notify');
    } on FormatException {
      return null;
    }
  }

  static DiagnosticEnvironment current(Client? client) {
    final platform = kIsWeb
        ? DiagnosticPlatform.web
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => DiagnosticPlatform.android,
            TargetPlatform.iOS => DiagnosticPlatform.ios,
            TargetPlatform.macOS => DiagnosticPlatform.macos,
            TargetPlatform.linux => DiagnosticPlatform.linux,
            TargetPlatform.windows => DiagnosticPlatform.windows,
            _ => DiagnosticPlatform.other,
          };
    final n = NotificationManager.notifier;
    final provider = n is UnifiedPushNotifier
        ? DiagnosticProvider.unifiedPush
        : n is FirebasePushNotifier
            ? DiagnosticProvider.firebase
            : n == null
                ? DiagnosticProvider.missing
                : DiagnosticProvider.local;
    final mx = client is MatrixClient ? client.getMatrixClient() : null;
    final channels = <String, String>{};
    if (platform == DiagnosticPlatform.android) {
      channels[AppSounds.androidChannelId(SoundEvent.message)] = S.messages;
      final mention = AppSounds.androidChannelId(SoundEvent.mention);
      channels[mention] =
          channels.containsKey(mention) ? S.messagesMentions : S.mentions;
      channels['chat_invites'] = S.invites;
      channels[AppSounds.androidChannelId(SoundEvent.ringIncoming)] = S.calls;
    }
    return DiagnosticEnvironment(
        platform: platform,
        provider: provider,
        enabled: provider == DiagnosticProvider.unifiedPush
            ? preferences.unifiedPushEnabled.value == true
            : n?.enabled == true,
        key: provider == DiagnosticProvider.unifiedPush
            ? preferences.unifiedPushEndpoint.value
            : provider == DiagnosticProvider.firebase
                ? preferences.fcmKey.value
                : null,
        gateway: configuredGateway(preferences.pushGateway),
        deviceId: mx?.deviceID,
        accountId: client?.identifier,
        channels: channels);
  }
}

/// Read-only surface: no initialization, permission request, token refresh,
/// distributor launch, channel writes, pusher writes or notification sends.
class NotificationDiagnosticReads {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<bool?> androidPermission() async => plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.areNotificationsEnabled();
  Future<List<AndroidNotificationChannel>?> androidChannels() async => plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.getNotificationChannels();
  Future<List<String>> distributors() => UnifiedPush.getDistributors([]);
  Future<String?> distributor() => UnifiedPush.getDistributor();
}

class AppNotificationDiagnosticReader implements NotificationDiagnosticReader {
  AppNotificationDiagnosticReader(
      {required this.environment,
      required this.currentEnvironment,
      required this.readPushers,
      NotificationDiagnosticReads? reads})
      : reads = reads ?? NotificationDiagnosticReads();
  factory AppNotificationDiagnosticReader.forClient(Client? client) {
    Client? available() =>
        clientManager?.clients.contains(client) == true ? client : null;
    final c = available();
    return AppNotificationDiagnosticReader(
        environment: DiagnosticEnvironment.current(c),
        currentEnvironment: () => DiagnosticEnvironment.current(available()),
        readPushers: c is MatrixClient ? c.getMatrixClient().getPushers : null);
  }
  final DiagnosticEnvironment environment;
  final DiagnosticEnvironment Function() currentEnvironment;
  final Future<List<matrix.Pusher>?> Function()? readPushers;
  final NotificationDiagnosticReads reads;
  bool _providerReady = false, _selectionChanged = false;
  String? _selected;
  @override
  bool get isCurrent =>
      !_selectionChanged &&
      environment.identity == currentEnvironment().identity;
  @override
  List<DiagnosticCheck> get checks => [
        DiagnosticCheck(S.permission, permission),
        DiagnosticCheck(S.channels, channels),
        DiagnosticCheck(S.provider, provider),
        DiagnosticCheck(S.registration, registration)
      ];
  Future<List<DiagnosticResult>> permission() async {
    final p = environment.platform;
    final allowed = p == DiagnosticPlatform.android
        ? await reads.androidPermission()
        : null;
    return one(
        S.permission,
        allowed == null
            ? DiagnosticStatus.unknown
            : allowed
                ? DiagnosticStatus.passed
                : DiagnosticStatus.failed,
        allowed == null
            ? S.permissionUnknown
            : allowed
                ? S.androidAllowed
                : S.androidBlocked,
        p == DiagnosticPlatform.android
            ? DiagnosticAction.androidSettings
            : null);
  }

  Future<List<DiagnosticResult>> channels() async {
    if (environment.platform != DiagnosticPlatform.android)
      return one(
          S.channels, DiagnosticStatus.unavailable, S.channelsUnavailable);
    final found = await reads.androidChannels();
    return [
      for (final e in environment.channels.entries)
        channelResult(e.value, found?.where((c) => c.id == e.key).firstOrNull)
    ];
  }

  static DiagnosticResult channelResult(
      String title, AndroidNotificationChannel? c) {
    final (state, detail) = c == null
        ? (DiagnosticStatus.unknown, S.channelMissing)
        : c.importance == Importance.none
            ? (DiagnosticStatus.failed, S.channelBlocked)
            : c.importance.value < 0 || c.groupId?.isNotEmpty == true
                ? (DiagnosticStatus.unknown, S.channelUnknown)
                : !c.playSound || c.importance.value < Importance.high.value
                    ? (DiagnosticStatus.attention, S.channelQuiet)
                    : (DiagnosticStatus.passed, S.channelAllowed);
    return DiagnosticResult(title, state, detail,
        action: DiagnosticAction.androidSettings);
  }

  Future<List<DiagnosticResult>> provider() async {
    _providerReady = false;
    final e = environment;
    if (e.provider == DiagnosticProvider.missing)
      return one(S.provider, DiagnosticStatus.unknown, S.providerMissing);
    if (e.provider == DiagnosticProvider.local)
      return one(S.provider, DiagnosticStatus.unavailable, S.localProvider);
    if (!e.enabled)
      return one(S.provider, DiagnosticStatus.failed, S.providerOff,
          DiagnosticAction.notificationSettings);
    if (e.provider == DiagnosticProvider.unifiedPush) {
      final found = await reads.distributors();
      _selected = await reads.distributor();
      if (found.isEmpty || !found.contains(_selected))
        return one(
            S.provider,
            DiagnosticStatus.failed,
            found.isEmpty ? S.noDistributor : S.noSelection,
            DiagnosticAction.notificationSettings);
    }
    _providerReady = e.key?.isNotEmpty == true;
    // Software brand names are provider data; only the fixed whitelist is displayed.
    final name = switch (_selected) {
      'io.heckel.ntfy' => S.ntfy,
      'org.unifiedpush.distributor.nextpush' => S.nextPush,
      'org.unifiedpush.distributor.sunup' => S.sunup,
      'org.unifiedpush.distributor.fcm' => S.fcmDistributor,
      _ => S.otherDistributor
    };
    return one(
        S.provider,
        !_providerReady
            ? DiagnosticStatus.failed
            : e.provider == DiagnosticProvider.firebase
                ? DiagnosticStatus.unknown
                : DiagnosticStatus.passed,
        _providerReady
            ? S.providerSaved(e.provider == DiagnosticProvider.firebase
                ? S.firebase
                : S.selected(name))
            : S.noKey,
        DiagnosticAction.notificationSettings);
  }

  Future<List<DiagnosticResult>> registration() async {
    if (environment.provider == DiagnosticProvider.local)
      return one(
          S.registration, DiagnosticStatus.unavailable, S.localRegistration);
    if (!_providerReady)
      return one(
          S.registration, DiagnosticStatus.notChecked, S.registrationSkipped);
    if (readPushers == null || environment.gateway == null)
      return one(S.registration, DiagnosticStatus.unknown, S.accountUnknown);
    final pushers = await readPushers!();
    if (environment.provider == DiagnosticProvider.unifiedPush &&
        await reads.distributor() != _selected) {
      _selectionChanged = true;
      return one(S.registration, DiagnosticStatus.unknown, S.changed);
    }
    return pushers == null
        ? one(S.registration, DiagnosticStatus.unknown, S.registrationUnknown)
        : [registrationResult(environment, pushers)];
  }

  static DiagnosticResult registrationResult(
      DiagnosticEnvironment e, List<matrix.Pusher> pushers) {
    final matches = pushers.where((p) =>
        PusherHousekeeping.ourAppIds.contains(p.appId) &&
        p.kind == 'http' &&
        (e.provider != DiagnosticProvider.firebase ||
            p.data.additionalProperties['type'] == 'fcm') &&
        p.pushkey == e.key &&
        p.data.url == e.gateway);
    final (state, detail) = matches.isEmpty
        ? (DiagnosticStatus.failed, S.registrationMissing)
        : e.deviceId == null ||
                !matches.any((p) =>
                    PusherHousekeeping.taggedDeviceId(p) == e.deviceId &&
                    p.data.additionalProperties['local_client_id'] ==
                        e.accountId)
            ? (DiagnosticStatus.unknown, S.sessionUnknown)
            : (DiagnosticStatus.passed, S.registered);
    return DiagnosticResult(S.registration, state, detail,
        action: DiagnosticAction.notificationSettings);
  }
}
