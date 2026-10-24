import 'dart:async';

import 'package:commet/client/matrix/recovery_checkins_sync.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings › Security › Encryption & recovery: "Recovery key check-ins",
/// the switch for the "Still have your recovery key?" check-ins, with when
/// the next one comes and how often they come.
///
/// The setting is part of the schedule the user's Vommet devices share
/// ([RecoveryCheckInsSync]): turned off here, no device asks.
class RecoveryCheckInsRow extends StatefulWidget {
  const RecoveryCheckInsRow(this.records, {this.client, super.key});
  final SecureSetupRecords records;

  /// The account, to share the setting with the user's other devices
  /// (null in tests: this device only).
  final matrix.Client? client;

  @override
  State<RecoveryCheckInsRow> createState() => _RecoveryCheckInsRowState();
}

class _RecoveryCheckInsRowState extends State<RecoveryCheckInsRow> {
  bool expanded = false;
  StreamSubscription<matrix.SyncUpdate>? _sub;

  SecureSetupRecords get records => widget.records;

  @override
  void initState() {
    super.initState();
    final mx = widget.client;
    if (mx != null) {
      // Changed on another device while this page is open.
      _sub = mx.onSync.stream
          .where((u) =>
              u.accountData?.any((e) => e.type == RecoveryCheckInsSync.type) ??
              false)
          .listen((_) => _pull(mx));
      _pull(mx);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _pull(matrix.Client mx) async {
    try {
      await RecoveryCheckInsSync.pull(mx, records);
    } catch (e) {
      Log.w("Recovery key check-ins: couldn't read the shared copy: $e");
    }
    if (mounted) setState(() {});
  }

  /// Turning on is instant; turning off only after the warning's hold. The
  /// switch shows the saved setting meanwhile (no flip before the answer).
  Future<void> _onChanged(bool on) async {
    if (!on) {
      final confirmed = await showDialog<bool>(
          context: context, builder: (_) => const TurnOffCheckInsDialog());
      if (confirmed != true) return;
    }
    await records.setCheckInsEnabled(on);
    Log.i("Recovery key check-ins turned ${on ? "on" : "off"}");
    if (mounted) setState(() {});
    final mx = widget.client;
    if (mx != null) unawaited(RecoveryCheckInsSync.push(mx, records));
  }

  @override
  Widget build(BuildContext context) {
    final on = records.checkInsEnabled;
    final next = records.nextCheckInAt;
    final scheme = ColorScheme.of(context);
    final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                  on ? Icons.event_repeat_outlined : Icons.event_busy_outlined,
                  size: 22,
                  color: scheme.onSurfaceVariant)),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                tiamat.Text.label(recoveryCheckInsTitle),
                tiamat.Text.labelLow(
                    on ? recoveryCheckInsOn : recoveryCheckInsOff),
                if (on)
                  Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (next != null) ...[
                              Icon(Icons.schedule,
                                  size: 15, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 5),
                              tiamat.Text.labelLow(recoveryCheckInsNext(
                                  DateFormat.yMMMM().format(next.toLocal()))),
                              const SizedBox(width: 10)
                            ],
                            InkWell(
                                onTap: () =>
                                    setState(() => expanded = !expanded),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(recoveryCheckInsHowOften,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                  color: scheme.primary)),
                                      Icon(
                                          expanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          size: 18,
                                          color: scheme.primary)
                                    ]))
                          ])),
                if (!on)
                  Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(28),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange.shade400, size: 18),
                            Expanded(
                                child: tiamat.Text.labelLow(
                                    recoveryCheckInsOffWarning))
                          ]))
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
              child: tiamat.Switch(state: on, onChanged: _onChanged))
        ]));
    return SettingsSearchTarget(
        ids: const [recoveryCheckInsSettingId],
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row,
          if (on && expanded)
            Padding(
                padding: const EdgeInsets.only(left: 34, bottom: 4),
                child: _howOften(context))
        ]));
  }

  Widget _howOften(BuildContext context) => Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
          color: ColorScheme.of(context).surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        tiamat.Text.labelEmphasised(recoveryCheckInsHowTitle),
        const SizedBox(height: 4),
        _howLine(Icons.flag_outlined, recoveryCheckInsHowFirst),
        _howLine(Icons.trending_up_rounded, recoveryCheckInsHowThen),
        _howLine(Icons.event_repeat_outlined, recoveryCheckInsHowAfter),
        _howLine(Icons.replay_rounded, recoveryCheckInsHowReset),
        _howLine(Icons.snooze_outlined, recoveryCheckInsHowLater)
      ]));

  Widget _howLine(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon,
                size: 16, color: ColorScheme.of(context).onSurfaceVariant)),
        const SizedBox(width: 8),
        Expanded(child: tiamat.Text.labelLow(text))
      ]));
}

/// "Turn off check-ins?": pops true only after "Hold to turn off" was held.
class TurnOffCheckInsDialog extends StatelessWidget {
  const TurnOffCheckInsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SetupDialog(
        icon: const Icon(Icons.key_off_outlined, size: 40, color: setupWarn),
        title: recoveryCheckInsOffTitle,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(recoveryCheckInsOffBody, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          SetupCallout(Icons.event_repeat_outlined, t.colorScheme.primary,
              recoveryCheckInsOffRareTitle, recoveryCheckInsOffRareBody),
          const SizedBox(height: 14),
          Text(recoveryCheckInsOffCleanup, textAlign: TextAlign.center)
        ]),
        buttons: [
          SetupPrimaryButton(recoveryCheckInsOffKeep,
              onPressed: () => Navigator.of(context).pop(false)),
          const SizedBox(height: 12),
          HoldButton(recoveryCheckInsOffHold,
              onHeld: () => Navigator.of(context).pop(true)),
          const SizedBox(height: 6),
          Text(recoveryCheckInsOffLater,
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant))
        ]);
  }
}

String get recoveryCheckInsTitle => Intl.message("Recovery key check-ins",
    name: "recoveryCheckInsTitle",
    desc: "Settings › Security: title of the recovery key check-ins switch");

String get recoveryCheckInsOn => Intl.message(
    "Now and then, Vommet asks for your key to make sure you still have it. Each time you get it right, the next check comes later, until it's about twice a year.",
    name: "recoveryCheckInsOn",
    desc: "Settings › Security: recovery key check-ins switched on");

String recoveryCheckInsNext(String month) => Intl.message(
    "Next check: around $month",
    name: "recoveryCheckInsNext",
    args: [month],
    desc:
        "Settings › Security: when the next recovery key check-in comes (month and year)");

String get recoveryCheckInsHowOften => Intl.message("How often?",
    name: "recoveryCheckInsHowOften",
    desc: "Settings › Security: link that shows how often check-ins come");

String get recoveryCheckInsOff =>
    Intl.message("Off. Vommet won't check that you still have your key.",
        name: "recoveryCheckInsOff",
        desc: "Settings › Security: recovery key check-ins switched off");

String get recoveryCheckInsOffWarning => Intl.message(
    "Not recommended. If your key goes missing, you'd only find out on the day you need it, and your encrypted messages could be gone for good.",
    name: "recoveryCheckInsOffWarning",
    desc: "Settings › Security: warning under check-ins switched off");

String get recoveryCheckInsHowTitle => Intl.message("How often Vommet asks",
    name: "recoveryCheckInsHowTitle",
    desc: "Settings › Security: title of the check-in schedule explainer");

String get recoveryCheckInsHowFirst =>
    Intl.message("First, 2 weeks after you set up or sign in.",
        name: "recoveryCheckInsHowFirst",
        desc: "Check-in schedule explainer: the first check-in");

String get recoveryCheckInsHowThen => Intl.message(
    "Then 30, 90, and 180 days later, each time you get the one before right.",
    name: "recoveryCheckInsHowThen",
    desc: "Check-in schedule explainer: the growing gaps");

String get recoveryCheckInsHowAfter =>
    Intl.message("After that, about twice a year.",
        name: "recoveryCheckInsHowAfter",
        desc: "Check-in schedule explainer: the steady gap");

String get recoveryCheckInsHowReset => Intl.message(
    "Enter it wrong, say you've lost it, or make a new key, and it goes back to 30 days.",
    name: "recoveryCheckInsHowReset",
    desc: "Check-in schedule explainer: what starts the gaps over");

String get recoveryCheckInsHowLater => Intl.message(
    "\"Remind me later\" asks again in 3 days. After 3 of those in a row, the next check waits for an answer.",
    name: "recoveryCheckInsHowLater",
    desc: "Check-in schedule explainer: putting a check-in off");

String get recoveryCheckInsOffTitle => Intl.message("Turn off check-ins?",
    name: "recoveryCheckInsOffTitle",
    desc: "Title of the warning shown before turning check-ins off");

String get recoveryCheckInsOffBody => Intl.message(
    "We strongly recommend leaving them on. They're how you find out your key is lost while you can still make a new one, instead of on the day you need it.",
    name: "recoveryCheckInsOffBody",
    desc: "Body of the warning shown before turning check-ins off");

String get recoveryCheckInsOffRareTitle => Intl.message("They're rare",
    name: "recoveryCheckInsOffRareTitle",
    desc: "Callout title in the turn-off warning");

String get recoveryCheckInsOffRareBody => Intl.message(
    "2 weeks after setup, then 30, 90, and 180 days apart, then about twice a year. Each one takes a few seconds.",
    name: "recoveryCheckInsOffRareBody",
    desc: "Callout text in the turn-off warning: how often check-ins come");

String get recoveryCheckInsOffCleanup => Intl.message(
    "With them off, Vommet also won't remind you to finish cleaning up copies an old key can still open. Those stay until you next enter your recovery key.",
    name: "recoveryCheckInsOffCleanup",
    desc:
        "Turn-off warning: the old-key cleanup reminder goes away with check-ins");

String get recoveryCheckInsOffKeep => Intl.message("Keep check-ins on",
    name: "recoveryCheckInsOffKeep",
    desc: "Turn-off warning: button that keeps check-ins on");

String get recoveryCheckInsOffHold => Intl.message("Hold to turn off",
    name: "recoveryCheckInsOffHold",
    desc: "Turn-off warning: button held for 2 seconds to turn check-ins off");

String get recoveryCheckInsOffLater =>
    Intl.message("You can turn them back on here any time.",
        name: "recoveryCheckInsOffLater",
        desc: "Turn-off warning: small print under the buttons");
