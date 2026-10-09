import 'dart:convert';

import 'package:commet/client/matrix/components/push_notifications/matrix_push_notification_component.dart';
import 'package:commet/client/matrix/components/push_notifications/pusher_housekeeping.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/atoms/panel.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The account's push registrations (pushers), with the session each belongs
/// to and a Remove button. Vommet: lists sessions' last activity so stale
/// registrations can be spotted and removed.
class MatrixNotifierComponentView extends StatefulWidget {
  const MatrixNotifierComponentView(this.component, {super.key});
  final MatrixPushNotificationComponent component;

  @override
  State<MatrixNotifierComponentView> createState() =>
      _MatrixNotifierComponentViewState();
}

class _MatrixNotifierComponentViewState
    extends State<MatrixNotifierComponentView> {
  List<matrix.Pusher>? pushers;
  List<matrix.Device> devices = const [];

  matrix.Client get mx => widget.component.client.getMatrixClient();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final value = await mx.getPushers();
    List<matrix.Device> sessions = const [];
    try {
      sessions = await mx.getDevices() ?? const [];
    } catch (e, s) {
      Log.onError(e, s);
    }
    if (!mounted) return;
    setState(() {
      pushers = value ?? const [];
      devices = sessions;
    });
  }

  Future<void> remove(matrix.Pusher pusher, {required String device}) async {
    final app = pusher.appDisplayName;
    final ours = PusherHousekeeping.ourAppIds.contains(pusher.appId);
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: "Remove push registration?",
        prompt: "$app on \"$device\" will stop getting notifications for "
            "this account. "
            "${ours ? "If that device is still in use, $app registers it again the next time it starts." : "$app may register again the next time it starts; if it doesn't, turn notifications back on in $app."}",
        confirmationText: "Remove",
        cancelText: "Cancel",
        dangerous: true);
    if (confirmed != true) return;
    try {
      await mx.deletePusher(pusher);
    } catch (e, s) {
      Log.onError(e, s);
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
    if (pushers == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    bool isOurs(matrix.Pusher e) => e.deviceDisplayName == mx.clientName;
    final ourPushers = pushers!.where(isOurs);
    final otherPushers = pushers!.where((e) => !isOurs(e));
    final now = DateTime.now();

    Widget entry(matrix.Pusher e, {required bool thisDevice}) {
      final session = PusherHousekeeping.sessionOf(e, devices);
      return Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
          child: PusherEntryView(
            appName: e.appDisplayName,
            // Vommet names its pushers by an internal account id; the
            // session's name says more when it's known.
            deviceName: thisDevice || session?.exact == true
                ? null
                : e.deviceDisplayName,
            gatewayHost: PusherHousekeeping.gatewayHost(e),
            session: thisDevice ? "this device" : sessionLabel(session, now),
            oldCommetGateway: PusherHousekeeping.usesCommetGateway(e),
            rawData: preferences.developerMode.value
                ? "key: ${redactedKey(e.pushkey)}\n"
                    "data: ${const JsonEncoder.withIndent("  ").convert(e.data.toJson())}"
                : null,
            // Removing this device's own would silence it until restart.
            onRemove: thisDevice
                ? null
                : () => remove(e,
                    device: session?.device.displayName ?? e.deviceDisplayName),
          ));
    }

    return Column(children: [
      Panel(
        header: "This Device",
        mode: TileType.surfaceContainerLowest,
        child: Column(
            children:
                ourPushers.map((e) => entry(e, thisDevice: true)).toList()),
      ),
      const SizedBox(
        height: 10,
      ),
      Panel(
        header: "Other Devices",
        mode: TileType.surfaceContainerLowest,
        child: Column(
            children:
                otherPushers.map((e) => entry(e, thisDevice: false)).toList()),
      ),
    ]);
  }

  static String sessionLabel(PusherSession? session, DateTime now) {
    if (session == null) return "session unknown";
    final name = session.device.displayName ?? session.device.deviceId;
    final active = PusherHousekeeping.lastActive(session.lastSeen, now);
    return session.exact ? "$name, $active" : "probably $name, $active";
  }

  static String redactedKey(String pushkey) {
    final uri = Uri.tryParse(pushkey);
    if (uri != null && (uri.scheme == "http" || uri.scheme == "https")) {
      final path = uri.path.length > 6 ? uri.path.substring(0, 6) : uri.path;
      return "${uri.scheme}://${uri.host}$path...";
    }
    return pushkey.length > 10 ? "${pushkey.substring(0, 10)}..." : pushkey;
  }
}

/// One push registration: app, device, the session it belongs to with its
/// last activity, the push server, and Remove.
class PusherEntryView extends StatelessWidget {
  const PusherEntryView(
      {required this.appName,
      this.deviceName,
      required this.session,
      this.gatewayHost,
      this.oldCommetGateway = false,
      this.rawData,
      this.onRemove,
      super.key});

  final String appName;
  final String? deviceName;
  final String session;
  final String? gatewayHost;
  final bool oldCommetGateway;

  /// Shown in developer mode.
  final String? rawData;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: scheme.surfaceContainerLow,
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tiamat.Text.label(
                      deviceName == null ? appName : "$appName · $deviceName",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  tiamat.Text.labelLow(session),
                  tiamat.Text.labelLow(
                      "push server: ${gatewayHost ?? "unknown"}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  // Vommet: a Commet install on that device still uses it;
                  // neutral, so it isn't removed by mistake.
                  if (oldCommetGateway)
                    tiamat.Text.labelLow(
                        "Commet's push server: only the Commet app gets "
                        "these. Keep it if you use Commet on that device."),
                  if (rawData != null) tiamat.Text.labelLow(rawData!),
                ],
              ),
            ),
            if (onRemove != null)
              TextButton(
                onPressed: onRemove,
                child: Text("Remove", style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
