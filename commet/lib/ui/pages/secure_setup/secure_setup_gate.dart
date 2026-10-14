import 'dart:async';

import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_flow.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 129: runs the secure messaging setup before any room opens.
/// Accounts already set up (judged from what's stored on the device, which
/// is instant) never see a screen; only when one looks like it needs setup
/// does a full-screen route cover the app, confirm with the server, and show
/// the flow. Then due "Still have your recovery key?" check-ins.
class SecureSetupGate {
  static bool get enabled => preferences.experimentSecureSetup.value;

  /// Notifies the room-list reminder banner when something changes.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static Future<void> run(BuildContext context, ClientManager manager) async {
    Log.i("Secure setup at sign-in: ${enabled ? "checking" : "off"}");
    if (!enabled) return;
    final clients = manager.clients.whereType<MatrixClient>().toList();
    final pending = <MatrixClient>[];
    for (final client in clients) {
      final cached = await cachedStatus(client);
      final records = SecureSetupRecords(client.getMatrixClient().userID!);
      Log.i("Secure setup at sign-in: ${cached.state.name}"
          "${records.skipped ? " (skipped before)" : ""}");
      // Unknown (no encryption on this account/server): never block.
      if (cached.needsSetup && !records.skipped) {
        pending.add(client);
      }
    }
    if (pending.isNotEmpty && context.mounted) {
      await Navigator.of(context).push(PageRouteBuilder(
          opaque: true, pageBuilder: (_, __, ___) => _GatePage(pending)));
    }
    changed.value++;
    if (!context.mounted) return;
    for (final client in clients) {
      await maybeCheckIn(context, client);
    }
  }

  /// The status from what's stored on the device (no network).
  static Future<SecureMessagingStatus> cachedStatus(MatrixClient client) async {
    final mx = client.getMatrixClient();
    try {
      await mx.accountDataLoading;
      await mx.userDeviceKeysLoading;
    } catch (_) {}
    return SecureMessaging.fromClient(mx);
  }

  /// Open the setup for [client] (the reminder banner's "Fix", Settings).
  static Future<void> open(BuildContext context, MatrixClient client,
      {SecureSetupStart start = SecureSetupStart.signIn}) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _GatePage([client], start: start)));
    changed.value++;
  }

  static Future<void> maybeCheckIn(
      BuildContext context, MatrixClient client) async {
    final records = SecureSetupRecords(client.getMatrixClient().userID!);
    if (!records.checkInDue()) return;
    final status = await SecureMessaging.load(client);
    if (status.state != SecureMessagingState.ready || !context.mounted) return;
    final result = await showDialog<_CheckInResult>(
        context: context, builder: (_) => _CheckInDialog(client));
    switch (result) {
      case _CheckInResult.ok:
        await records.confirmed();
      case _CheckInResult.lost:
        if (context.mounted) {
          await open(context, client, start: SecureSetupStart.newKey);
        }
      case _CheckInResult.later:
      case null:
        await records.snoozed();
    }
  }
}

class _GatePage extends StatefulWidget {
  const _GatePage(this.clients, {this.start = SecureSetupStart.signIn});
  final List<MatrixClient> clients;
  final SecureSetupStart start;

  @override
  State<_GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<_GatePage> {
  int index = 0;
  SecureMessagingStatus? status;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (index >= widget.clients.length) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _finishing = false;
    setState(() => status = null);
    final client = widget.clients[index];
    final loaded = await SecureMessaging.load(client);
    if (!mounted) return;
    // Making or replacing a key needs a set-up, verified account.
    final needs = widget.start == SecureSetupStart.signIn
        ? loaded.needsSetup
        : loaded.state == SecureMessagingState.ready;
    if (!needs) {
      // Fine after all (e.g. approved from another device meanwhile): make
      // sure the message keys are fetched, then the next account.
      if (loaded.state == SecureMessagingState.ready) {
        unawaited(SecureSetupController(client).loadHistoryKeys());
      }
      index++;
      return _check();
    }
    setState(() => status = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) {
      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: scheme.surfaceContainer,
        child: SetupPage(children: [
          const SizedBox(height: 120),
          Center(
              child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                      strokeWidth: 4, color: scheme.primary))),
          const SizedBox(height: 22),
          SetupBody(secureGateChecking),
        ], bottom: [
          // Never trap anyone behind a slow server.
          SetupTextLink(secureGateContinueWithoutChecking,
              onTap: () => Navigator.of(context).pop()),
        ]),
      );
    }
    return SecureSetupFlow(
      key: ValueKey(index),
      client: widget.clients[index],
      status: s,
      start: widget.start,
      onFinished: (_) {
        if (_finishing) return; // a double tap must not skip an account
        _finishing = true;
        SecureSetupGate.changed.value++;
        index++;
        _check();
      },
    );
  }
}

enum _CheckInResult { ok, lost, later }

/// The check-in dialog on its own, for layout tests.
Widget checkInDialogForTest(MatrixClient client) => _CheckInDialog(client);

class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog(this.client);
  final MatrixClient client;

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  final _field = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SetupDialog(
      icon: const SetupBubbleIcon(Icons.vpn_key_outlined, size: 28),
      title: secureGateCheckInTitle,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(secureGateCheckInBody, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        AutofillGroup(
          child: TextField(
            controller: _field,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
                labelText: secureGateCheckInFieldLabel,
                errorText: error,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ]),
      buttons: [
        SetupPrimaryButton(secureGateCheckInCheck, busy: busy,
            onPressed: () async {
          setState(() {
            busy = true;
            error = null;
          });
          final ok = await SecureSetupController(widget.client)
              .checkKey(_field.text)
              .catchError((Object e) {
            Log.w("Recovery key check failed: $e");
            return false;
          });
          if (!context.mounted) return;
          if (ok) {
            Navigator.of(context).pop(_CheckInResult.ok);
            ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(SnackBar(content: Text(secureGateCheckInOk)));
          } else {
            setState(() {
              busy = false;
              error = secureGateCheckInWrong;
            });
          }
        }),
        SetupTextLink(secureGateCheckInLost,
            color: t.colorScheme.primary,
            onTap: () => Navigator.of(context).pop(_CheckInResult.lost)),
        SetupTextLink(secureGateCheckInLater,
            onTap: () => Navigator.of(context).pop(_CheckInResult.later)),
      ],
    );
  }
}

/// "Your messages aren't backed up": at the top of the room list while an
/// account skipped setup or still needs it.
class SecureSetupBanner extends StatefulWidget {
  const SecureSetupBanner({super.key});

  @override
  State<SecureSetupBanner> createState() => _SecureSetupBannerState();
}

class _SecureSetupBannerState extends State<SecureSetupBanner> {
  bool dismissed = false;
  MatrixClient? needing;

  @override
  void initState() {
    super.initState();
    SecureSetupGate.changed.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    SecureSetupGate.changed.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!SecureSetupGate.enabled) return;
    MatrixClient? found;
    for (final client in clientManager?.clients.whereType<MatrixClient>() ??
        const <MatrixClient>[]) {
      final status = await SecureSetupGate.cachedStatus(client);
      if (status.needsSetup) {
        found = client;
        break;
      }
    }
    if (mounted) setState(() => needing = found);
  }

  @override
  Widget build(BuildContext context) {
    final client = needing;
    if (dismissed || client == null || !SecureSetupGate.enabled) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: SetupCallout(
        Icons.shield_outlined,
        setupWarn,
        secureGateBannerTitle,
        secureGateBannerBody,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
              onPressed: () => SecureSetupGate.open(context, client),
              child: Text(secureGateBannerFix)),
          IconButton(
              tooltip: secureGateBannerHide,
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => dismissed = true)),
        ]),
      ),
    );
  }
}

String get secureGateChecking => Intl.message("Checking secure messaging…",
    name: "secureGateChecking",
    desc: "Shown while checking the secure messaging state at sign-in");

String get secureGateContinueWithoutChecking =>
    Intl.message("Continue without checking",
        name: "secureGateContinueWithoutChecking",
        desc: "Link that skips the secure messaging check at sign-in");

String get secureGateCheckInTitle =>
    Intl.message("Still have your recovery key?",
        name: "secureGateCheckInTitle",
        desc: "Title of the periodic recovery key check-in");

String get secureGateCheckInBody => Intl.message(
    "A quick check now and then, so you don't find out the day you need it.",
    name: "secureGateCheckInBody",
    desc: "Body of the periodic recovery key check-in");

String get secureGateCheckInFieldLabel => Intl.message("Recovery key or phrase",
    name: "secureGateCheckInFieldLabel",
    desc: "Field label in the recovery key check-in");

String get secureGateCheckInCheck => Intl.message("Check",
    name: "secureGateCheckInCheck",
    desc: "Button that checks the entered recovery key");

String get secureGateCheckInOk => Intl.message("That's the one. Keep it safe.",
    name: "secureGateCheckInOk",
    desc: "Snackbar when the entered recovery key is right");

String get secureGateCheckInWrong =>
    Intl.message("That's not it. Try your password manager.",
        name: "secureGateCheckInWrong",
        desc: "Error when the entered recovery key is wrong");

String get secureGateCheckInLost => Intl.message("I've lost it, make a new one",
    name: "secureGateCheckInLost",
    desc: "Link for users who lost their recovery key");

String get secureGateCheckInLater => Intl.message("Remind me later",
    name: "secureGateCheckInLater",
    desc: "Link that postpones the recovery key check-in");

String get secureGateBannerTitle =>
    Intl.message("Your messages aren't backed up",
        name: "secureGateBannerTitle",
        desc: "Banner title when secure messaging backup is not set up");

String get secureGateBannerBody =>
    Intl.message("Lose this device and you lose them. Takes 2 minutes.",
        name: "secureGateBannerBody",
        desc: "Banner body when secure messaging backup is not set up");

String get secureGateBannerFix => Intl.message("Fix",
    name: "secureGateBannerFix",
    desc: "Banner button that opens the secure messaging setup (short)");

String get secureGateBannerHide => Intl.message("Hide for now",
    name: "secureGateBannerHide", desc: "Tooltip of the banner close button");
