import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/push_notification_component.dart';
import 'package:commet/client/matrix/components/push_notifications/pusher_housekeeping.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart';

class MatrixPushNotificationComponent
    implements PushNotificationComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixPushNotificationComponent(this.client);

  @override
  Future<void> ensurePushNotificationsRegistered(
      String pushKey, Uri pushServer, String deviceName,
      {Map<String, dynamic>? extraData}) async {
    var matrixClient = client.getMatrixClient();

    Log.i("Current push key: $pushKey");

    var pushers = await matrixClient.getPushers();

    var data = PusherData(
      format: "event_id_only",
      url: pushServer,
      additionalProperties: extraData ?? {},
    );

    if (pushers != null &&
        pushers.any((element) =>
            element.pushkey == pushKey &&
            element.data.toJson() == data.toJson())) {
      return;
    }

    var pusher = Pusher(
        appId: "chat.commet.commetapp.android",
        pushkey: pushKey,
        appDisplayName: BuildConfig.appName,
        data: data,
        deviceDisplayName: deviceName,
        kind: "http",
        lang: "en");

    await matrixClient.postPusher(pusher, append: true);
  }

  Future<void> cleanOldPushers(
      String? currentPushKey, String deviceName, Uri pushGateway) async {
    var matrixClient = client.getMatrixClient();
    var pushers = await matrixClient.getPushers();

    // Check for stale pushers
    if (pushers != null) {
      for (var pusher in pushers) {
        if (pusher.deviceDisplayName == deviceName &&
            (pusher.pushkey != currentPushKey ||
                pusher.data.url != pushGateway)) {
          await matrixClient.deletePusher(pusher);
        }
      }
      await _cleanStaleSessionPushers(pushers);
    }
  }

  /// Vommet: our pushers whose session is gone or unused for 90 days (see
  /// PusherHousekeeping.isStale). Untagged and other apps' pushers stay.
  Future<void> _cleanStaleSessionPushers(List<Pusher> pushers) async {
    var matrixClient = client.getMatrixClient();
    try {
      final devices = await matrixClient.getDevices() ?? const <Device>[];
      final now = DateTime.now();
      for (final pusher in pushers) {
        if (!PusherHousekeeping.isStale(pusher, devices, now,
            ownDeviceId: matrixClient.deviceID)) {
          continue;
        }
        Log.i("Removing the pusher of unused session "
            "${PusherHousekeeping.taggedDeviceId(pusher)}");
        await matrixClient.deletePusher(pusher);
      }
    } catch (e, s) {
      Log.w("Could not clean up old sessions' pushers");
      Log.onError(e, s);
    }
  }

  @override
  Future<void> updatePushers() async {
    if (NotificationManager.notifierLoading != null) {
      await NotificationManager.notifierLoading;
    }
    var notifier = NotificationManager.notifier;
    var key = await notifier?.getToken();
    var mxClient = client.getMatrixClient();
    var extraData = notifier?.extraRegistrationData();

    extraData ??= {};

    extraData["local_client_id"] = client.identifier;
    // Vommet: which session registered it, for "last active" and cleanup.
    final deviceId = mxClient.deviceID;
    if (deviceId != null) {
      extraData[PusherHousekeeping.deviceIdKey] = deviceId;
    }

    var name = mxClient.clientName;

    var uri = Uri.parse(preferences.pushGateway);
    if (uri.hasScheme == false) {
      uri = Uri.https(preferences.pushGateway);
    }

    uri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: "/_matrix/push/v1/notify");

    await cleanOldPushers(key, name, uri);

    if (key == null) {
      return;
    }

    await ensurePushNotificationsRegistered(key, uri, name,
        extraData: extraData);
  }

  @override
  void postLoginInit() async {
    updatePushers();
  }
}
