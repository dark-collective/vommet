// Vommet issue 72: signing out warns first when this is the account's last
// device with its message keys, and offers ways to keep them: check the
// recovery key (message backup on), or save a key file / turn on backup.
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/client/matrix/ssss_repair.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_flow.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/ui/pages/settings/categories/account/account_management/sign_out_check.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_page.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/key_file/key_file_row.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SignOutDialog extends StatefulWidget {
  const SignOutDialog(this.client,
      {this.load,
      this.checkKey,
      this.saveKeyFile,
      this.setUpBackup,
      this.method,
      super.key});
  final Client client;

  /// Stand-ins for tests: the sessions check, the recovery key check, the
  /// key file export (true = saved) and the backup setup.
  final Future<SignOutAssessment> Function()? load;
  final Future<bool> Function(String input)? checkKey;
  final Future<bool> Function(BuildContext context)? saveKeyFile;
  final Future<void> Function(BuildContext context)? setUpBackup;

  /// How the recovery key was set up (the field's label); null = not known.
  final RecoveryMethod? method;

  static const confirmKey = ValueKey("SIGN_OUT_DIALOG_CONFIRM");

  /// Asks before signing [client] out; true = sign out.
  static Future<bool> show(BuildContext context, Client client) async {
    final name = client.self?.identifier ?? "";
    final result = await AdaptiveDialog.show<bool>(context,
        title: signOutDialogTitle(name), builder: (_) => SignOutDialog(client));
    return result == true;
  }

  @override
  State<SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends State<SignOutDialog> {
  final _field = TextEditingController();
  SignOutAssessment? assessment;
  bool keysSaved = false;
  bool understood = false;
  bool keyPassed = false;
  bool skipCheck = false;
  bool checking = false;
  String? keyError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => assessment = null);
    final client = widget.client;
    final result = await (widget.load?.call() ??
        (client is MatrixClient
            ? SignOutCheck.load(client)
            : Future.value(const SignOutAssessment(SignOutCase.plain))));
    if (mounted) setState(() => assessment = result);
  }

  RecoveryMethod? get _method {
    if (widget.method != null || widget.load != null) return widget.method;
    try {
      final client = widget.client;
      if (client is! MatrixClient) return null;
      final userId = client.getMatrixClient().userID;
      return userId == null ? null : SecureSetupRecords(userId).method;
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkKey() async {
    if (checking || _field.text.trim().isEmpty) return;
    setState(() {
      checking = true;
      keyError = null;
    });
    bool ok = false;
    try {
      ok = await (widget.checkKey?.call(_field.text) ?? _realCheck());
    } catch (e) {
      Log.w("Sign-out recovery key check failed: $e");
    }
    if (!mounted) return;
    setState(() {
      checking = false;
      keyPassed = ok;
      keyError = ok ? null : secureSetupErrorWrongKey;
    });
  }

  Future<bool> _realCheck() async {
    final client = widget.client as MatrixClient;
    return SecureSetupController(client).checkKey(_field.text,
        currentKeyOnly: SsssRepair.pending(client.getMatrixClient()) > 0);
  }

  Future<void> _saveKeyFile() async {
    final saved = await (widget.saveKeyFile?.call(context) ??
        AdaptiveDialog.show<bool>(context,
            title: keyFileExportTitle,
            dismissible: false,
            builder: (_) => KeyExportDialog(widget.client as MatrixClient)));
    if (saved == true && mounted) setState(() => keysSaved = true);
  }

  Future<void> _setUpBackup() async {
    if (widget.setUpBackup != null) {
      await widget.setUpBackup!(context);
    } else {
      final client = widget.client as MatrixClient;
      if (SecureSetupGate.enabled && SecureMessaging.of(client).needsSetup) {
        await SecureSetupGate.open(context, client,
            start: SecureSetupStart.signIn);
      } else {
        await AdaptiveDialog.show(context,
            builder: (_) => MatrixCrossSigningPage(
                  client: client,
                  onComplete: () {},
                  mode: MatrixCrossSigningMode.enableBackup,
                ),
            dismissible: true,
            title: signOutTurnOnBackup);
      }
    }
    // Backup may be on now: the warning changes to the recovery key check.
    if (mounted) await _load();
  }

  bool get canSignOut => switch (assessment?.kind) {
        null => false,
        SignOutCase.plain || SignOutCase.otherSession => true,
        SignOutCase.lastDeviceBackedUp =>
          keyPassed || keysSaved || (skipCheck && understood),
        SignOutCase.lastDeviceNoBackup => keysSaved || understood,
      };

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (a == null) _loading(context) else ..._content(context, a),
            const SizedBox(height: 16),
            _buttons(a),
          ],
        ),
      ),
    );
  }

  Widget _loading(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 12),
          Flexible(child: tiamat.Text.labelLow(signOutChecking)),
        ]),
      );

  List<Widget> _content(BuildContext context, SignOutAssessment a) {
    final t = Theme.of(context);
    final quiet =
        t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    switch (a.kind) {
      case SignOutCase.plain:
        return [];
      case SignOutCase.otherSession:
        final keeper = a.keeper!;
        return [
          Text(signOutKeysOnOtherSession),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                border: Border.all(color: t.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(keeper.displayName ?? keeper.deviceId,
                  style: t.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.circle, size: 9, color: setupGood),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                      signOutKeeperDetail(sessionLastSeenLabel(
                          keeper.lastSeen?.millisecondsSinceEpoch,
                          DateTime.now())),
                      style: quiet),
                ),
              ]),
            ]),
          ),
        ];
      case SignOutCase.lastDeviceBackedUp:
        return [
          keysSaved
              ? SetupCallout(Icons.check_circle_outline, setupGood,
                  signOutKeysSavedTitle, signOutKeysSavedBody)
              : SetupCallout(Icons.warning_amber_rounded, setupWarn,
                  signOutLastDeviceTitle, signOutBackedUpBody),
          const SizedBox(height: 16),
          if (keyPassed)
            Row(children: [
              const Icon(Icons.check, color: setupGood, size: 18),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(signOutKeyPassed,
                      style: const TextStyle(color: setupGood))),
            ])
          else if (!skipCheck && !keysSaved) ...[
            TextField(
              controller: _field,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _checkKey(),
              decoration: InputDecoration(
                  labelText: signOutKeyLabel(_method),
                  errorText: keyError,
                  errorMaxLines: 4,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: tiamat.Button.secondary(
                  text: signOutCheckKey, isLoading: checking, onTap: _checkKey),
            ),
          ],
          if (!keysSaved)
            Align(
              alignment: Alignment.centerLeft,
              child: SetupTextLink(signOutSaveKeyFileToo,
                  color: t.colorScheme.primary, onTap: _saveKeyFile),
            ),
          if (skipCheck && !keyPassed && !keysSaved) _understood(),
          if (!skipCheck && !keyPassed && !keysSaved)
            Align(
              alignment: Alignment.centerLeft,
              child: SetupTextLink(signOutWithoutChecking,
                  onTap: () => setState(() => skipCheck = true)),
            ),
        ];
      case SignOutCase.lastDeviceNoBackup:
        return [
          keysSaved
              ? SetupCallout(Icons.check_circle_outline, setupGood,
                  signOutKeysSavedTitle, signOutKeysSavedBody)
              : SetupCallout(Icons.warning_amber_rounded, t.colorScheme.error,
                  signOutLastDeviceTitle, signOutNoBackupBody),
          const SizedBox(height: 16),
          if (!keysSaved) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(signOutSaveKeysHeader.toUpperCase(),
                  style: t.textTheme.labelMedium?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700)),
            ),
            SetupOption(Icons.file_download_outlined, signOutSaveKeyFile,
                signOutSaveKeyFileBody,
                selected: true, onTap: _saveKeyFile),
            SetupOption(Icons.cloud_upload_outlined, signOutTurnOnBackup,
                signOutTurnOnBackupBody,
                onTap: _setUpBackup),
            Text(signOutKeyFileNote, style: quiet),
            const SizedBox(height: 8),
            _understood(),
          ],
        ];
    }
  }

  Widget _understood() => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: understood,
        onChanged: (v) => setState(() => understood = v ?? false),
        title: Text(signOutUnderstood),
      );

  Widget _buttons(SignOutAssessment? a) {
    final anyway = !keysSaved &&
        !keyPassed &&
        (a?.kind == SignOutCase.lastDeviceNoBackup ||
            (a?.kind == SignOutCase.lastDeviceBackedUp && skipCheck));
    final enabled = canSignOut;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        tiamat.Button.secondary(
            text: CommonStrings.promptCancel,
            onTap: () => Navigator.of(context).pop(false)),
        IgnorePointer(
          ignoring: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: tiamat.Button.danger(
                key: SignOutDialog.confirmKey,
                text: anyway ? signOutAnyway : signOutConfirm,
                onTap: () => Navigator.of(context).pop(true)),
          ),
        ),
      ],
    );
  }
}

String signOutDialogTitle(String account) =>
    Intl.message("Sign out of $account?",
        args: [account],
        name: "signOutDialogTitle",
        desc: "Title of the dialog asking before signing out of an account");

String get signOutChecking => Intl.message("Checking your other sessions…",
    name: "signOutChecking",
    desc:
        "Sign-out dialog: shown while it looks for the account's other sessions");

String get signOutKeysOnOtherSession => Intl.message(
    "Your keys stay safe on your other session:",
    name: "signOutKeysOnOtherSession",
    desc:
        "Sign-out dialog when another verified session was used recently; the session is shown below");

String signOutKeeperDetail(String lastSeen) => Intl.message(
    "Verified · $lastSeen",
    args: [lastSeen],
    name: "signOutKeeperDetail",
    desc:
        "Sign-out dialog: the other session's state, e.g. 'Verified · Active 2 hours ago'");

String get signOutLastDeviceTitle => Intl.message(
    "This is your last signed-in device",
    name: "signOutLastDeviceTitle",
    desc:
        "Sign-out dialog warning title: no other recently used, verified session");

String get signOutNoBackupBody => Intl.message(
    "If you sign out without saving your keys, you will permanently lose your past encrypted messages. Nobody, not even your server, can recover them.",
    name: "signOutNoBackupBody",
    desc:
        "Sign-out warning when this is the last device and there is no message backup");

String get signOutBackedUpBody => Intl.message(
    "Your messages are backed up. To read them again after you sign in, you'll need your recovery key. Check it now.",
    name: "signOutBackedUpBody",
    desc:
        "Sign-out warning when this is the last device but message backup is on");

String get signOutKeysSavedTitle => Intl.message("Your keys are saved",
    name: "signOutKeysSavedTitle",
    desc: "Sign-out dialog after a key file was saved");

String get signOutKeysSavedBody => Intl.message(
    "Keep the file and its passphrase safe. You'll need both to read your past messages.",
    name: "signOutKeysSavedBody",
    desc: "Sign-out dialog after a key file was saved");

String get signOutSaveKeysHeader => Intl.message(
    "Before you go, save your keys",
    name: "signOutSaveKeysHeader",
    desc: "Sign-out dialog: header above the ways to keep the message keys");

String get signOutSaveKeyFile => Intl.message("Save a key file",
    name: "signOutSaveKeyFile",
    desc: "Sign-out dialog option: export the message keys to a file");

String get signOutSaveKeyFileBody =>
    Intl.message("Locked with a passphrase. Imports into Element too.",
        name: "signOutSaveKeyFileBody",
        desc: "Sign-out dialog: what the key file option does");

String get signOutTurnOnBackup => Intl.message("Turn on message backup",
    name: "signOutTurnOnBackup",
    desc: "Sign-out dialog option: set up the online message backup");

String get signOutTurnOnBackupBody =>
    Intl.message("Your recovery key unlocks your history anywhere.",
        name: "signOutTurnOnBackupBody",
        desc: "Sign-out dialog: what the message backup option does");

String get signOutKeyFileNote => Intl.message(
    "A key file covers your messages up to now. Message backup keeps covering new ones after you sign in again.",
    name: "signOutKeyFileNote",
    desc:
        "Sign-out dialog: the difference between a key file and message backup");

String get signOutUnderstood =>
    Intl.message("I understand I'll lose my encrypted messages",
        name: "signOutUnderstood",
        desc: "Sign-out dialog tick box needed before 'Sign out anyway'");

String signOutKeyLabel(RecoveryMethod? method) => switch (method) {
      RecoveryMethod.key => signOutKeyLabelKey,
      RecoveryMethod.phrase => signOutKeyLabelPhrase,
      RecoveryMethod.password => signOutKeyLabelPassword,
      null => signOutKeyLabelAny,
    };

String get signOutKeyLabelKey => Intl.message("Your recovery key",
    name: "signOutKeyLabelKey",
    desc: "Sign-out dialog: field for the recovery key");

String get signOutKeyLabelPhrase => Intl.message("Your recovery phrase",
    name: "signOutKeyLabelPhrase",
    desc: "Sign-out dialog: field for the recovery phrase");

String get signOutKeyLabelPassword => Intl.message("Your recovery password",
    name: "signOutKeyLabelPassword",
    desc: "Sign-out dialog: field for the recovery password");

String get signOutKeyLabelAny => Intl.message(
    "Your recovery key, phrase, or password",
    name: "signOutKeyLabelAny",
    desc:
        "Sign-out dialog: field for the recovery key when it isn't known how it was set up");

String get signOutCheckKey => Intl.message("Check",
    name: "signOutCheckKey",
    desc: "Sign-out dialog: button that checks the entered recovery key");

String get signOutKeyPassed =>
    Intl.message("That's your current recovery key. You're all set.",
        name: "signOutKeyPassed",
        desc: "Sign-out dialog: the entered recovery key is right");

String get signOutSaveKeyFileToo => Intl.message("Save a key file too",
    name: "signOutSaveKeyFileToo",
    desc: "Sign-out dialog link: export the message keys as well");

String get signOutWithoutChecking => Intl.message("Sign out without checking…",
    name: "signOutWithoutChecking",
    desc:
        "Sign-out dialog link: skip the recovery key check (asks for the tick box)");

String get signOutConfirm => Intl.message("Sign out",
    name: "signOutConfirm", desc: "Sign-out dialog: the button that signs out");

String get signOutAnyway => Intl.message("Sign out anyway",
    name: "signOutAnyway",
    desc: "Sign-out dialog: signs out although the keys weren't saved");
