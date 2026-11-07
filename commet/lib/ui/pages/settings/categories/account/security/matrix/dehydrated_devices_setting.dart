import 'dart:async';

import 'package:commet/client/matrix/dehydrated_devices.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 965: Settings › Security › Messages while signed out, the
/// switch for the stand-in session (MSC3814 dehydrated device) and what's
/// on the server now.
class DehydratedDevicesStrings {
  static String get panelTitle => Intl.message("Messages while signed out",
      desc:
          "Header of the Security settings section about receiving encrypted messages while every device is signed out",
      name: "labelDehydratedPanelTitle");

  static String get toggleTitle =>
      Intl.message("Receive messages while signed out",
          desc: "Toggle for the stand-in session that collects message keys",
          name: "labelDehydratedToggle");

  static String get toggleDescription => Intl.message(
      "Keeps a locked stand-in session on your server. Messages sent while you're signed out everywhere open after you sign back in with your recovery key.",
      desc: "Explains the stand-in session toggle",
      name: "labelDehydratedToggleDescription");

  static String get statusTitle => Intl.message("Stand-in session",
      desc: "Label of the row showing the stand-in session's state",
      name: "labelDehydratedStatusTitle");

  static String get on => Intl.message("On",
      desc: "Stand-in session state: Vommet keeps it",
      name: "labelDehydratedOn");

  static String get otherApp => Intl.message("Kept by another app",
      desc: "Stand-in session state: another app such as Element keeps it",
      name: "labelDehydratedOtherApp");

  static String get off => Intl.message("Off",
      desc: "Stand-in session state: there is none",
      name: "labelDehydratedOff");

  static String get starting => Intl.message("Starting…",
      desc: "Stand-in session state: on, but not created yet",
      name: "labelDehydratedStarting");

  static String get unknown => Intl.message("Couldn't check",
      desc: "Stand-in session state: the server couldn't be asked right now",
      name: "labelDehydratedUnknown");

  static String get unknownExplanation => Intl.message(
      "Vommet couldn't reach your server to check. It tries again the next time you open this page.",
      desc: "Explains the Couldn't check state",
      name: "labelDehydratedUnknownExplanation");

  static String get keptByVommet => Intl.message("Vommet keeps it.",
      desc: "Explains the On state of the stand-in session",
      name: "labelDehydratedKeptByVommet");

  static String refreshed(String when) => Intl.message(
      "Vommet keeps it. It was last refreshed $when.",
      args: [when],
      desc:
          "Explains the On state; the argument is 'today', 'yesterday' or 'on <date>'",
      name: "labelDehydratedRefreshed");

  static String get today => Intl.message("today",
      desc: "Used in 'It was last refreshed today'",
      name: "labelDehydratedToday");

  static String get yesterday => Intl.message("yesterday",
      desc: "Used in 'It was last refreshed yesterday'",
      name: "labelDehydratedYesterday");

  static String onDate(String date) => Intl.message("on $date",
      args: [date],
      desc: "Used in 'It was last refreshed on <date>'",
      name: "labelDehydratedOnDate");

  static String get otherAppExplanation => Intl.message(
      "Another app, such as Element, keeps it. Vommet leaves it alone, so messages it collects open in that app first.",
      desc: "Explains the 'Kept by another app' state",
      name: "labelDehydratedOtherAppExplanation");

  static String get offExplanation => Intl.message(
      "No stand-in session. Messages sent while you're signed out everywhere may stay unreadable.",
      desc: "Explains the Off state after turning the switch off",
      name: "labelDehydratedOffExplanation");

  static String get serverCantExplanation =>
      Intl.message("Your server doesn't support stand-in sessions yet.",
          desc: "Explains the Off state when the server can't keep one",
          name: "labelDehydratedServerCantExplanation");

  static String get startingExplanation => Intl.message(
      "Starts the next time you enter your recovery key, for example at the next check-in.",
      desc: "Explains the Starting state",
      name: "labelDehydratedStartingExplanation");

  static String get turnOffTitle => Intl.message(
      "Stop receiving messages while signed out?",
      desc: "Title of the dialog confirming the stand-in session is turned off",
      name: "labelDehydratedTurnOffTitle");

  static String get turnOffPrompt => Intl.message(
      "Vommet removes its stand-in session from your server. Messages sent while you're signed out everywhere may stay unreadable. Another app's stand-in session is not touched.",
      desc: "Body of the dialog confirming the stand-in session is turned off",
      name: "labelDehydratedTurnOffPrompt");

  static String get turnOff => Intl.message("Turn off",
      desc: "Confirms turning the stand-in session off",
      name: "labelDehydratedTurnOff");

  static String get cancel => Intl.message("Cancel",
      desc: "Keeps the stand-in session on", name: "labelDehydratedCancel");
}

class DehydratedDevicesPanel extends StatefulWidget {
  const DehydratedDevicesPanel(this.client, {super.key});
  final MatrixClient client;

  @override
  State<DehydratedDevicesPanel> createState() => _DehydratedDevicesPanelState();
}

class _DehydratedDevicesPanelState extends State<DehydratedDevicesPanel> {
  StandInStatus? status;
  bool busy = false;
  StreamSubscription? _sub;
  StreamSubscription? _refreshedSub;

  @override
  void initState() {
    super.initState();
    _sub = DehydratedDevices.onChanged.listen((_) => _load());
    _refreshedSub = DehydratedDevices.onRefreshed.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _refreshedSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final mx = widget.client.getMatrixClient();
    StandInStatus s;
    try {
      s = await DehydratedDevices.status(mx);
    } catch (e) {
      Log.w("Stand-in session status: $e");
      s = DehydratedDevices.isOn(mx)
          ? StandInStatus.unknown
          : StandInStatus.off;
    }
    if (mounted) setState(() => status = s);
  }

  Future<void> _onChanged(bool on) async {
    final mx = widget.client.getMatrixClient();
    if (!on) {
      final confirmed = await AdaptiveDialog.confirmation(context,
          title: DehydratedDevicesStrings.turnOffTitle,
          prompt: DehydratedDevicesStrings.turnOffPrompt,
          confirmationText: DehydratedDevicesStrings.turnOff,
          cancelText: DehydratedDevicesStrings.cancel,
          dangerous: true);
      if (confirmed != true) return;
    }
    setState(() => busy = true);
    try {
      await DehydratedDevices.setOn(mx, on);
      Log.i("Stand-in session turned ${on ? "on" : "off"}");
    } catch (e, s) {
      Log.onError(e, s,
          content: "Turning the stand-in session ${on ? "on" : "off"}");
    }
    if (!mounted) return;
    setState(() => busy = false);
    await _load();
  }

  String _refreshedText() {
    final at = DehydratedDevices.lastRefreshed(widget.client.getMatrixClient());
    if (at == null) return DehydratedDevicesStrings.keptByVommet;
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(at.year, at.month, at.day))
        .inDays;
    final when = days <= 0
        ? DehydratedDevicesStrings.today
        : days == 1
            ? DehydratedDevicesStrings.yesterday
            : DehydratedDevicesStrings.onDate(DateFormat.yMMMd().format(at));
    return DehydratedDevicesStrings.refreshed(when);
  }

  @override
  Widget build(BuildContext context) {
    final mx = widget.client.getMatrixClient();
    if (mx.encryption == null) return const SizedBox.shrink();
    final scheme = ColorScheme.of(context);
    final s = status;
    final switchOn = s == null
        ? DehydratedDevices.isOn(mx)
        : s != StandInStatus.off && s != StandInStatus.serverCant;
    final chip = switch (s) {
      null => null,
      StandInStatus.on => (
          Icons.check_circle_outline,
          DehydratedDevicesStrings.on,
          Colors.green,
          _refreshedText()
        ),
      StandInStatus.otherApp => (
          Icons.apps_outlined,
          DehydratedDevicesStrings.otherApp,
          scheme.primary,
          DehydratedDevicesStrings.otherAppExplanation
        ),
      StandInStatus.off => (
          Icons.remove_circle_outline,
          DehydratedDevicesStrings.off,
          Colors.orange.shade400,
          DehydratedDevicesStrings.offExplanation
        ),
      StandInStatus.serverCant => (
          Icons.cloud_off_outlined,
          DehydratedDevicesStrings.off,
          scheme.onSurfaceVariant,
          DehydratedDevicesStrings.serverCantExplanation
        ),
      StandInStatus.starting => (
          Icons.hourglass_top_rounded,
          DehydratedDevicesStrings.starting,
          scheme.primary,
          DehydratedDevicesStrings.startingExplanation
        ),
      StandInStatus.unknown => (
          Icons.help_outline,
          DehydratedDevicesStrings.unknown,
          scheme.onSurfaceVariant,
          DehydratedDevicesStrings.unknownExplanation
        ),
    };
    return tiamat.Panel(
      header: DehydratedDevicesStrings.panelTitle,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(spacing: 4, children: [
          _row(
              context,
              Icons.move_to_inbox_outlined,
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      tiamat.Text.label(DehydratedDevicesStrings.toggleTitle),
                      tiamat.Text.labelLow(
                          DehydratedDevicesStrings.toggleDescription),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: tiamat.Switch(
                      state: switchOn,
                      onChanged: busy || s == StandInStatus.serverCant
                          ? null
                          : _onChanged),
                ),
              ])),
          if (chip != null) ...[
            const tiamat.Seperator(),
            _row(
                context,
                Icons.phonelink_lock_outlined,
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Row(spacing: 10, children: [
                        Flexible(
                            child: tiamat.Text.label(
                                DehydratedDevicesStrings.statusTitle)),
                        Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 3,
                            children: [
                              Icon(chip.$1, size: 14, color: chip.$3),
                              Text(chip.$2,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                          color: chip.$3,
                                          fontWeight: FontWeight.w600)),
                            ]),
                      ]),
                      tiamat.Text.labelLow(chip.$4),
                    ])),
          ],
        ]),
      ),
    );
  }

  /// Like the Encryption & recovery rows: a leading icon, then the content.
  Widget _row(BuildContext context, IconData icon, Widget content) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(icon,
                size: 22, color: ColorScheme.of(context).onSurfaceVariant),
          ),
          Expanded(child: content),
        ]),
      );
}
