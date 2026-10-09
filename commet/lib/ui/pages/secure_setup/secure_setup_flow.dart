import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:commet/ui/pages/secure_setup/login_password_memory.dart';
import 'package:commet/ui/pages/secure_setup/password_strength.dart';
import 'package:commet/ui/pages/secure_setup/recovery_phrase.dart';
import 'package:commet/ui/pages/secure_setup/secure_screen.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_explainer.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

/// Why the flow was opened.
enum SecureSetupStart {
  /// Right after sign-in / at startup: the account needs setting up, or this
  /// device needs verifying.
  signIn,

  /// The check-in's "I've lost it, make a new one" (this device verified).
  newKey,
}

enum _Step {
  welcome,
  choose,
  savePm,
  confirmPm,
  phrase,
  confirmPhrase,
  ownPassword,
  confirmPassword,
  existing,
  enterKey,
  approve,
  reset,
  newKey,
  working,
  done,
}

enum _Method { passwordManager, phrase, ownPassword }

const _bitwardenUrl = "https://bitwarden.com/download/";

/// Vommet issue 129: the secure messaging setup (cross-signing + key backup
/// in plain language). The UI never says "cross-signing". [onFinished] gets
/// true once set up/verified, false when skipped.
class SecureSetupFlow extends StatefulWidget {
  const SecureSetupFlow({
    required this.client,
    required this.status,
    required this.onFinished,
    this.start = SecureSetupStart.signIn,
    super.key,
  });

  final MatrixClient client;
  final SecureMessagingStatus status;
  final SecureSetupStart start;
  final void Function(bool completed) onFinished;

  @override
  State<SecureSetupFlow> createState() => _SecureSetupFlowState();
}

class _SecureSetupFlowState extends State<SecureSetupFlow> {
  late final controller = SecureSetupController(widget.client);
  late final records = SecureSetupRecords(_userId);
  final List<_Step> _stack = [];

  _Method method = _Method.passwordManager;
  String? recoveryKey;
  RecoveryPhrase? phrase;
  (int, int) phrasePositions = (1, 4);
  String ownPassword = "";
  bool googleAutofill = false;

  String workingTitle = "";
  String workingBody = "";
  String? error;

  KeyVerification? verification;
  int _verificationGeneration = 0;

  /// Something is running: ignore further taps.
  bool busy = false;

  /// "Start over" / "make a new key": replace the identity (only then).
  bool replaceExisting = false;
  bool keepBackup = false;

  /// The current backup couldn't be kept: offer going on without it.
  bool _offerNoBackup = false;

  /// Keys were created in this flow (so "choose a different password" may
  /// replace that just-made identity).
  bool _createdHere = false;

  /// "Show my words again" on the phrase check.
  bool _showWords = false;

  /// We put the key on the clipboard ("copy it myself").
  bool _copiedKey = false;

  final _field1 = TextEditingController();
  final _field2 = TextEditingController();
  bool _showPassword = false;

  String get _userId => widget.client.getMatrixClient().userID ?? "";

  _Step get step => _stack.last;

  @override
  void initState() {
    super.initState();
    if (widget.start == SecureSetupStart.newKey) {
      replaceExisting = true;
      keepBackup = true;
    }
    _stack.add(switch (widget.start) {
      SecureSetupStart.newKey => _Step.newKey,
      SecureSetupStart.signIn =>
        widget.status.state == SecureMessagingState.thisDeviceUnverified
            ? _Step.existing
            : _Step.welcome,
    });
    SecureScreen.autofillIsGoogle().then((v) {
      if (mounted) setState(() => googleAutofill = v);
    });
  }

  @override
  void dispose() {
    _field1.dispose();
    _field2.dispose();
    _stopVerification();
    LoginPasswordMemory.forget(_userId);
    super.dispose();
  }

  void go(_Step next) => setState(() {
        error = null;
        _field1.clear();
        _field2.clear();
        _showPassword = false;
        _stack.add(next);
      });

  /// Replace the whole history with [next] (after keys exist, Back must not
  /// lead to creating them again).
  void goOnly(_Step next) => setState(() {
        error = null;
        _field1.clear();
        _field2.clear();
        _showPassword = false;
        _stack
          ..clear()
          ..add(next);
      });

  /// Cancel a pending approval without its callback touching navigation.
  void _stopVerification() {
    final request = verification;
    verification = null;
    _verificationGeneration++;
    if (request != null) {
      request.onUpdate = null;
      unawaited(request.cancel().catchError((_) {}));
    }
  }

  void back() {
    if (step == _Step.approve) return _leaveApproval();
    if (_stack.length <= 1 || step == _Step.working) return;
    setState(() {
      error = null;
      _offerNoBackup = false;
      _stack.removeLast();
      // Don't land back on a finished "working" screen.
      while (_stack.length > 1 && _stack.last == _Step.working) {
        _stack.removeLast();
      }
      // Leaving start-over: no replacing unless chosen again.
      if (step == _Step.reset ||
          step == _Step.existing ||
          step == _Step.welcome) {
        replaceExisting = widget.start == SecureSetupStart.newKey;
        keepBackup = replaceExisting;
      }
    });
  }

  void help() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SecureSetupExplainer(), fullscreenDialog: true));

  /// Show the working screen while [task] runs, then go to [then].
  Future<void> work(String title, String body, Future<void> Function() task,
      {required _Step then, bool replaceHistory = false}) async {
    if (busy) return;
    busy = true;
    go(_Step.working);
    setState(() {
      workingTitle = title;
      workingBody = body;
    });
    try {
      await task();
      if (!mounted) return;
      if (replaceHistory) {
        goOnly(then);
      } else {
        setState(() {
          _stack.removeLast(); // working
          _stack.add(then);
        });
      }
    } on ExistingSetupException {
      // It turned out to be an existing account: confirm this device.
      if (mounted) {
        goOnly(_Step.existing);
        setState(() => error = "Secure messaging is already set up on your "
            "account. Confirm this device instead.");
      }
    } on OldBackupException {
      if (mounted) {
        goOnly(_Step.existing);
        setState(() => error = "Your account has a message backup made by "
            "another app (like Element). Confirm this device there, or use "
            "\"I've lost all my devices\" to start over; the old backup "
            "would be replaced.");
      }
    } on BackupNotKeptException {
      if (mounted) {
        setState(() {
          _stack.removeLast(); // working
          _offerNoBackup = true;
          error = "This device doesn't have the key to your current message "
              "backup, so it can't be kept with a new key. Messages on this "
              "device stay readable.";
        });
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Secure messaging setup failed");
      if (!mounted) return;
      setState(() {
        _stack.removeLast(); // working
        error = e is WrongRecoveryKeyException
            ? "That didn't work. Check for typos, or try your recovery key "
                "if you used a phrase (or the other way round)."
            : "Something went wrong. Try again. ($e)";
      });
    } finally {
      busy = false;
    }
  }

  Future<void> createKeys({String? passphrase, required _Step then}) => work(
          "Setting up secure messaging",
          "Creating your keys. This takes a few seconds.", () async {
        recoveryKey = await controller.setUpNew(
            passphrase: passphrase,
            replaceExisting: replaceExisting,
            keepBackup: keepBackup);
        _createdHere = true;
      }, then: then, replaceHistory: true);

  /// Setup confirmed. [checkIns]: schedule "Still have your recovery key?"
  /// (not for a device approved from another one: its user may never have
  /// held the key, and the check-in's "lost it" makes a new identity).
  Future<void> finished({bool checkIns = true}) async {
    if (checkIns) {
      await records.confirmed(firstTime: true);
    } else {
      await records.setSkipped(false);
    }
    LoginPasswordMemory.forget(_userId);
    // A key we copied for the password manager doesn't stay on the
    // clipboard once it's confirmed saved.
    if (_copiedKey) {
      try {
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        if (clip?.text?.trim() == recoveryKey) {
          await Clipboard.setData(const ClipboardData(text: ""));
        }
      } catch (_) {}
    }
    if (mounted) goOnly(_Step.done);
  }

  // ---------- skipping ----------

  Future<void> skip() async {
    final first = await showDialog<bool>(
        context: context, builder: (c) => const _SkipDialog1());
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
        context: context, builder: (c) => const _SkipDialog2());
    if (second != true || !mounted) return;
    await records.setSkipped(true);
    LoginPasswordMemory.forget(_userId);
    if (mounted) widget.onFinished(false);
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final page = switch (step) {
      _Step.welcome => welcome(),
      _Step.choose => choose(),
      _Step.savePm => savePm(),
      _Step.confirmPm => confirmKey(),
      _Step.phrase => phraseScreen(),
      _Step.confirmPhrase => confirmPhrase(),
      _Step.ownPassword => ownPasswordScreen(),
      _Step.confirmPassword => confirmPassword(),
      _Step.existing => existing(),
      _Step.enterKey => enterKey(),
      _Step.approve => approve(),
      _Step.reset => reset(),
      _Step.newKey => newKey(),
      _Step.working => working(),
      _Step.done => done(),
    };
    const secretSteps = {
      _Step.savePm,
      _Step.confirmPm,
      _Step.phrase,
      _Step.confirmPhrase,
      _Step.ownPassword,
      _Step.confirmPassword,
      _Step.enterKey,
    };
    final secret = secretSteps.contains(step);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (step == _Step.done) {
          widget.onFinished(true);
        } else {
          back();
        }
      },
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: secret
            ? ScreenshotGuard(setSecure: SecureScreen.setSecure, child: page)
            : page,
      ),
    );
  }

  VoidCallback? get onBack => _stack.length > 1 ? back : null;

  Widget errorText() => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Column(children: [
            Text(error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_offerNoBackup)
              SetupTextLink("Make the new key without the old backup",
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => setState(() {
                        keepBackup = false;
                        _offerNoBackup = false;
                        error = null;
                      })),
          ]),
        );

  // New account ------------------------------------------------------------

  Widget welcome() => SetupPage(
        onHelp: help,
        step: 0,
        children: [
          const SizedBox(height: 12),
          const SetupBubbleIcon(Icons.lock_outline, size: 40),
          const SizedBox(height: 22),
          const SetupTitle("Keep your messages safe"),
          const SizedBox(height: 12),
          const SetupBody(
              "Your private messages are locked on your device. Nobody else "
              "can read them, not even the people who run the server. Most "
              "chat apps can read everything you send."),
          const SizedBox(height: 10),
          const SetupBody(
              "That's because only you hold the keys, and keeping them safe "
              "is your job. It takes 2 minutes, and we'll walk you through "
              "it."),
          const SizedBox(height: 22),
          for (final s in const [
            "Read your messages on a new phone or computer",
            "Keep your history if you reinstall or lose a device",
            "Show others that this device is really you",
          ])
            SetupBullet(s, icon: Icons.check_circle, color: setupGood),
          errorText(),
        ],
        bottom: [
          SetupPrimaryButton("Set up  ·  about 2 minutes",
              onPressed: () => go(_Step.choose)),
          SetupTextLink("What does this mean?",
              onTap: help, color: Theme.of(context).colorScheme.primary),
          SetupTextLink("Skip for now", onTap: skip),
        ],
      );

  Widget choose() => SetupPage(
        onBack: onBack,
        onHelp: help,
        step: 1,
        children: [
          const SetupTitle("How do you want to save your recovery key?"),
          const SizedBox(height: 8),
          const SetupBody(
              "It gets you back into your messages if you lose all your "
              "devices."),
          const SizedBox(height: 16),
          const SetupCallout(
              Icons.key,
              setupWarn,
              "Treat it like your house key",
              "Together with your password, it lets someone read your whole "
                  "message history and impersonate you. Store it encrypted. A "
                  "password manager is best."),
          const SizedBox(height: 14),
          SetupOption(
              Icons.vpn_key_outlined,
              "Save in an encrypted password manager",
              "Bitwarden on any device, or iCloud Keychain on Apple. Only you "
                  "can open them",
              badge: "RECOMMENDED · ENCRYPTED",
              selected: method == _Method.passwordManager,
              onTap: () => setState(() => method = _Method.passwordManager)),
          SetupOption(
              Icons.psychology_outlined,
              "Use a memorable phrase",
              "6 easy words to keep in your head. Best saved in a password "
                  "manager too",
              selected: method == _Method.phrase,
              onTap: () => setState(() => method = _Method.phrase)),
          SetupOption(
              Icons.password,
              "Choose my own password",
              "Something long that only you know. Save it in a password "
                  "manager too",
              selected: method == _Method.ownPassword,
              onTap: () => setState(() => method = _Method.ownPassword)),
          errorText(),
        ],
        bottom: [
          SetupPrimaryButton("Continue", busy: busy, onPressed: () async {
            if (busy) return;
            switch (method) {
              case _Method.passwordManager:
                await createKeys(then: _Step.savePm);
              case _Method.phrase:
                phrase = await RecoveryPhrase.generate();
                if (mounted) go(_Step.phrase);
              case _Method.ownPassword:
                go(_Step.ownPassword);
            }
          }),
        ],
      );

  Widget bitwardenCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: const Color(0xff175ddc),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.shield, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("No password manager yet?",
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
                "The Vommet developers recommend Bitwarden. It's free, "
                "end-to-end encrypted and works on every device.",
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
        TextButton(
            onPressed: () => LinkUtils.open(Uri.parse(_bitwardenUrl)),
            child: const Text("Get it")),
      ]),
    );
  }

  Widget googleCaveat() => const SetupCallout(
      Icons.cloud_outlined,
      setupWarn,
      "Your phone saves passwords to Google",
      "Google can read what's saved there unless you've turned on on-device "
          "encryption. For your recovery key, use an end-to-end encrypted "
          "password manager instead.");

  Widget savePm() => SetupPage(
        onBack: onBack,
        onHelp: help,
        step: 2,
        children: [
          const SetupTitle("Save it in your password manager"),
          const SizedBox(height: 8),
          const SetupBody(
              "Tap Save and your password manager will offer to keep it."),
          const SizedBox(height: 16),
          RecoveryKeyText(recoveryKey ?? "",
              label: "Recovery key for $_userId"),
          _AutofillSaver(
              username: "Recovery key for $_userId",
              secret: recoveryKey ?? "",
              key: const ValueKey("autofill-saver")),
          const SizedBox(height: 14),
          if (googleAutofill) ...[googleCaveat(), const SizedBox(height: 12)],
          bitwardenCard(),
        ],
        bottom: [
          if (_AutofillSaver.supported) ...[
            SetupPrimaryButton("Save", icon: Icons.vpn_key_outlined,
                onPressed: () async {
              await _AutofillSaver.save();
              if (mounted) go(_Step.confirmPm);
            }),
            SetupTextLink("I'll copy it into my password manager myself",
                onTap: copyKey),
          ] else
            SetupPrimaryButton("Copy it for my password manager",
                icon: Icons.copy, onPressed: copyKey),
        ],
      );

  /// Copy the key for pasting into a password manager. The confirm step
  /// clears the clipboard, so the check really comes from the manager.
  Future<void> copyKey() async {
    await Clipboard.setData(ClipboardData(text: recoveryKey ?? ""));
    _copiedKey = true;
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text("Copied. Paste it into your password manager and save "
            "it there. We clear the clipboard once it's checked.")));
    go(_Step.confirmPm);
  }

  Widget confirmKey() => SetupPage(
        onBack: onBack,
        onHelp: help,
        step: 3,
        children: [
          const SetupTitle("Let's check it saved"),
          const SizedBox(height: 8),
          const SetupBody(
              "Fill in your recovery key from your password manager. This "
              "proves you can get it back when you need it."),
          const SizedBox(height: 22),
          AutofillGroup(
            child: Column(children: [
              _hiddenUsername(),
              TextField(
                controller: _field1,
                autofillHints: const [AutofillHints.password],
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "Recovery key",
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                      tooltip: "Paste",
                      icon: const Icon(Icons.content_paste),
                      onPressed: () => _paste(_field1)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          errorText(),
          SetupBody("Can't find it? Go back and save it again. That's fine.",
              align: TextAlign.center),
        ],
        bottom: [
          SetupPrimaryButton("Check", onPressed: () {
            final typed = _field1.text.replaceAll(RegExp(r"\s"), "");
            final want = (recoveryKey ?? "").replaceAll(RegExp(r"\s"), "");
            if (typed.isNotEmpty && typed == want) {
              finished();
            } else {
              setState(() => error =
                  "That's not the same key. Check your password manager has "
                      "the whole key.");
            }
          }),
        ],
      );

  Widget _hiddenUsername() => Offstage(
        child: TextField(
          controller: TextEditingController(text: "Recovery key for $_userId"),
          autofillHints: const [AutofillHints.username],
        ),
      );

  Future<void> _paste(TextEditingController c) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) c.text = data!.text!.trim();
  }

  Widget phraseScreen() {
    final p = phrase!;
    final scheme = Theme.of(context).colorScheme;
    return SetupPage(
      onBack: onBack,
      onHelp: help,
      step: 2,
      children: [
        const SetupTitle("Your recovery phrase"),
        const SizedBox(height: 8),
        const SetupBody("Remember these 6 words in order. Best: save them in "
            "a password manager too."),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16)),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < p.words.length; i++)
              Container(
                width: 150,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Text("${i + 1}",
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  Text(p.words[i],
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
        Center(
          child: TextButton.icon(
              onPressed: () async {
                final next = await RecoveryPhrase.generate();
                if (mounted) setState(() => phrase = next);
              },
              icon: const Icon(Icons.refresh),
              label: const Text("Different words")),
        ),
        _AutofillSaver(
            username: "Recovery phrase for $_userId",
            secret: p.passphrase,
            key: ValueKey(p.passphrase)),
        OutlinedButton.icon(
            onPressed: _AutofillSaver.save,
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text("Save to password manager")),
        const SizedBox(height: 8),
        const SetupBody(
            "Writing them down? Paper isn't encrypted, so keep it locked "
            "away."),
        const SizedBox(height: 12),
        SetupCallout(
            Icons.remove_circle_outline,
            scheme.error,
            "Never send it to anyone",
            "With these words and your password, anyone can read your message "
                "history and impersonate you. Nobody from Vommet or your "
                "server will ever ask for them."),
        const SizedBox(height: 10),
        const SetupCallout(
            Icons.no_photography_outlined,
            setupWarn,
            "Don't screenshot it",
            "Photos sync to the cloud and get shared by accident."),
        if (googleAutofill) ...[const SizedBox(height: 10), googleCaveat()],
        errorText(),
      ],
      bottom: [
        SetupPrimaryButton("I've got them", busy: busy, onPressed: () async {
          phrasePositions = RecoveryPhrase.confirmPositions();
          await createKeys(passphrase: p.passphrase, then: _Step.confirmPhrase);
        }),
      ],
    );
  }

  Widget confirmPhrase() {
    final (a, b) = phrasePositions;
    return SetupPage(
      onBack: onBack,
      onHelp: help,
      step: 3,
      children: [
        const SetupTitle("Let's check you saved it"),
        const SizedBox(height: 8),
        const SetupBody(
            "Without looking at the last screen, type these words from your "
            "phrase."),
        const SizedBox(height: 22),
        if (!_showWords) ...[
          _plainField(_field1, "Word ${a + 1}"),
          _plainField(_field2, "Word ${b + 1}"),
        ],
        errorText(),
        if (_showWords) ...[
          const SetupBody("Save them this time, then hide them and type the "
              "two words."),
          const SizedBox(height: 10),
        ],
        if (_showWords)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                [
                  for (var i = 0; i < phrase!.words.length; i++)
                    "${i + 1} ${phrase!.words[i]}"
                ].join("   "),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          )
        else
          SetupTextLink("Lost them already? Show my words again",
              color: Theme.of(context).colorScheme.primary,
              onTap: () => setState(() => _showWords = true)),
      ],
      bottom: [
        if (_showWords)
          SetupPrimaryButton("Hide them, I've saved them",
              onPressed: () => setState(() {
                    _showWords = false;
                    _field1.clear();
                    _field2.clear();
                  }))
        else
          SetupPrimaryButton("Check", onPressed: () {
            if (phrase!.matches(a, _field1.text) &&
                phrase!.matches(b, _field2.text)) {
              finished();
            } else {
              setState(() => error = "Those aren't the right words.");
            }
          }),
      ],
    );
  }

  Widget _plainField(TextEditingController c, String label,
          {bool obscure = false, Widget? suffix, List<String>? hints}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: hints,
          decoration: InputDecoration(
              labelText: label,
              filled: true,
              suffixIcon: suffix,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );

  Widget ownPasswordScreen() {
    final scheme = Theme.of(context).colorScheme;
    final score = PasswordStrength.score(ownPassword);
    final reused = LoginPasswordMemory.isLoginPassword(_userId, ownPassword);
    final colors = [
      scheme.error,
      setupWarn,
      setupWarn,
      setupGood,
      setupGood,
    ];
    return SetupPage(
      onBack: onBack,
      onHelp: help,
      step: 2,
      children: [
        const SetupTitle("Choose a recovery password"),
        const SizedBox(height: 8),
        const SetupBody("Long and memorable beats short and clever. A short "
            "sentence works well."),
        const SizedBox(height: 18),
        AutofillGroup(
          child: Column(children: [
            Offstage(
              child: TextField(
                  controller: TextEditingController(
                      text: "Recovery password for $_userId"),
                  autofillHints: const [AutofillHints.username]),
            ),
            TextField(
              controller: _field1,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (v) => setState(() => ownPassword = v),
              decoration: InputDecoration(
                labelText: "Recovery password",
                filled: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                    tooltip: _showPassword ? "Hide" : "Show",
                    icon: Icon(_showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword)),
              ),
            ),
          ]),
        ),
        if (ownPassword.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Container(
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i < score.clamp(1, 4)
                        ? colors[score]
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          Text(PasswordStrength.labels[score],
              style: TextStyle(color: colors[score])),
        ],
        const SizedBox(height: 14),
        if (reused == true) ...[
          SetupCallout(
              Icons.warning_amber_rounded,
              scheme.error,
              "This is your login password",
              "If you use the same one, anyone who gets your login password "
                  "can also read your private messages. Pick something "
                  "different."),
          const SizedBox(height: 12),
        ],
        const SetupCallout(
            Icons.psychology_alt_outlined,
            setupWarn,
            "People forget these",
            "A password you only use here is easy to forget, and then your "
                "messages are gone. Save it in a password manager like "
                "Bitwarden too."),
        const SizedBox(height: 12),
        bitwardenCard(),
        errorText(),
      ],
      bottom: [
        SetupPrimaryButton("Continue",
            busy: busy,
            onPressed:
                !PasswordStrength.acceptable(ownPassword) || reused == true
                    ? null
                    : () async {
                        TextInput.finishAutofillContext();
                        await createKeys(
                            passphrase: ownPassword.trim(),
                            then: _Step.confirmPassword);
                      }),
      ],
    );
  }

  Widget confirmPassword() => SetupPage(
        onBack: onBack,
        onHelp: help,
        step: 3,
        children: [
          const SetupTitle("Type it once more"),
          const SizedBox(height: 8),
          const SetupBody(
              "Your recovery password, from memory or your password manager. "
              "This makes sure there's no typo in it."),
          const SizedBox(height: 22),
          _plainField(_field1, "Recovery password",
              obscure: true, hints: const [AutofillHints.password]),
          errorText(),
          SetupTextLink("Forgot it already? Choose a different password",
              color: Theme.of(context).colorScheme.primary,
              onTap: busy || !_createdHere
                  ? null
                  : () {
                      // Replaces only the identity this flow just made.
                      replaceExisting = true;
                      ownPassword = "";
                      goOnly(_Step.ownPassword);
                    }),
        ],
        bottom: [
          SetupPrimaryButton("Check", onPressed: () {
            if (_field1.text.trim() == ownPassword.trim()) {
              finished();
            } else {
              setState(() => error = "That's not the same password.");
            }
          }),
        ],
      );

  // Existing account ---------------------------------------------------------

  Widget existing() => SetupPage(
        title: "Signing in",
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          const SetupBubbleIcon(Icons.phonelink_lock, size: 40),
          const SizedBox(height: 18),
          const SetupTitle("Is this you?"),
          const SizedBox(height: 8),
          const SetupBody("You've used secure messaging before. Confirm this "
              "new device so it can read your messages."),
          const SizedBox(height: 22),
          SetupOption(Icons.devices_other, "Approve from another device",
              "Open the app on your phone or computer and tap Approve",
              badge: "EASIEST", selected: true, onTap: () => startApproval()),
          SetupOption(Icons.key, "Enter recovery key or phrase",
              "Or let your password manager fill it in",
              onTap: () => go(_Step.enterKey)),
          errorText(),
        ],
        bottom: [
          SetupTextLink("I've lost all my devices and my recovery key",
              onTap: () => go(_Step.reset),
              color: Theme.of(context).colorScheme.error),
          SetupTextLink("Skip for now", onTap: skip),
        ],
      );

  Widget enterKey() => SetupPage(
        title: "Signing in",
        onBack: onBack,
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          const SetupBubbleIcon(Icons.key, size: 36),
          const SizedBox(height: 18),
          const SetupTitle("Enter your recovery key"),
          const SizedBox(height: 8),
          const SetupBody("Or your recovery phrase or password, if you chose "
              "one. Your password manager can fill it in."),
          const SizedBox(height: 22),
          AutofillGroup(
            child: Column(children: [
              _hiddenUsername(),
              _plainField(_field1, "Recovery key, phrase or password",
                  obscure: !_showPassword,
                  hints: const [AutofillHints.password],
                  suffix: IconButton(
                      tooltip: "Paste",
                      icon: const Icon(Icons.content_paste),
                      onPressed: () => _paste(_field1))),
            ]),
          ),
          errorText(),
          SetupTextLink("Where do I find it?",
              color: Theme.of(context).colorScheme.primary,
              onTap: () => LinkUtils.open(Uri.parse(
                  "https://vommet.app/help/secure-messaging#saving-your-key"))),
        ],
        bottom: [
          SetupPrimaryButton("Unlock my messages", onPressed: () {
            final input = _field1.text;
            if (input.trim().isEmpty) return;
            work(
                "Unlocking your messages",
                "Fetching the keys to your message history. This can take a "
                    "minute on a big account.", () async {
              await controller.unlockExisting(input);
              await records.confirmed(firstTime: true);
              LoginPasswordMemory.forget(_userId);
            }, then: _Step.done);
          }),
        ],
      );

  Future<void> startApproval() async {
    if (busy || verification != null || step == _Step.approve) return;
    go(_Step.approve);
    final generation = ++_verificationGeneration;
    try {
      final mx = widget.client.getMatrixClient();
      final keys = mx.userDeviceKeys[mx.userID];
      if (keys == null) throw StateError("Our device list isn't loaded");
      final request = await keys.startVerification();
      if (!mounted || generation != _verificationGeneration) {
        unawaited(request.cancel().catchError((_) {}));
        return;
      }
      request.onUpdate = () {
        if (!mounted || generation != _verificationGeneration) return;
        if (request.state == KeyVerificationState.done) {
          request.onUpdate = null;
          verification = null;
          _verificationGeneration++;
          onApproved();
        } else if (request.state == KeyVerificationState.error) {
          _approvalFailed("The approval was cancelled or failed. Try again, "
              "or use your recovery key.");
        } else {
          setState(() {});
        }
      };
      setState(() => verification = request);
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't start device approval");
      if (mounted && generation == _verificationGeneration) {
        _approvalFailed(
            "Couldn't reach your other devices. Try your recovery key.");
      }
    }
  }

  void _approvalFailed(String message) {
    _stopVerification();
    setState(() {
      if (step == _Step.approve) _stack.removeLast();
      error = message;
    });
  }

  void _leaveApproval({_Step? to}) {
    _stopVerification();
    setState(() {
      if (step == _Step.approve) _stack.removeLast();
      if (to != null) _stack.add(to);
      error = null;
    });
  }

  void onApproved() {
    // The other device sends our secrets after approving; fetch the message
    // keys once the backup key arrives (now or later).
    work(
        "Unlocking your messages",
        "Fetching the keys to your message history. This can take a minute "
            "on a big account.", () async {
      final mx = widget.client.getMatrixClient();
      for (var i = 0; i < 20; i++) {
        if (await mx.encryption?.keyManager.isCached() == true) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      if (await mx.encryption?.keyManager.isCached() == true) {
        await controller.loadHistoryKeys();
      } else {
        controller.loadHistoryKeysWhenBackupKeyArrives();
      }
      // No check-ins: this device was approved; its user may never have
      // held the recovery key.
      await records.setSkipped(false);
      LoginPasswordMemory.forget(_userId);
    }, then: _Step.done, replaceHistory: true);
  }

  Widget approve() {
    final request = verification;
    final waiting = request == null ||
        request.state == KeyVerificationState.waitingAccept ||
        request.state == KeyVerificationState.askChoice;
    if (!waiting) {
      return Column(children: [
        SizedBox(
          height: 52,
          child: Row(children: [
            IconButton(
                onPressed: () => _leaveApproval(),
                icon: const Icon(Icons.arrow_back)),
          ]),
        ),
        Expanded(child: MatrixVerificationPage(request: request)),
      ]);
    }
    final scheme = Theme.of(context).colorScheme;
    return SetupPage(
      title: "Signing in",
      onBack: () => _leaveApproval(),
      onHelp: help,
      children: [
        const SizedBox(height: 30),
        const SetupBubbleIcon(Icons.devices_other, size: 40),
        const SizedBox(height: 18),
        const SetupTitle("Approve on your other device"),
        const SizedBox(height: 10),
        const SetupBody(
            "Open Vommet (or another Matrix app) on a phone or computer "
            "you're already signed in to. A request to approve this device "
            "will pop up there."),
        const SizedBox(height: 26),
        Center(
            child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: scheme.primary))),
        const SizedBox(height: 10),
        const SetupBody("Waiting for your other device…"),
      ],
      bottom: [
        SetupTextLink("Use my recovery key instead",
            onTap: () => _leaveApproval(to: _Step.enterKey)),
      ],
    );
  }

  Widget reset() => SetupPage(
        title: "Signing in",
        onBack: onBack,
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          SetupBubbleIcon(Icons.restart_alt,
              color: Theme.of(context).colorScheme.error, size: 38),
          const SizedBox(height: 18),
          const SetupTitle("Start over with a new key?"),
          const SizedBox(height: 10),
          const SetupBody("Only do this if you've lost every signed-in device "
              "AND your recovery key."),
          const SizedBox(height: 18),
          const SetupBullet(
              "Your old private messages stay locked. Nobody can unlock them, "
              "not even your server's admins"),
          const SetupBullet(
              "People you talk to will see that your secure identity changed"),
          const SetupBullet("Your other signed-in devices (if any turn up) "
              "will need approving again"),
          const SizedBox(height: 16),
          const SetupCallout(
              Icons.lightbulb_outline,
              setupWarn,
              "Check first",
              "An old phone in a drawer, or a laptop that's still signed in, "
                  "can approve this device and keep everything."),
        ],
        bottom: [
          HoldButton("Hold to start over", onHeld: () {
            // The only path besides "make a new key" that may replace an
            // existing identity; the old backup can't be opened anyway.
            replaceExisting = true;
            keepBackup = false;
            go(_Step.choose);
          }),
          const SizedBox(height: 4),
          SetupTextLink("Go back", onTap: back),
        ],
      );

  Widget newKey() => SetupPage(
        title: "Recovery key",
        onBack: () => widget.onFinished(false),
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          const SetupBubbleIcon(Icons.key_off_outlined,
              color: setupWarn, size: 36),
          const SizedBox(height: 18),
          const SetupTitle("Make a new recovery key"),
          const SizedBox(height: 10),
          const SetupBody("Good news: this device still has your messages, so "
              "nothing is lost. A new key backs them up again."),
          const SizedBox(height: 18),
          const SetupBullet(
              "Your old key stops working. If anyone finds it, it's useless"),
          const SetupBullet("People you talk to will see your secure identity "
              "changed. It's still you; you can tell them why"),
          const SetupBullet(
              "Your other signed-in devices need approving again"),
        ],
        bottom: [
          HoldButton("Hold to make a new key", onHeld: () => go(_Step.choose)),
          SetupTextLink("Go back", onTap: () => widget.onFinished(false)),
        ],
      );

  // Shared -------------------------------------------------------------------

  Widget working() {
    final scheme = Theme.of(context).colorScheme;
    return SetupPage(children: [
      const SizedBox(height: 90),
      Center(
          child: SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                  strokeWidth: 4, color: scheme.primary))),
      const SizedBox(height: 26),
      SetupTitle(workingTitle),
      const SizedBox(height: 10),
      SetupBody(workingBody),
    ]);
  }

  Widget done() => SetupPage(
        onHelp: help,
        children: [
          const SizedBox(height: 40),
          const SetupBubbleIcon(Icons.verified_user,
              color: setupGood, size: 48),
          const SizedBox(height: 22),
          const SetupTitle("You're all set"),
          const SizedBox(height: 12),
          const SetupBody("Secure messaging is on. Your messages are backed up "
              "and only you can unlock them."),
          const SizedBox(height: 26),
          SetupCallout(
              Icons.devices,
              Theme.of(context).colorScheme.primary,
              "Signing in somewhere else?",
              "Just approve it from this device. You'll only need your "
                  "recovery key if you lose every device."),
        ],
        bottom: [
          SetupPrimaryButton("Start chatting",
              onPressed: () => widget.onFinished(true)),
        ],
      );
}

/// Offers [username] + [secret] to the system password manager (Android
/// autofill / Apple Keychain) when [save] is called.
class _AutofillSaver extends StatefulWidget {
  const _AutofillSaver(
      {required this.username, required this.secret, super.key});
  final String username;
  final String secret;

  static final _focus = FocusNode();

  /// Android and Apple platforms offer to save; desktop has no such API.
  static bool get supported =>
      PlatformUtils.isAndroid ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static Future<void> save() async {
    _focus.requestFocus();
    await Future.delayed(const Duration(milliseconds: 150));
    TextInput.finishAutofillContext(shouldSave: true);
    _focus.unfocus();
  }

  @override
  State<_AutofillSaver> createState() => _AutofillSaverState();
}

class _AutofillSaverState extends State<_AutofillSaver> {
  late final _user = TextEditingController(text: widget.username);
  late final _secret = TextEditingController(text: widget.secret);

  @override
  void dispose() {
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Laid out but invisible: the platform only offers to save fields that
    // exist in the autofill context.
    return SizedBox(
      height: 1,
      child: Opacity(
        opacity: 0,
        child: AutofillGroup(
          child: Row(children: [
            Expanded(
                child: TextField(
                    controller: _user,
                    autofillHints: const [AutofillHints.username])),
            Expanded(
                child: TextField(
                    controller: _secret,
                    focusNode: _AutofillSaver._focus,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword])),
          ]),
        ),
      ),
    );
  }
}

class _SkipDialog1 extends StatelessWidget {
  const _SkipDialog1();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, size: 40, color: setupWarn),
      title: const Text("Skip secure messaging?"),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Without it:", style: t.textTheme.bodyLarge),
            const SizedBox(height: 8),
            const SetupBullet(
                "You can lose your private message history for good"),
            const SetupBullet("Messages may not show on your other devices"),
            const SetupBullet(
                "People you talk to will see this device as unconfirmed"),
          ]),
      actions: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SetupPrimaryButton("Go back and set up",
              onPressed: () => Navigator.of(context).pop(false)),
          SetupTextLink("Skip anyway",
              onTap: () => Navigator.of(context).pop(true)),
        ]),
      ],
    );
  }
}

class _SkipDialog2 extends StatelessWidget {
  const _SkipDialog2();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.report_outlined, size: 40, color: t.colorScheme.error),
      title: const Text("This is for developers"),
      content: const Text(
          "If you don't know exactly why you're skipping this, you almost "
          "certainly don't want to. Nobody, not even your server's admins, "
          "can recover messages you lose this way.",
          textAlign: TextAlign.center),
      actions: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SetupPrimaryButton("Take me back",
              onPressed: () => Navigator.of(context).pop(false)),
          const SizedBox(height: 12),
          HoldButton("Hold to skip",
              onHeld: () => Navigator.of(context).pop(true)),
          const SizedBox(height: 6),
          Text("You can set it up later in Settings › Security.",
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ]),
      ],
    );
  }
}
