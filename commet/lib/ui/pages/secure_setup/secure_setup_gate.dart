import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/recovery_checkins_sync.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/client/matrix/ssss_repair.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/secure_setup/recovery_key_file.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_flow.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

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

  /// A setup page is open (the sign-in gate, or Settings' replace / new
  /// key): no check-in on top of it.
  static bool get setupOpen => _GatePageState._open > 0;

  static Future<void> maybeCheckIn(
      BuildContext context, MatrixClient client) async {
    final mx = client.getMatrixClient();
    final records = SecureSetupRecords(mx.userID!);
    // The schedule the user's other Vommet devices share, as far as synced
    // (stored on the device, no request): passed on another device = not
    // asked here.
    await _pull(mx, records);
    // Vommet issue 526: old-key copies wait for the user's current key, and
    // the check-in is where they type it, so it comes now instead of in up
    // to 180 days, once per pending cleanup. Local data only here; the
    // decision waits for the first sync and the confirmed state below.
    // Check-ins turned off: none at all, this one included.
    final waiting = SsssRepair.waiting(mx);
    if (!waiting && records.repairCheckInMarked) {
      await records.updateRepairCheckIn(pending: false, canCheck: false);
    }
    final bringForward =
        records.checkInsEnabled && waiting && !records.repairCheckInMarked;
    if (!records.checkInDue() && !bringForward) {
      unawaited(_shareWhenSynced(client, records));
      return;
    }
    final status = await SecureMessaging.load(client);
    if (status.state != SecureMessagingState.ready || !context.mounted) return;
    // The first sync may have brought a newer copy (passed elsewhere).
    await _pull(mx, records);
    if (bringForward && records.checkInsEnabled) {
      final action = await records.updateRepairCheckIn(
          pending: SsssRepair.waiting(mx),
          canCheck: SecureMessaging.secretStorageHasSecrets(mx));
      Log.i("Recovery key check-in for the old key cleanup: ${action.name}");
    }
    if (!records.checkInDue() || setupOpen || !context.mounted) {
      unawaited(share(mx, records));
      return;
    }
    // Put off 3 times in a row (on any device): this one waits for an
    // answer, or for check-ins to be turned off in Settings.
    final ultimatum = records.ultimatum;
    // Once the key passed it counts, however the dialog then closes.
    var passed = false;
    final result = await showDialog<_CheckInResult>(
        context: context,
        barrierDismissible: !ultimatum,
        builder: (_) => _CheckInDialog(client,
            method: records.method,
            ultimatum: ultimatum,
            onPassed: () => passed = true,
            // A wrong key: the gap goes back to 30 days after the next pass.
            onWrong: () => unawaited(
                records.resetCheckInStreak().then((_) => share(mx, records)))));
    switch (passed ? _CheckInResult.ok : result) {
      case _CheckInResult.ok:
        await records.confirmed();
        await records.confirmedRepairCheckIn();
      case _CheckInResult.lost:
        await records.resetCheckInStreak();
        unawaited(share(mx, records));
        if (context.mounted) {
          await open(context, client, start: SecureSetupStart.newKey);
        }
        return;
      case _CheckInResult.settings:
        // Still due: asked again next time, unless turned off there.
        if (context.mounted) SettingsNavigation.openRecoveryCheckIns(context);
        return;
      case _CheckInResult.later:
      case null:
        await records.snoozed();
    }
    unawaited(share(mx, records));
  }

  static Future<void> _pull(matrix.Client mx, SecureSetupRecords records) =>
      RecoveryCheckInsSync.pull(mx, records).catchError((Object e) {
        Log.w("Recovery key check-ins: couldn't read the shared copy: $e");
        return false;
      });

  /// Shares this device's check-in schedule with the user's other Vommet
  /// devices (in the background; does nothing without the backup key).
  static Future<void> share(matrix.Client mx, SecureSetupRecords records) =>
      RecoveryCheckInsSync.push(mx, records);

  /// Nothing due: still bring the shared copy and this one together once
  /// synced (the first run after an update seeds it from this device).
  static Future<void> _shareWhenSynced(
      MatrixClient client, SecureSetupRecords records) async {
    try {
      await SecureMessaging.waitForFirstSync(client)
          .timeout(const Duration(minutes: 5));
    } catch (_) {
      return;
    }
    final mx = client.getMatrixClient();
    if (mx.encryption == null) return;
    await RecoveryCheckInsSync.sync(mx, records).catchError((Object e) =>
        Log.w("Recovery key check-ins: couldn't share the schedule: $e"));
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
  /// Gate pages open right now (see [SecureSetupGate.setupOpen]).
  static int _open = 0;

  int index = 0;
  SecureMessagingStatus? status;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _open++;
    _check();
  }

  @override
  void dispose() {
    _open--;
    super.dispose();
  }

  Future<void> _check() async {
    if (index >= widget.clients.length) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _finishing = false;
    setState(() => status = null);
    final client = widget.clients[index];
    // No limit on the first sync here: this page says it's checking and
    // offers "Continue without checking". With the 30 s limit a slow device
    // gave up mid first sync and the page closed without asking anything.
    final loaded = await SecureMessaging.load(client, firstSyncTimeout: null);
    if (!mounted) return;
    // Making or replacing a key needs a set-up, verified account; the
    // "Confirm this device" ways in need an unconfirmed one (these used to
    // fall under the first rule, so the page closed again at once and the
    // buttons did nothing).
    final needs = switch (widget.start) {
      SecureSetupStart.signIn ||
      SecureSetupStart.enterKey ||
      SecureSetupStart.approve =>
        loaded.needsSetup,
      SecureSetupStart.newKey ||
      SecureSetupStart.replaceKey =>
        loaded.state == SecureMessagingState.ready,
    };
    if (!needs) {
      // Fine after all (e.g. approved from another device meanwhile): make
      // sure the message keys are fetched, then the next account.
      if (loaded.state == SecureMessagingState.ready) {
        SecureSetupController(client).startHistoryImport();
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

enum _CheckInResult { ok, lost, later, settings }

/// The check-in dialog on its own, for tests. [check] stands in for the
/// real key check, [pickFile] for the file picker (the file's text, or null
/// when nothing was picked).
Widget checkInDialogForTest(MatrixClient client,
        {Future<bool> Function(String key)? check,
        Future<String?> Function()? pickFile,
        RecoveryMethod? method,
        bool ultimatum = false,
        VoidCallback? onPassed,
        VoidCallback? onWrong}) =>
    _CheckInDialog(client,
        check: check,
        pickFile: pickFile,
        method: method,
        ultimatum: ultimatum,
        onPassed: onPassed,
        onWrong: onWrong);

/// Shows the check-in dialog for tests; the result's name ("ok", "lost",
/// "later", "settings") or null.
Future<String?> showCheckInDialogForTest(
        BuildContext context, MatrixClient client,
        {Future<bool> Function(String key)? check,
        Future<String?> Function()? pickFile,
        RecoveryMethod? method,
        bool ultimatum = false,
        VoidCallback? onPassed,
        VoidCallback? onWrong}) async =>
    (await showDialog<_CheckInResult>(
            context: context,
            barrierDismissible: !ultimatum,
            builder: (_) => _CheckInDialog(client,
                check: check,
                pickFile: pickFile,
                method: method,
                ultimatum: ultimatum,
                onPassed: onPassed,
                onWrong: onWrong)))
        ?.name;

/// The words of the check-in for each way the key was set up (null: not
/// known, e.g. set up in another app).
class _CheckInWording {
  const _CheckInWording(
      this.icon, this.title, this.ask, this.label, this.wrong);
  final IconData icon;
  final String title;

  /// What to enter, after the shared first sentence.
  final String ask;
  final String label;
  final String wrong;

  static _CheckInWording of(RecoveryMethod? method) => switch (method) {
        RecoveryMethod.key => _CheckInWording(
            Icons.vpn_key_outlined,
            secureGateCheckInTitle,
            secureGateCheckInKeyAsk,
            secureGateCheckInKeyLabel,
            secureGateCheckInKeyWrong),
        RecoveryMethod.phrase => _CheckInWording(
            Icons.psychology_outlined,
            secureGateCheckInPhraseTitle,
            secureGateCheckInPhraseAsk,
            secureGateCheckInPhraseLabel,
            secureGateCheckInPhraseWrong),
        RecoveryMethod.password => _CheckInWording(
            Icons.password,
            secureGateCheckInPasswordTitle,
            secureGateCheckInPasswordAsk,
            secureGateCheckInPasswordLabel,
            secureGateCheckInPasswordWrong),
        null => _CheckInWording(
            Icons.lock_open_outlined,
            secureGateCheckInNeutralTitle,
            secureGateCheckInNeutralAsk,
            secureSetupEnterKeyLabel,
            secureSetupErrorWrongKey),
      };
}

class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog(this.client,
      {this.check,
      this.pickFile,
      this.method,
      this.ultimatum = false,
      this.onPassed,
      this.onWrong});
  final MatrixClient client;
  final Future<bool> Function(String key)? check;
  final Future<String?> Function()? pickFile;

  /// How the key was set up: the dialog's wording.
  final RecoveryMethod? method;

  /// Put off 3 times: no "Remind me later", and it can't be dismissed.
  final bool ultimatum;

  /// Called once, as soon as the key passed.
  final VoidCallback? onPassed;

  /// The check said the key is wrong (not when the check itself failed).
  final VoidCallback? onWrong;

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  /// How long "That's the one" stays before the dialog closes by itself.
  static const _successFor = Duration(milliseconds: 1500);

  final _field = TextEditingController();
  bool busy = false;
  String? error;

  /// The wording shown: the setup method, or neutral after "Have a
  /// recovery key or key file instead?".
  late RecoveryMethod? method = widget.method;

  /// The key passed: the dialog shows its success state until it closes.
  bool passed = false;
  bool _closed = false;
  Timer? _autoClose;

  @override
  void dispose() {
    _autoClose?.cancel();
    _field.dispose();
    super.dispose();
  }

  Future<bool> _check(String key) =>
      widget.check?.call(key) ??
      // Vommet issue 526: while old-key copies wait, only the current key
      // passes (the old one would be "the one" to keep).
      SecureSetupController(widget.client).checkKey(key,
          currentKeyOnly:
              SsssRepair.pending(widget.client.getMatrixClient()) > 0);

  /// The success state's only way out (Done, the timer, back, a tap
  /// outside): closes once.
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    _autoClose?.cancel();
    Navigator.of(context).pop(_CheckInResult.ok);
  }

  /// Checks [input]. A wrong recovery password can take seconds (it's
  /// turned into a key first): the button shows it's busy meanwhile.
  Future<void> _run(String input, {required String wrong}) async {
    if (busy || passed) return;
    setState(() {
      busy = true;
      error = null;
    });
    bool? ok;
    try {
      ok = await _check(input);
    } catch (e) {
      // Not a wrong key: shown the same, but no effect on the streak.
      Log.w("Recovery key check failed: $e");
    }
    if (ok == false) widget.onWrong?.call();
    if (!mounted || passed) return;
    if (ok == true) {
      widget.onPassed?.call();
      setState(() => passed = true);
      _autoClose = Timer(_successFor, _close);
    } else {
      setState(() {
        busy = false;
        error = wrong;
      });
    }
  }

  /// "Open a file": a recovery key saved as a file (Element's
  /// recovery-key.txt, say). A key export is something else; tell so.
  Future<void> _openFile() async {
    if (busy || passed) return;
    String? text;
    try {
      text = await (widget.pickFile ?? _pickTextFile)();
    } catch (e, s) {
      Log.onError(e, s, content: "Check-in: opening a file failed");
      return;
    }
    if (text == null || !mounted) return;
    final found = RecoveryKeyFile.parse(text);
    switch (found.kind) {
      case RecoveryKeyFileKind.keyExport:
        setState(() => error = secureGateCheckInFileIsExport);
      case RecoveryKeyFileKind.none:
        setState(() => error = secureGateCheckInFileNoKey);
      case RecoveryKeyFileKind.key:
        _field.text = found.key!;
        await _run(found.key!,
            wrong: _CheckInWording.of(RecoveryMethod.key).wrong);
    }
  }

  /// The picked file's text (bytes on every platform: web has no paths).
  static Future<String?> _pickTextFile() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.firstOrNull;
    if (file == null) return null;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return null;
    // A recovery key file is a few dozen bytes; don't read a whole video.
    if (bytes.length > 1024 * 1024) return "";
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) {
    if (passed) {
      // In place of the old snack bar, which needed a Scaffold the main
      // page doesn't have. No animation, just the switch.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: SetupDialog(
          icon: const SetupBubbleIcon(Icons.check_rounded,
              color: setupGood, size: 28),
          title: secureGateCheckInOk,
          content: const SizedBox.shrink(),
          buttons: [
            SetupPrimaryButton(CommonStrings.promptDone, onPressed: _close),
          ],
        ),
      );
    }
    final t = Theme.of(context);
    final words = _CheckInWording.of(method);
    final fileOption = method == null || method == RecoveryMethod.key;
    final dialog = SetupDialog(
      icon: SetupBubbleIcon(words.icon, size: 28),
      title: words.title,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.ultimatum) ...[
          SetupCallout(Icons.snooze_outlined, t.colorScheme.primary,
              secureGateCheckInUltimatumTitle, secureGateCheckInUltimatumBody),
          const SizedBox(height: 14),
        ],
        Text(
            widget.ultimatum
                ? words.ask
                : "$secureGateCheckInBody ${words.ask}",
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        AutofillGroup(
          child: TextField(
            controller: _field,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _run(_field.text, wrong: words.wrong),
            decoration: InputDecoration(
                labelText: words.label,
                errorText: error,
                errorMaxLines: 4,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ),
        if (fileOption) ...[
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(
                onPressed: busy ? null : _openFile,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: Text(secureGateCheckInOpenFile)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(secureGateCheckInOpenFileHint,
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant))),
          ]),
        ],
      ]),
      buttons: [
        SetupPrimaryButton(secureGateCheckInCheck,
            busy: busy, onPressed: () => _run(_field.text, wrong: words.wrong)),
        if (!fileOption)
          SetupTextLink(secureGateCheckInUseKeyInstead,
              color: t.colorScheme.primary,
              onTap: busy
                  ? null
                  : () => setState(() {
                        method = null;
                        error = null;
                      })),
        SetupTextLink(secureGateCheckInLost,
            color: t.colorScheme.primary,
            onTap: () => Navigator.of(context).pop(_CheckInResult.lost)),
        if (!widget.ultimatum)
          SetupTextLink(secureGateCheckInLater,
              onTap: () => Navigator.of(context).pop(_CheckInResult.later)),
        if (widget.ultimatum) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_CheckInResult.settings),
              child: Text(secureGateCheckInUltimatumSettings,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.underline)),
            ),
          ),
        ],
      ],
    );
    // The ultimatum waits for an answer: no Escape, no back.
    return widget.ultimatum ? PopScope(canPop: false, child: dialog) : dialog;
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

String get secureGateCheckInKeyAsk => Intl.message(
    "Fill it in from your password manager.",
    name: "secureGateCheckInKeyAsk",
    desc:
        "Check-in for a recovery key kept in a password manager: what to enter");

String get secureGateCheckInKeyLabel => Intl.message("Recovery key",
    name: "secureGateCheckInKeyLabel",
    desc: "Field label in the recovery key check-in");

String get secureGateCheckInKeyWrong => Intl.message(
    "That's not it. Check your password manager has the whole key.",
    name: "secureGateCheckInKeyWrong",
    desc: "Error when the entered recovery key is wrong");

String get secureGateCheckInPhraseTitle =>
    Intl.message("Still remember your recovery phrase?",
        name: "secureGateCheckInPhraseTitle",
        desc: "Title of the check-in for a recovery phrase (6 words)");

String get secureGateCheckInPhraseAsk =>
    Intl.message("Type your 6 words in order.",
        name: "secureGateCheckInPhraseAsk",
        desc: "Check-in for a recovery phrase: what to enter");

String get secureGateCheckInPhraseLabel =>
    Intl.message("Recovery phrase (6 words)",
        name: "secureGateCheckInPhraseLabel",
        desc: "Field label in the recovery phrase check-in");

String get secureGateCheckInPhraseWrong => Intl.message(
    "That's not it. Check the words and their order. If you saved them in a password manager, look there.",
    name: "secureGateCheckInPhraseWrong",
    desc: "Error when the entered recovery phrase is wrong");

String get secureGateCheckInPasswordTitle =>
    Intl.message("Still remember your recovery password?",
        name: "secureGateCheckInPasswordTitle",
        desc: "Title of the check-in for a recovery password the user chose");

String get secureGateCheckInPasswordAsk => Intl.message(
    "It's the password you chose for your messages, not the one you sign in with.",
    name: "secureGateCheckInPasswordAsk",
    desc: "Check-in for a recovery password: what to enter");

String get secureGateCheckInPasswordLabel => Intl.message("Recovery password",
    name: "secureGateCheckInPasswordLabel",
    desc: "Field label in the recovery password check-in");

String get secureGateCheckInPasswordWrong => Intl.message(
    "That's not it. Capitals count. If you saved it in a password manager, look there.",
    name: "secureGateCheckInPasswordWrong",
    desc: "Error when the entered recovery password is wrong");

String get secureGateCheckInNeutralTitle => Intl.message(
    "Can you still unlock your messages?",
    name: "secureGateCheckInNeutralTitle",
    desc:
        "Title of the check-in when it isn't known how the recovery key was set up");

String get secureGateCheckInNeutralAsk => Intl.message(
    "Enter your recovery key, phrase, or password, whichever you set up.",
    name: "secureGateCheckInNeutralAsk",
    desc: "Check-in when the setup method isn't known: what to enter");

String get secureGateCheckInUseKeyInstead => Intl.message(
    "Have a recovery key or key file instead?",
    name: "secureGateCheckInUseKeyInstead",
    desc:
        "Link in the phrase/password check-in that switches to entering a recovery key or file");

String get secureGateCheckInOpenFile => Intl.message("Open a file",
    name: "secureGateCheckInOpenFile",
    desc: "Button in the check-in that reads a recovery key from a file");

String get secureGateCheckInOpenFileHint => Intl.message(
    "For a recovery key you saved as a file, like recovery-key.txt from Element.",
    name: "secureGateCheckInOpenFileHint",
    desc: "Hint next to the check-in's Open a file button");

String get secureGateCheckInFileIsExport => Intl.message(
    "That's a key export (a backup of message keys), not your recovery key. It can't answer this check. You can import it under Key file in Settings › Security.",
    name: "secureGateCheckInFileIsExport",
    desc: "Error when the opened file is a message key export");

String get secureGateCheckInFileNoKey =>
    Intl.message("There's no recovery key in that file.",
        name: "secureGateCheckInFileNoKey",
        desc: "Error when the opened file holds no recovery key");

String get secureGateCheckInUltimatumTitle =>
    Intl.message("You've put this off 3 times",
        name: "secureGateCheckInUltimatumTitle",
        desc: "Callout title in the check-in after 3 Remind me later in a row");

String get secureGateCheckInUltimatumBody => Intl.message(
    "So this time it waits for your answer. It only takes a moment, and it's how you find out early if your key is lost, while you can still make a new one.",
    name: "secureGateCheckInUltimatumBody",
    desc: "Callout text in the check-in after 3 Remind me later in a row");

String get secureGateCheckInUltimatumSettings => Intl.message(
    "Rather not be asked? Turn off check-ins in Settings",
    name: "secureGateCheckInUltimatumSettings",
    desc:
        "Link in the check-in that can't be put off; opens Settings › Security");

String get secureGateCheckInCheck => Intl.message("Check",
    name: "secureGateCheckInCheck",
    desc: "Button that checks the entered recovery key");

String get secureGateCheckInOk => Intl.message("That's the one. Keep it safe.",
    name: "secureGateCheckInOk",
    desc:
        "Shown in the check-in dialog when the entered recovery key is right");

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
