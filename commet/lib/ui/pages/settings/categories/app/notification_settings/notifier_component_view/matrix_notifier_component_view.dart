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
import 'package:intl/intl.dart';

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
        title: pusherRemoveTitle,
        prompt: ours
            ? pusherRemovePromptOurs(app, device)
            : pusherRemovePromptOther(app, device),
        confirmationText: pusherRemove,
        cancelText: pusherRemoveCancel,
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
            session: thisDevice ? pusherThisDevice : sessionLabel(session, now),
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
    if (session == null) return pusherSessionUnknown;
    final name = session.device.displayName ?? session.device.deviceId;
    final active = PusherHousekeeping.lastActive(session.lastSeen, now);
    return session.exact
        ? pusherSessionLabel(name, active)
        : pusherSessionLabelProbably(name, active);
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
                      pusherPushServer(gatewayHost ?? pusherPushServerUnknown),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  // Vommet: a Commet install on that device still uses it;
                  // neutral, so it isn't removed by mistake.
                  if (oldCommetGateway)
                    tiamat.Text.labelLow(pusherCommetGatewayNote),
                  if (rawData != null) tiamat.Text.labelLow(rawData!),
                ],
              ),
            ),
            if (onRemove != null)
              TextButton(
                onPressed: onRemove,
                child:
                    Text(pusherRemove, style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

String get pusherRemoveTitle => Intl.message("Remove push registration?",
    name: "pusherRemoveTitle",
    desc: "Title of the confirmation for removing a push registration");

String pusherRemovePromptOurs(String app, String device) => Intl.message(
    "$app on \"$device\" will stop getting notifications for this account. If that device is still in use, $app registers it again the next time it starts.",
    args: [app, device],
    name: "pusherRemovePromptOurs",
    desc:
        "Body of the remove-push-registration confirmation for a Vommet/Commet registration; app is the app name, device the device name");

String pusherRemovePromptOther(String app, String device) => Intl.message(
    "$app on \"$device\" will stop getting notifications for this account. $app may register again the next time it starts; if it doesn't, turn notifications back on in $app.",
    args: [app, device],
    name: "pusherRemovePromptOther",
    desc:
        "Body of the remove-push-registration confirmation for another app's registration; app is the app name, device the device name");

String get pusherRemove => Intl.message("Remove",
    name: "pusherRemove", desc: "Button that removes a push registration");

String get pusherRemoveCancel => Intl.message("Cancel",
    name: "pusherRemoveCancel",
    desc: "Cancel button of the remove-push-registration dialog");

String get pusherThisDevice => Intl.message("this device",
    name: "pusherThisDevice",
    desc: "Session label of a push registration belonging to this device");

String get pusherSessionUnknown => Intl.message("session unknown",
    name: "pusherSessionUnknown",
    desc: "Session label of a push registration whose session is unknown");

String pusherSessionLabel(String name, String active) => Intl.message(
    "$name, $active",
    args: [name, active],
    name: "pusherSessionLabel",
    desc:
        "Session label of a push registration; name is the session name, active is when it was last active (e.g. 'active 2 days ago')");

String pusherSessionLabelProbably(String name, String active) => Intl.message(
    "probably $name, $active",
    args: [name, active],
    name: "pusherSessionLabelProbably",
    desc:
        "Session label of a push registration when the session is a best guess; name is the session name, active when it was last active");

String pusherPushServer(String host) => Intl.message("push server: $host",
    args: [host],
    name: "pusherPushServer",
    desc:
        "Line showing which push server a registration uses; host is a host name or \"unknown\"");

String get pusherPushServerUnknown => Intl.message("unknown",
    name: "pusherPushServerUnknown",
    desc: "Shown as the push server host when it isn't known");

String get pusherCommetGatewayNote => Intl.message(
    "Commet's push server: only the Commet app gets these. Keep it if you use Commet on that device.",
    name: "pusherCommetGatewayNote",
    desc: "Note on a push registration that uses Commet's push server");
