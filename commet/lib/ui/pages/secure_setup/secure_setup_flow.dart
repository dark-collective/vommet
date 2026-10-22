import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/recovery_checkins_sync.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:commet/ui/pages/secure_setup/change_password.dart';
import 'package:commet/ui/pages/secure_setup/login_password_memory.dart';
import 'package:commet/ui/pages/secure_setup/password_strength.dart';
import 'package:commet/ui/pages/secure_setup/recovery_phrase.dart';
import 'package:commet/ui/pages/secure_setup/secure_screen.dart';
import 'package:commet/telemetry/secure_unlock_telemetry.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_explainer.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/recovery_key_clipboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:intl/intl.dart';

/// Why the flow was opened.
enum SecureSetupStart {
  /// Right after sign-in / at startup: the account needs setting up, or this
  /// device needs verifying.
  signIn,

  /// The check-in's "I've lost it, make a new one" (this device verified).
  newKey,

  /// Settings › Security › "Replace my recovery key" (this device
  /// verified): choose between replacing it and locking someone out.
  replaceKey,

  /// Settings › Security › "Confirm this device" › "Enter recovery key":
  /// straight to the key step (Back leads to the other ways in).
  enterKey,

  /// Settings › Security › "Confirm this device" › "Use another device
  /// instead": straight into approval from a signed-in device.
  approve,
}

/// How new keys are made in this flow.
enum _Mode {
  /// New account (or start over / new key: see replaceExisting).
  setUp,

  /// Same identity, the current key moved to a new one.
  replace,

  /// New key, new identity, new backup; then change the password.
  lockOut,
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
  replaceChooser,
  replaceCurrent,
  lockOutIntro,
  changePassword,
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
  _Mode mode = _Mode.setUp;

  /// "Replace my recovery key": the current key/phrase/password, checked.
  String? _currentInput;

  /// The chooser's selection: true = someone may have used it.
  bool _lockOutChosen = false;
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

  /// Watches for this device being confirmed some other way, e.g. a
  /// verification started from Element, which finishes in its own dialog.
  StreamSubscription<SecureMessagingStatus>? _statusSub;

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

  /// The key we put on the clipboard ("copy it myself"), to take off again.
  String? _copiedKey;

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
      SecureSetupStart.replaceKey => _Step.replaceChooser,
      SecureSetupStart.signIn ||
      SecureSetupStart.enterKey ||
      SecureSetupStart.approve =>
        widget.status.state == SecureMessagingState.thisDeviceUnverified
            ? _Step.existing
            : _Step.welcome,
    });
    if (widget.status.state == SecureMessagingState.thisDeviceUnverified) {
      if (widget.start == SecureSetupStart.enterKey) _stack.add(_Step.enterKey);
      if (widget.start == SecureSetupStart.approve) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) startApproval();
        });
      }
    }
    SecureScreen.autofillIsGoogle().then((v) {
      if (mounted) setState(() => googleAutofill = v);
    });
    _statusSub =
        SecureMessaging.watchConfirmation(widget.client).listen(_onStatus);
  }

  /// Confirmed elsewhere while waiting here (a verification another device
  /// started, approved in its own dialog): carry on as if approved here,
  /// instead of still asking for the recovery key.
  void _onStatus(SecureMessagingStatus status) {
    Log.i("Secure setup: status ${status.state.name} "
        "(step ${step.name}, busy $busy, mounted $mounted)");
    if (!mounted || busy || status.state != SecureMessagingState.ready) return;
    if (step != _Step.existing &&
        step != _Step.enterKey &&
        step != _Step.approve) {
      return;
    }
    Log.i("Secure messaging setup: this device was confirmed elsewhere");
    _stopVerification();
    onApproved();
  }

  @override
  void dispose() {
    _field1.dispose();
    _field2.dispose();
    _statusSub?.cancel();
    _stopVerification();
    LoginPasswordMemory.forget(_userId);
    // Leaving setup any other way than finished() (skip, closing the page)
    // mustn't leave the recovery key on the clipboard either.
    unawaited(RecoveryKeyClipboard.clearIfHolds(_copiedKey));
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
      // A finished one stays finished (cancelling it would tell the other
      // device the approval failed).
      if (request.state != KeyVerificationState.done) {
        unawaited(request.cancel().catchError((_) {}));
      }
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
      Log.i("Secure setup: \"$title\" done (mounted: $mounted, "
          "steps: ${_stack.map((e) => e.name).join(" > ")})");
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
        setState(() => error = secureSetupErrorAlreadySetUp);
      }
    } on OldBackupException {
      if (mounted) {
        goOnly(_Step.existing);
        setState(() => error = secureSetupErrorOldBackup);
      }
    } on BackupNotKeptException {
      if (mounted) {
        setState(() {
          _stack.removeLast(); // working
          _offerNoBackup = true;
          error = secureSetupErrorBackupNotKept;
        });
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Secure messaging setup failed");
      if (!mounted) return;
      setState(() {
        _stack.removeLast(); // working
        error = switch (e) {
          WrongRecoveryKeyException() => secureSetupErrorWrongKey,
          MalformedRecoveryKeyException() => secureSetupErrorMalformedKey,
          NothingToUnlockException() => secureSetupErrorNothingToUnlock,
          _ => secureSetupErrorGeneric(e.toString()),
        };
      });
    } finally {
      busy = false;
    }
  }

  Future<void> createKeys({String? passphrase, required _Step then}) =>
      work(secureSetupWorkingCreateTitle, secureSetupWorkingCreateBody,
          () async {
        if (_createdHere && recoveryKey != null) {
          // A different password/phrase right after making keys here: move
          // them to the new one (same identity, no second change).
          recoveryKey =
              await controller.replaceKey(recoveryKey!, passphrase: passphrase);
        } else {
          recoveryKey = switch (mode) {
            _Mode.setUp => await controller.setUpNew(
                passphrase: passphrase,
                replaceExisting: replaceExisting,
                keepBackup: keepBackup),
            _Mode.replace => await controller.replaceKey(_currentInput!,
                passphrase: passphrase),
            _Mode.lockOut => await controller.lockOut(passphrase: passphrase),
          };
        }
        _createdHere = true;
      }, then: then, replaceHistory: true);

  /// Setup confirmed: "Still have your recovery key?" check-ins start over
  /// (the first in 3 days), worded for how the key is kept, and the
  /// schedule is shared with the user's other Vommet devices.
  Future<void> finished() async {
    await records.setUp(
        method: switch (method) {
      _Method.passwordManager => RecoveryMethod.key,
      _Method.phrase => RecoveryMethod.phrase,
      _Method.ownPassword => RecoveryMethod.password,
    });
    _shareCheckIns();
    LoginPasswordMemory.forget(_userId);
    // A key we copied for the password manager doesn't stay on the
    // clipboard once it's confirmed saved.
    await RecoveryKeyClipboard.clearIfHolds(_copiedKey);
    _copiedKey = null;
    if (mounted) {
      goOnly(mode == _Mode.lockOut ? _Step.changePassword : _Step.done);
    }
  }

  /// Brings this device's check-in schedule and the shared one together
  /// (in the background; needs the backup key, which may come later after
  /// an approval: then the next start does it).
  void _shareCheckIns() {
    final mx = widget.client.getMatrixClient();
    unawaited(RecoveryCheckInsSync.sync(mx, records).catchError((Object e) =>
        Log.w("Recovery key check-ins: couldn't share the schedule: $e")));
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
      _Step.replaceChooser => replaceChooser(),
      _Step.replaceCurrent => replaceCurrent(),
      _Step.lockOutIntro => lockOutIntro(),
      _Step.changePassword => changePassword(),
    };
    const secretSteps = {
      _Step.savePm,
      _Step.confirmPm,
      _Step.phrase,
      _Step.confirmPhrase,
      _Step.ownPassword,
      _Step.confirmPassword,
      _Step.enterKey,
      _Step.replaceCurrent,
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
              SetupTextLink(secureSetupWithoutOldBackup,
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
          SetupTitle(secureSetupIntroTitle),
          const SizedBox(height: 12),
          SetupBody(secureSetupIntroBody1),
          const SizedBox(height: 10),
          SetupBody(secureSetupIntroBody2),
          const SizedBox(height: 22),
          for (final s in [
            secureSetupIntroBenefit1,
            secureSetupIntroBenefit2,
            secureSetupIntroBenefit3,
          ])
            SetupBullet(s, icon: Icons.check_circle, color: setupGood),
          errorText(),
        ],
        bottom: [
          SetupPrimaryButton(secureSetupIntroStart,
              onPressed: () => go(_Step.choose)),
          SetupTextLink(secureSetupWhatDoesThisMean,
              onTap: help, color: Theme.of(context).colorScheme.primary),
          SetupTextLink(secureSetupSkipForNow, onTap: skip),
        ],
      );

  Widget choose() => SetupPage(
        onBack: onBack,
        onHelp: help,
        step: 1,
        children: [
          SetupTitle(secureSetupChooseTitle),
          const SizedBox(height: 8),
          SetupBody(secureSetupChooseBody),
          const SizedBox(height: 16),
          SetupCallout(Icons.key, setupWarn, secureSetupChooseWarningTitle,
              secureSetupChooseWarningBody),
          const SizedBox(height: 14),
          SetupOption(Icons.vpn_key_outlined, secureSetupOptionManager,
              secureSetupOptionManagerDetail,
              badge: secureSetupOptionManagerBadge,
              selected: method == _Method.passwordManager,
              onTap: () => setState(() => method = _Method.passwordManager)),
          SetupOption(Icons.psychology_outlined, secureSetupOptionPhrase,
              secureSetupOptionPhraseDetail,
              selected: method == _Method.phrase,
              onTap: () => setState(() => method = _Method.phrase)),
          SetupOption(Icons.password, secureSetupOptionPassword,
              secureSetupOptionPasswordDetail,
              selected: method == _Method.ownPassword,
              onTap: () => setState(() => method = _Method.ownPassword)),
          errorText(),
        ],
        bottom: [
          SetupPrimaryButton(secureSetupContinue, busy: busy,
              onPressed: () async {
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
            Text(secureSetupNoManagerTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(secureSetupNoManagerBody,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
        TextButton(
            onPressed: () => LinkUtils.open(Uri.parse(_bitwardenUrl)),
            child: Text(secureSetupNoManagerGetIt)),
      ]),
    );
  }

  Widget googleCaveat() => SetupCallout(Icons.cloud_outlined, setupWarn,
      secureSetupGoogleCaveatTitle, secureSetupGoogleCaveatBody);

  Widget savePm() => SetupPage(
        onBack: onBack,
        onHelp: help,
        step: 2,
        children: [
          SetupTitle(secureSetupSaveKeyTitle),
          const SizedBox(height: 8),
          SetupBody(secureSetupSaveKeyBody),
          const SizedBox(height: 16),
          RecoveryKeyText(recoveryKey ?? "",
              label: secureSetupRecoveryKeyFor(_userId)),
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
            SetupPrimaryButton(secureSetupSave, icon: Icons.vpn_key_outlined,
                onPressed: () async {
              await _AutofillSaver.save();
              if (mounted) go(_Step.confirmPm);
            }),
            SetupTextLink(secureSetupCopyMyself, onTap: copyKey),
          ] else
            SetupPrimaryButton(secureSetupCopyForManager,
                icon: Icons.copy, onPressed: copyKey),
        ],
      );

  /// A snack bar where there's a Scaffold to show it: the setup at sign-in
  /// has none, and the messenger would only show it later on another page
  /// (asserting in debug builds).
  void _snack(String text) {
    if (Scaffold.maybeOf(context) == null) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Copy the key for pasting into a password manager. It comes off the
  /// clipboard again when setup finishes or is left.
  Future<void> copyKey() async {
    await Clipboard.setData(ClipboardData(text: recoveryKey ?? ""));
    _copiedKey = recoveryKey;
    if (!mounted) return;
    _snack(secureSetupCopiedSnack);
    go(_Step.confirmPm);
  }

  Widget confirmKey() => SetupPage(
        onBack: onBack,
        onHelp: help,
        step: 3,
        children: [
          SetupTitle(secureSetupCheckKeyTitle),
          const SizedBox(height: 8),
          SetupBody(secureSetupCheckKeyBody),
          const SizedBox(height: 22),
          AutofillGroup(
            child: Column(children: [
              _hiddenUsername(),
              TextField(
                controller: _field1,
                autofillHints: const [AutofillHints.password],
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: secureSetupRecoveryKeyLabel,
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                      tooltip: secureSetupPaste,
                      icon: const Icon(Icons.content_paste),
                      onPressed: () => _paste(_field1)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          errorText(),
          SetupBody(secureSetupCheckKeyCantFind, align: TextAlign.center),
        ],
        bottom: [
          SetupPrimaryButton(secureSetupCheck, onPressed: () {
            final typed = _field1.text.replaceAll(RegExp(r"\s"), "");
            final want = (recoveryKey ?? "").replaceAll(RegExp(r"\s"), "");
            if (typed.isNotEmpty && typed == want) {
              finished();
            } else {
              setState(() => error = secureSetupCheckKeyMismatch);
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
        SetupTitle(secureSetupPhraseTitle),
        const SizedBox(height: 8),
        SetupBody(secureSetupPhraseBody),
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
              label: Text(secureSetupPhraseDifferentWords)),
        ),
        _AutofillSaver(
            username: "Recovery phrase for $_userId",
            secret: p.passphrase,
            key: ValueKey(p.passphrase)),
        // Vommet: desktop has no save-to-password-manager API (the button
        // did nothing on Windows/Linux), so copying is offered everywhere.
        Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_AutofillSaver.supported)
                OutlinedButton.icon(
                    onPressed: _AutofillSaver.save,
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: Text(secureSetupPhraseSaveToManager)),
              OutlinedButton.icon(
                  onPressed: () => copyPhrase(p.passphrase),
                  icon: const Icon(Icons.copy),
                  label: Text(secureSetupPhraseCopy)),
            ]),
        const SizedBox(height: 8),
        SetupBody(secureSetupPhrasePaperWarning),
        const SizedBox(height: 12),
        SetupCallout(Icons.remove_circle_outline, scheme.error,
            secureSetupPhraseNeverSendTitle, secureSetupPhraseNeverSendBody),
        const SizedBox(height: 10),
        SetupCallout(
            Icons.no_photography_outlined,
            setupWarn,
            secureSetupPhraseNoScreenshotTitle,
            secureSetupPhraseNoScreenshotBody),
        if (googleAutofill) ...[const SizedBox(height: 10), googleCaveat()],
        errorText(),
      ],
      bottom: [
        SetupPrimaryButton(secureSetupPhraseGotThem, busy: busy,
            onPressed: () async {
          phrasePositions = RecoveryPhrase.confirmPositions();
          await createKeys(passphrase: p.passphrase, then: _Step.confirmPhrase);
        }),
      ],
    );
  }

  /// Copy the words for pasting into a password manager. Like the key,
  /// they come off the clipboard again when setup finishes or is left.
  Future<void> copyPhrase(String passphrase) async {
    await Clipboard.setData(ClipboardData(text: passphrase));
    _copiedKey = passphrase;
    if (!mounted) return;
    _snack(secureSetupPhraseCopiedSnack);
  }

  Widget confirmPhrase() {
    final (a, b) = phrasePositions;
    return SetupPage(
      onBack: onBack,
      onHelp: help,
      step: 3,
      children: [
        SetupTitle(secureSetupCheckPhraseTitle),
        const SizedBox(height: 8),
        SetupBody(secureSetupCheckPhraseBody),
        const SizedBox(height: 22),
        if (!_showWords) ...[
          _plainField(_field1, secureSetupPhraseWordLabel(a + 1)),
          _plainField(_field2, secureSetupPhraseWordLabel(b + 1)),
        ],
        errorText(),
        if (_showWords) ...[
          SetupBody(secureSetupCheckPhraseSaveAgain),
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
          SetupTextLink(secureSetupCheckPhraseShowAgain,
              color: Theme.of(context).colorScheme.primary,
              onTap: () => setState(() => _showWords = true)),
      ],
      bottom: [
        if (_showWords)
          SetupPrimaryButton(secureSetupCheckPhraseHide,
              onPressed: () => setState(() {
                    _showWords = false;
                    _field1.clear();
                    _field2.clear();
                  }))
        else
          SetupPrimaryButton(secureSetupCheck, onPressed: () {
            if (phrase!.matches(a, _field1.text) &&
                phrase!.matches(b, _field2.text)) {
              finished();
            } else {
              setState(() => error = secureSetupCheckPhraseWrong);
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
        SetupTitle(secureSetupPasswordTitle),
        const SizedBox(height: 8),
        SetupBody(secureSetupPasswordBody),
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
                labelText: secureSetupRecoveryPasswordLabel,
                filled: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                    tooltip: _showPassword ? secureSetupHide : secureSetupShow,
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
          SetupCallout(Icons.warning_amber_rounded, scheme.error,
              secureSetupPasswordIsLoginTitle, secureSetupPasswordIsLoginBody),
          const SizedBox(height: 12),
        ],
        SetupCallout(Icons.psychology_alt_outlined, setupWarn,
            secureSetupPasswordForgetTitle, secureSetupPasswordForgetBody),
        const SizedBox(height: 12),
        bitwardenCard(),
        errorText(),
      ],
      bottom: [
        SetupPrimaryButton(secureSetupContinue,
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
          SetupTitle(secureSetupCheckPasswordTitle),
          const SizedBox(height: 8),
          SetupBody(secureSetupCheckPasswordBody),
          const SizedBox(height: 22),
          _plainField(_field1, secureSetupRecoveryPasswordLabel,
              obscure: true, hints: const [AutofillHints.password]),
          errorText(),
          SetupTextLink(secureSetupCheckPasswordForgot,
              color: Theme.of(context).colorScheme.primary,
              onTap: busy || !_createdHere
                  ? null
                  : () {
                      // Moves the keys just made here to a new password.
                      ownPassword = "";
                      goOnly(_Step.ownPassword);
                    }),
        ],
        bottom: [
          SetupPrimaryButton(secureSetupCheck, onPressed: () {
            if (_field1.text.trim() == ownPassword.trim()) {
              finished();
            } else {
              setState(() => error = secureSetupCheckPasswordMismatch);
            }
          }),
        ],
      );

  // Existing account ---------------------------------------------------------

  Widget existing() => SetupPage(
        title: secureSetupSigningIn,
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          const SetupBubbleIcon(Icons.phonelink_lock, size: 40),
          const SizedBox(height: 18),
          SetupTitle(secureSetupExistingTitle),
          const SizedBox(height: 8),
          SetupBody(secureSetupExistingBody),
          const SizedBox(height: 22),
          SetupOption(Icons.devices_other, secureSetupExistingApprove,
              secureSetupExistingApproveDetail,
              badge: secureSetupExistingApproveBadge,
              selected: true,
              onTap: () => startApproval()),
          SetupOption(Icons.key, secureSetupExistingEnterKey,
              secureSetupExistingEnterKeyDetail,
              onTap: () => go(_Step.enterKey)),
          errorText(),
        ],
        bottom: [
          SetupTextLink(secureSetupExistingLostAll,
              onTap: () => go(_Step.reset),
              color: Theme.of(context).colorScheme.error),
          SetupTextLink(secureSetupSkipForNow, onTap: skip),
        ],
      );

  Widget enterKey() => SetupPage(
        title: secureSetupSigningIn,
        onBack: onBack,
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          const SetupBubbleIcon(Icons.key, size: 36),
          const SizedBox(height: 18),
          SetupTitle(secureSetupEnterKeyTitle),
          const SizedBox(height: 8),
          SetupBody(secureSetupEnterKeyBody),
          const SizedBox(height: 22),
          AutofillGroup(
            child: Column(children: [
              _hiddenUsername(),
              _plainField(_field1, secureSetupEnterKeyLabel,
                  obscure: !_showPassword,
                  hints: const [AutofillHints.password],
                  suffix: IconButton(
                      tooltip: secureSetupPaste,
                      icon: const Icon(Icons.content_paste),
                      onPressed: () => _paste(_field1))),
            ]),
          ),
          errorText(),
          SetupTextLink(secureSetupEnterKeyWhere,
              color: Theme.of(context).colorScheme.primary,
              onTap: () => LinkUtils.open(Uri.parse(
                  "https://vommet.app/help/secure-messaging#saving-your-key"))),
        ],
        bottom: [
          SetupPrimaryButton(secureSetupEnterKeyUnlock, onPressed: () {
            final input = _field1.text;
            if (input.trim().isEmpty) return;
            work(secureSetupWorkingUnlockTitle, secureSetupWorkingUnlockBody,
                () async {
              final clock = Stopwatch()..start();
              final steps = UnlockSteps();
              final path = SecureSetupController.looksLikeRecoveryKey(input)
                  ? "recovery_key"
                  : "passphrase";
              try {
                await controller.unlockExisting(input, steps: steps);
                // The key was entered right: a passed check-in.
                await RecoveryCheckInsSync.pull(
                        widget.client.getMatrixClient(), records)
                    .catchError((Object _) => false);
                await records.confirmed();
                _shareCheckIns();
                LoginPasswordMemory.forget(_userId);
              } catch (e) {
                SecureUnlockTelemetry.unlock(
                    path: path,
                    screenMs: clock.elapsedMilliseconds,
                    steps: steps,
                    error: e);
                rethrow;
              }
              SecureUnlockTelemetry.unlock(
                  path: path,
                  screenMs: clock.elapsedMilliseconds,
                  steps: steps);
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
      // Right after signing in the SDK may not have our device list yet
      // (it used to load the member lists of every encrypted room first,
      // minutes on a big account): ask the server for it here.
      final keys = await SecureMessaging.ownDeviceList(mx);
      if (!mounted || generation != _verificationGeneration) return;
      if (keys == null) throw StateError("Our device list couldn't be loaded");
      // The request only goes to devices our identity signed; with none,
      // nothing would ever arrive anywhere.
      if (SecureMessaging.approvingDevices(mx, keys).isEmpty) {
        Log.w("Device approval: no other confirmed device "
            "(${keys.deviceKeys.length} devices known)");
        _approvalFailed(secureSetupApprovalNoDevice);
        return;
      }
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
          Log.w("Device approval failed: ${request.canceledCode} "
              "(${request.canceledReason})");
          _approvalFailed(
              secureSetupApprovalFailedCode(request.canceledCode ?? "unknown"));
        } else {
          setState(() {});
        }
      };
      setState(() => verification = request);
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't start device approval");
      if (mounted && generation == _verificationGeneration) {
        _approvalFailed(secureSetupApprovalUnreachable);
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
    // The other device sends our secrets after approving; the message keys
    // are fetched in the background once the backup key is here (now or
    // later).
    work(secureSetupWorkingUnlockTitle, secureSetupWorkingUnlockBody, () async {
      final clock = Stopwatch()..start();
      final mx = widget.client.getMatrixClient();
      // Our list with the other device's signature, and the secrets if the
      // verification itself didn't ask for them (it can't when it ended on
      // the other device, or ours failed to check the other's keys).
      try {
        await SecureMessaging.finishConfirmation(mx);
      } catch (e, s) {
        Log.onError(e, s, content: "Couldn't finish device approval");
      }
      final finishMs = clock.elapsedMilliseconds;
      // The message history comes in the background: the screen doesn't
      // wait for the backup key or for the import (minutes on a big
      // account).
      if (mx.encryption != null) {
        controller.loadHistoryKeysWhenBackupKeyArrives();
      }
      // Approved, not a pass (its user may never have held the key): this
      // device takes the schedule the user's other devices share, if any.
      await records.setSkipped(false);
      _shareCheckIns();
      LoginPasswordMemory.forget(_userId);
      SecureUnlockTelemetry.unlock(
          path: "approval",
          screenMs: clock.elapsedMilliseconds,
          finishMs: finishMs);
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
      title: secureSetupSigningIn,
      onBack: () => _leaveApproval(),
      onHelp: help,
      children: [
        const SizedBox(height: 30),
        const SetupBubbleIcon(Icons.devices_other, size: 40),
        const SizedBox(height: 18),
        SetupTitle(secureSetupApproveTitle),
        const SizedBox(height: 10),
        SetupBody(secureSetupApproveBody),
        const SizedBox(height: 26),
        Center(
            child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: scheme.primary))),
        const SizedBox(height: 10),
        SetupBody(secureSetupApproveWaiting),
      ],
      bottom: [
        SetupTextLink(secureSetupApproveUseKey,
            onTap: () => _leaveApproval(to: _Step.enterKey)),
      ],
    );
  }

  Widget reset() => SetupPage(
        title: secureSetupSigningIn,
        onBack: onBack,
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          SetupBubbleIcon(Icons.restart_alt,
              color: Theme.of(context).colorScheme.error, size: 38),
          const SizedBox(height: 18),
          SetupTitle(secureSetupResetTitle),
          const SizedBox(height: 10),
          SetupBody(secureSetupResetBody),
          const SizedBox(height: 18),
          SetupBullet(secureSetupResetBullet1),
          SetupBullet(secureSetupResetBullet2),
          SetupBullet(secureSetupResetBullet3),
          const SizedBox(height: 16),
          SetupCallout(Icons.lightbulb_outline, setupWarn,
              secureSetupResetCheckFirstTitle, secureSetupResetCheckFirstBody),
        ],
        bottom: [
          HoldButton(secureSetupResetHold, onHeld: () {
            // The only path besides "make a new key" that may replace an
            // existing identity; the old backup can't be opened anyway.
            replaceExisting = true;
            keepBackup = false;
            go(_Step.choose);
          }),
          const SizedBox(height: 4),
          SetupTextLink(secureSetupGoBack, onTap: back),
        ],
      );

  Widget newKey() => SetupPage(
        title: secureSetupRecoveryKeyLabel,
        onBack: () => widget.onFinished(false),
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          const SetupBubbleIcon(Icons.key_off_outlined,
              color: setupWarn, size: 36),
          const SizedBox(height: 18),
          SetupTitle(secureSetupNewKeyTitle),
          const SizedBox(height: 10),
          SetupBody(secureSetupNewKeyBody),
          const SizedBox(height: 18),
          SetupBullet(secureSetupNewKeyBullet1),
          SetupBullet(secureSetupNewKeyBullet2),
          SetupBullet(secureSetupNewKeyBullet3),
        ],
        bottom: [
          HoldButton(secureSetupNewKeyHold, onHeld: () => go(_Step.choose)),
          SetupTextLink(secureSetupGoBack,
              onTap: () => widget.onFinished(false)),
        ],
      );

  // Replace the recovery key (Settings › Security) ------------------------

  Widget compareRow(String label, String a, String b, {Color? bColor}) {
    final t = Theme.of(context);
    Widget cell(String text, {Color? color}) => Expanded(
        child: Text(text,
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall?.copyWith(
                color: color ?? t.colorScheme.onSurface,
                fontWeight: FontWeight.w600)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
            width: 108,
            child: Text(label,
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant))),
        cell(a),
        cell(b, color: bColor),
      ]),
    );
  }

  Widget replaceChooser() {
    final t = Theme.of(context);
    return SetupPage(
      title: secureSetupSecurity,
      onBack: () => widget.onFinished(false),
      onHelp: help,
      children: [
        const SizedBox(height: 8),
        const SetupBubbleIcon(Icons.vpn_key_outlined, size: 34),
        const SizedBox(height: 16),
        SetupTitle(secureSetupReplaceTitle),
        const SizedBox(height: 8),
        SetupBody(secureSetupReplaceBody),
        const SizedBox(height: 18),
        SetupOption(Icons.autorenew, secureSetupReplaceKeyOption,
            secureSetupReplaceKeyOptionDetail,
            selected: !_lockOutChosen,
            onTap: () => setState(() => _lockOutChosen = false)),
        SetupOption(Icons.gpp_maybe_outlined, secureSetupReplaceUsedOption,
            secureSetupReplaceUsedOptionDetail,
            badge: secureSetupReplaceUsedBadge,
            badgeColor: t.colorScheme.error,
            selected: _lockOutChosen,
            onTap: () => setState(() => _lockOutChosen = true)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
              color: t.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 108),
              Expanded(
                  child: Text(secureSetupCompareReplace,
                      textAlign: TextAlign.center,
                      style: t.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w800))),
              Expanded(
                  child: Text(secureSetupCompareUsed,
                      textAlign: TextAlign.center,
                      style: t.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: t.colorScheme.error))),
            ]),
            const Divider(height: 14),
            compareRow(secureSetupCompareOldKey, secureSetupCompareStopsWorking,
                secureSetupCompareStopsWorking),
            compareRow(secureSetupCompareIdentity, secureSetupCompareStaysSame,
                secureSetupCompareNew,
                bColor: t.colorScheme.error),
            compareRow(secureSetupCompareContactsSee, secureSetupCompareNothing,
                secureSetupCompareIdentityChanged,
                bColor: t.colorScheme.error),
            compareRow(secureSetupCompareHistory, secureSetupCompareKept,
                secureSetupCompareKeptOnDevice),
            compareRow(secureSetupComparePassword, secureSetupCompareNoChange,
                secureSetupCompareChangeItToo,
                bColor: t.colorScheme.error),
          ]),
        ),
      ],
      bottom: [
        SetupPrimaryButton(secureSetupContinue,
            onPressed: () =>
                go(_lockOutChosen ? _Step.lockOutIntro : _Step.replaceCurrent)),
      ],
    );
  }

  Widget replaceCurrent() => SetupPage(
        title: secureSetupSecurity,
        onBack: onBack,
        onHelp: help,
        children: [
          const SizedBox(height: 8),
          const SetupBubbleIcon(Icons.autorenew, size: 34),
          const SizedBox(height: 16),
          SetupTitle(secureSetupReplaceKeyOption),
          const SizedBox(height: 8),
          SetupBody(secureSetupReplaceUnlockBody),
          const SizedBox(height: 18),
          SetupBullet(secureSetupReplaceBullet1,
              icon: Icons.check_circle, color: setupGood),
          SetupBullet(secureSetupReplaceBullet2,
              icon: Icons.check_circle, color: setupGood),
          SetupBullet(secureSetupReplaceBullet3,
              icon: Icons.check_circle, color: setupGood),
          const SizedBox(height: 16),
          AutofillGroup(
            child: Column(children: [
              _hiddenUsername(),
              _plainField(_field1, secureSetupReplaceCurrentKeyLabel,
                  obscure: true,
                  hints: const [AutofillHints.password],
                  suffix: IconButton(
                      tooltip: secureSetupPaste,
                      icon: const Icon(Icons.content_paste),
                      onPressed: () => _paste(_field1))),
            ]),
          ),
          errorText(),
          SetupCallout(
              Icons.info_outline,
              setupWarn,
              secureSetupReplaceThinkUsedTitle,
              secureSetupReplaceThinkUsedBody),
        ],
        bottom: [
          SetupPrimaryButton(secureSetupReplaceUnlockContinue, busy: busy,
              onPressed: () async {
            final input = _field1.text;
            if (input.trim().isEmpty || busy) return;
            setState(() => busy = true);
            final ok = await controller.checkKey(input);
            if (!mounted) return;
            setState(() => busy = false);
            if (!ok) {
              setState(() => error = secureSetupReplaceWrongKey);
              return;
            }
            _currentInput = input;
            mode = _Mode.replace;
            go(_Step.choose);
          }),
          SetupTextLink(secureSetupReplaceNoCurrentKey, onTap: () {
            // Without it the identity can't be kept: the new-key path.
            mode = _Mode.setUp;
            replaceExisting = true;
            keepBackup = true;
            setState(() {
              _stack
                ..clear()
                ..add(_Step.newKey);
            });
          }),
        ],
      );

  Widget lockOutIntro() {
    final t = Theme.of(context);
    return SetupPage(
      title: secureSetupSecurity,
      onBack: onBack,
      onHelp: help,
      children: [
        const SizedBox(height: 8),
        SetupBubbleIcon(Icons.gpp_maybe_outlined,
            color: t.colorScheme.error, size: 34),
        const SizedBox(height: 16),
        SetupTitle(secureSetupLockOutTitle),
        const SizedBox(height: 8),
        SetupBody(secureSetupLockOutBody),
        const SizedBox(height: 18),
        SetupBullet(secureSetupLockOutStep1,
            icon: Icons.looks_one_outlined, color: t.colorScheme.primary),
        SetupBullet(secureSetupLockOutStep2,
            icon: Icons.looks_two_outlined, color: t.colorScheme.primary),
        SetupBullet(secureSetupLockOutStep3,
            icon: Icons.looks_3_outlined, color: t.colorScheme.primary),
        const SizedBox(height: 16),
        SetupCallout(Icons.campaign_outlined, setupWarn,
            secureSetupLockOutWarningTitle, secureSetupLockOutWarningBody),
      ],
      bottom: [
        HoldButton(secureSetupLockOutHold, onHeld: () {
          mode = _Mode.lockOut;
          go(_Step.choose);
        }),
        SetupTextLink(secureSetupGoBack, onTap: back),
      ],
    );
  }

  Widget changePassword() => SetupPage(
        title: secureSetupSecurity,
        children: [
          const SizedBox(height: 40),
          const SetupBubbleIcon(Icons.verified_user,
              color: setupGood, size: 46),
          const SizedBox(height: 22),
          SetupTitle(secureSetupLockedOutTitle),
          const SizedBox(height: 10),
          SetupBody(secureSetupLockedOutBody),
          const SizedBox(height: 22),
          SetupCallout(
              Icons.password,
              Theme.of(context).colorScheme.error,
              secureSetupLockedOutPasswordTitle,
              secureSetupLockedOutPasswordBody),
        ],
        bottom: [
          SetupPrimaryButton(secureSetupLockedOutChangePassword,
              onPressed: () async {
            final changed = await ChangePassword.start(context, widget.client);
            if (changed && mounted) widget.onFinished(true);
          }),
          SetupTextLink(secureSetupLockedOutLater,
              onTap: () => widget.onFinished(true)),
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
          SetupTitle(secureSetupDoneTitle),
          const SizedBox(height: 12),
          SetupBody(secureSetupDoneBody),
          const SizedBox(height: 26),
          SetupCallout(Icons.devices, Theme.of(context).colorScheme.primary,
              secureSetupDoneHintTitle, secureSetupDoneHintBody),
        ],
        bottom: [
          SetupPrimaryButton(secureSetupDoneStart,
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

/// The two skip warnings on their own, for layout tests.
List<Widget> skipDialogsForTest() => const [_SkipDialog1(), _SkipDialog2()];

class _SkipDialog1 extends StatelessWidget {
  const _SkipDialog1();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SetupDialog(
      icon: const Icon(Icons.warning_amber_rounded, size: 40, color: setupWarn),
      title: secureSetupSkipTitle,
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(secureSetupSkipWithout, style: t.textTheme.bodyLarge),
            const SizedBox(height: 8),
            SetupBullet(secureSetupSkipBullet1),
            SetupBullet(secureSetupSkipBullet2),
            SetupBullet(secureSetupSkipBullet3),
          ]),
      buttons: [
        SetupPrimaryButton(secureSetupSkipGoBack,
            onPressed: () => Navigator.of(context).pop(false)),
        SetupTextLink(secureSetupSkipAnyway,
            onTap: () => Navigator.of(context).pop(true)),
      ],
    );
  }
}

class _SkipDialog2 extends StatelessWidget {
  const _SkipDialog2();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SetupDialog(
      icon: Icon(Icons.report_outlined, size: 40, color: t.colorScheme.error),
      title: secureSetupSkipDevTitle,
      content: Text(secureSetupSkipDevBody, textAlign: TextAlign.center),
      buttons: [
        SetupPrimaryButton(secureSetupSkipDevBack,
            onPressed: () => Navigator.of(context).pop(false)),
        const SizedBox(height: 12),
        HoldButton(secureSetupSkipDevHold,
            onHeld: () => Navigator.of(context).pop(true)),
        const SizedBox(height: 6),
        Text(secureSetupSkipDevLater,
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

String get secureSetupErrorAlreadySetUp => Intl.message(
    "Secure messaging is already set up on your account. Confirm this device instead.",
    name: "secureSetupErrorAlreadySetUp",
    desc:
        "Error in secure messaging setup when the account already has it set up");

String get secureSetupErrorOldBackup => Intl.message(
    "Your account has a message backup made by another app (like Element). Confirm this device there, or use \"I've lost all my devices\" to start over; the old backup would be replaced.",
    name: "secureSetupErrorOldBackup",
    desc:
        "Error in secure messaging setup when the account has a key backup from another app; quotes the button \"I've lost all my devices\"");

String get secureSetupErrorBackupNotKept => Intl.message(
    "This device doesn't have the key to your current message backup, so it can't be kept with a new key. Messages on this device stay readable.",
    name: "secureSetupErrorBackupNotKept",
    desc:
        "Error in secure messaging setup when the current backup cannot be kept with a new key");

String get secureSetupErrorWrongKey => Intl.message(
    "That didn't work. Check for typos, or try your recovery key if you used a phrase (or the other way round).",
    name: "secureSetupErrorWrongKey",
    desc:
        "Error when the entered recovery key, phrase or password did not work");

String get secureSetupErrorMalformedKey => Intl.message(
    "That recovery key has a typo: a character is missing, extra or wrong. Paste it again from where you saved it.",
    name: "secureSetupErrorMalformedKey",
    desc:
        "Error when the entered text looks like a recovery key but fails its built-in checksum");

String get secureSetupErrorNothingToUnlock => Intl.message(
    "Your account has nothing stored for a recovery key to unlock. If you use Element, open its Settings › Encryption and fix any key storage warning there, or approve this device from Element instead.",
    name: "secureSetupErrorNothingToUnlock",
    desc:
        "Error when the account's identity keys are not in secret storage, so no recovery key can work; mentions the Element app by name");

String secureSetupErrorGeneric(String error) => Intl.message(
    "Something went wrong. Try again. ($error)",
    args: [error],
    name: "secureSetupErrorGeneric",
    desc:
        "Generic error in secure messaging setup; error is the technical error text");

String get secureSetupWorkingCreateTitle => Intl.message(
    "Setting up secure messaging",
    name: "secureSetupWorkingCreateTitle",
    desc: "Title of the progress screen while creating secure messaging keys");

String get secureSetupWorkingCreateBody => Intl.message(
    "Creating your keys. This takes a few seconds.",
    name: "secureSetupWorkingCreateBody",
    desc: "Body of the progress screen while creating secure messaging keys");

String get secureSetupWithoutOldBackup =>
    Intl.message("Make the new key without the old backup",
        name: "secureSetupWithoutOldBackup",
        desc: "Link to make a new recovery key without keeping the old backup");

String get secureSetupIntroTitle => Intl.message("Keep your messages safe",
    name: "secureSetupIntroTitle",
    desc: "Title of the first secure messaging setup screen");

String get secureSetupIntroBody1 => Intl.message(
    "Your private messages are locked on your device. Nobody else can read them, not even the people who run the server. Most chat apps can read everything you send.",
    name: "secureSetupIntroBody1",
    desc: "First paragraph of the secure messaging setup intro");

String get secureSetupIntroBody2 => Intl.message(
    "That's because only you hold the keys, and keeping them safe is your job. It takes 2 minutes, and we'll walk you through it.",
    name: "secureSetupIntroBody2",
    desc: "Second paragraph of the secure messaging setup intro");

String get secureSetupIntroBenefit1 =>
    Intl.message("Read your messages on a new phone or computer",
        name: "secureSetupIntroBenefit1",
        desc: "Benefit bullet on the secure messaging setup intro");

String get secureSetupIntroBenefit2 =>
    Intl.message("Keep your history if you reinstall or lose a device",
        name: "secureSetupIntroBenefit2",
        desc: "Benefit bullet on the secure messaging setup intro");

String get secureSetupIntroBenefit3 =>
    Intl.message("Show others that this device is really you",
        name: "secureSetupIntroBenefit3",
        desc: "Benefit bullet on the secure messaging setup intro");

String get secureSetupIntroStart => Intl.message("Set up  ·  about 2 minutes",
    name: "secureSetupIntroStart",
    desc:
        "Main button of the secure messaging setup intro (the two spaces around · are intentional)");

String get secureSetupWhatDoesThisMean => Intl.message("What does this mean?",
    name: "secureSetupWhatDoesThisMean",
    desc: "Link that opens the secure messaging explainer");

String get secureSetupSkipForNow => Intl.message("Skip for now",
    name: "secureSetupSkipForNow",
    desc: "Link that skips secure messaging setup");

String get secureSetupChooseTitle =>
    Intl.message("How do you want to save your recovery key?",
        name: "secureSetupChooseTitle",
        desc: "Title of the screen choosing how to save the recovery key");

String get secureSetupChooseBody => Intl.message(
    "It gets you back into your messages if you lose all your devices.",
    name: "secureSetupChooseBody",
    desc: "Body of the screen choosing how to save the recovery key");

String get secureSetupChooseWarningTitle => Intl.message(
    "Treat it like your house key",
    name: "secureSetupChooseWarningTitle",
    desc: "Warning title on the screen choosing how to save the recovery key");

String get secureSetupChooseWarningBody => Intl.message(
    "Together with your password, it lets someone read your whole message history and impersonate you. Store it encrypted. A password manager is best.",
    name: "secureSetupChooseWarningBody",
    desc: "Warning body on the screen choosing how to save the recovery key");

String get secureSetupOptionManager =>
    Intl.message("Save in an encrypted password manager",
        name: "secureSetupOptionManager",
        desc: "Option: save the recovery key in a password manager");

String get secureSetupOptionManagerDetail => Intl.message(
    "Bitwarden on any device, or iCloud Keychain on Apple. Only you can open them.",
    name: "secureSetupOptionManagerDetail",
    desc: "Detail of the password manager option");

String get secureSetupOptionManagerBadge =>
    Intl.message("RECOMMENDED · ENCRYPTED",
        name: "secureSetupOptionManagerBadge",
        desc: "Badge on the password manager option (short, upper case)");

String get secureSetupOptionPhrase => Intl.message("Use a memorable phrase",
    name: "secureSetupOptionPhrase",
    desc: "Option: use a memorable recovery phrase");

String get secureSetupOptionPhraseDetail => Intl.message(
    "6 easy words to keep in your head. Best saved in a password manager too.",
    name: "secureSetupOptionPhraseDetail",
    desc: "Detail of the recovery phrase option");

String get secureSetupOptionPassword => Intl.message("Choose my own password",
    name: "secureSetupOptionPassword",
    desc: "Option: choose your own recovery password");

String get secureSetupOptionPasswordDetail => Intl.message(
    "Something long that only you know. Save it in a password manager too.",
    name: "secureSetupOptionPasswordDetail",
    desc: "Detail of the recovery password option");

String get secureSetupContinue => Intl.message("Continue",
    name: "secureSetupContinue",
    desc: "Continue button in the secure messaging setup");

String get secureSetupNoManagerTitle => Intl.message("No password manager yet?",
    name: "secureSetupNoManagerTitle",
    desc: "Title of the card recommending a password manager");

String get secureSetupNoManagerBody => Intl.message(
    "The Vommet developers recommend Bitwarden. It's free, end-to-end encrypted, and works on every device.",
    name: "secureSetupNoManagerBody",
    desc: "Body of the card recommending Bitwarden");

String get secureSetupNoManagerGetIt => Intl.message("Get it",
    name: "secureSetupNoManagerGetIt",
    desc: "Button on the Bitwarden card that opens its download page");

String get secureSetupGoogleCaveatTitle =>
    Intl.message("Your phone saves passwords to Google",
        name: "secureSetupGoogleCaveatTitle",
        desc: "Warning title when the phone saves passwords to Google");

String get secureSetupGoogleCaveatBody => Intl.message(
    "Google can read what's saved there unless you've turned on on-device encryption. For your recovery key, use an end-to-end encrypted password manager instead.",
    name: "secureSetupGoogleCaveatBody",
    desc: "Warning body when the phone saves passwords to Google");

String get secureSetupSaveKeyTitle => Intl.message(
    "Save it in your password manager",
    name: "secureSetupSaveKeyTitle",
    desc:
        "Title of the screen for saving the recovery key in a password manager");

String get secureSetupSaveKeyBody => Intl.message(
    "Tap Save and your password manager will offer to keep it.",
    name: "secureSetupSaveKeyBody",
    desc:
        "Body of the screen for saving the recovery key in a password manager");

String secureSetupRecoveryKeyFor(String user) =>
    Intl.message("Recovery key for $user",
        args: [user],
        name: "secureSetupRecoveryKeyFor",
        desc: "Label above the shown recovery key; user is the Matrix user ID");

String get secureSetupSave => Intl.message("Save",
    name: "secureSetupSave",
    desc: "Button that offers the recovery key to the password manager");

String get secureSetupCopyMyself =>
    Intl.message("I'll copy it into my password manager myself",
        name: "secureSetupCopyMyself",
        desc: "Link to copy the recovery key manually");

String get secureSetupCopyForManager =>
    Intl.message("Copy it for my password manager",
        name: "secureSetupCopyForManager",
        desc: "Button that copies the recovery key for a password manager");

String get secureSetupCopiedSnack => Intl.message(
    "Copied. Paste it into your password manager and save it there. We clear the clipboard once it's checked.",
    name: "secureSetupCopiedSnack",
    desc: "Snackbar after copying the recovery key");

String get secureSetupCheckKeyTitle => Intl.message("Let's check it saved",
    name: "secureSetupCheckKeyTitle",
    desc: "Title of the screen checking the recovery key was saved");

String get secureSetupCheckKeyBody => Intl.message(
    "Fill in your recovery key from your password manager. This proves you can get it back when you need it.",
    name: "secureSetupCheckKeyBody",
    desc: "Body of the screen checking the recovery key was saved");

String get secureSetupRecoveryKeyLabel => Intl.message("Recovery key",
    name: "secureSetupRecoveryKeyLabel",
    desc: "Field label / title: recovery key");

String get secureSetupPaste => Intl.message("Paste",
    name: "secureSetupPaste",
    desc: "Tooltip of the paste button in recovery key fields");

String get secureSetupCheckKeyCantFind =>
    Intl.message("Can't find it? Go back and save it again. That's fine.",
        name: "secureSetupCheckKeyCantFind",
        desc: "Hint on the screen checking the recovery key was saved");

String get secureSetupCheck => Intl.message("Check",
    name: "secureSetupCheck", desc: "Button that checks what the user entered");

String get secureSetupCheckKeyMismatch => Intl.message(
    "That's not the same key. Check your password manager has the whole key.",
    name: "secureSetupCheckKeyMismatch",
    desc: "Error when the entered recovery key differs from the created one");

String get secureSetupPhraseTitle => Intl.message("Your recovery phrase",
    name: "secureSetupPhraseTitle",
    desc: "Title of the screen showing the recovery phrase");

String get secureSetupPhraseBody => Intl.message(
    "Remember these 6 words in order. Best: save them in a password manager too.",
    name: "secureSetupPhraseBody",
    desc: "Body of the screen showing the recovery phrase");

String get secureSetupPhraseDifferentWords => Intl.message("Different words",
    name: "secureSetupPhraseDifferentWords",
    desc: "Button that generates different recovery phrase words");

String get secureSetupPhraseSaveToManager =>
    Intl.message("Save to password manager",
        name: "secureSetupPhraseSaveToManager",
        desc: "Button that saves the recovery phrase to a password manager");

String get secureSetupPhraseCopy => Intl.message("Copy to clipboard",
    name: "secureSetupPhraseCopy",
    desc: "Button that copies the recovery phrase to the clipboard");

String get secureSetupPhraseCopiedSnack => Intl.message(
    "Copied. Paste it into your password manager and save it there. We clear the clipboard when setup is done.",
    name: "secureSetupPhraseCopiedSnack",
    desc: "Shown after the recovery phrase was copied to the clipboard");

String get secureSetupPhrasePaperWarning => Intl.message(
    "Writing them down? Paper isn't encrypted, so keep it locked away.",
    name: "secureSetupPhrasePaperWarning",
    desc: "Note about writing the recovery phrase down");

String get secureSetupPhraseNeverSendTitle =>
    Intl.message("Never send it to anyone",
        name: "secureSetupPhraseNeverSendTitle",
        desc: "Warning title on the recovery phrase screen");

String get secureSetupPhraseNeverSendBody => Intl.message(
    "With these words and your password, anyone can read your message history and impersonate you. Nobody from Vommet or your server will ever ask for them.",
    name: "secureSetupPhraseNeverSendBody",
    desc: "Warning body on the recovery phrase screen");

String get secureSetupPhraseNoScreenshotTitle =>
    Intl.message("Don't screenshot it",
        name: "secureSetupPhraseNoScreenshotTitle",
        desc: "Warning title on the recovery phrase screen");

String get secureSetupPhraseNoScreenshotBody =>
    Intl.message("Photos sync to the cloud and get shared by accident.",
        name: "secureSetupPhraseNoScreenshotBody",
        desc: "Warning body on the recovery phrase screen");

String get secureSetupPhraseGotThem => Intl.message("I've got them",
    name: "secureSetupPhraseGotThem",
    desc: "Button after the user noted the recovery phrase words");

String get secureSetupCheckPhraseTitle =>
    Intl.message("Let's check you saved it",
        name: "secureSetupCheckPhraseTitle",
        desc: "Title of the screen checking the recovery phrase");

String get secureSetupCheckPhraseBody => Intl.message(
    "Without looking at the last screen, type these words from your phrase.",
    name: "secureSetupCheckPhraseBody",
    desc: "Body of the screen checking the recovery phrase");

String secureSetupPhraseWordLabel(int number) => Intl.message("Word $number",
    args: [number],
    name: "secureSetupPhraseWordLabel",
    desc:
        "Label of a field for one word of the recovery phrase; number is its position");

String get secureSetupCheckPhraseSaveAgain => Intl.message(
    "Save them this time, then hide them and type the two words.",
    name: "secureSetupCheckPhraseSaveAgain",
    desc: "Shown when the user asked to see the recovery phrase words again");

String get secureSetupCheckPhraseShowAgain =>
    Intl.message("Lost them already? Show my words again",
        name: "secureSetupCheckPhraseShowAgain",
        desc: "Link that shows the recovery phrase words again");

String get secureSetupCheckPhraseHide =>
    Intl.message("Hide them, I've saved them",
        name: "secureSetupCheckPhraseHide",
        desc: "Button that hides the shown recovery phrase words again");

String get secureSetupCheckPhraseWrong =>
    Intl.message("Those aren't the right words.",
        name: "secureSetupCheckPhraseWrong",
        desc: "Error when the typed recovery phrase words are wrong");

String get secureSetupPasswordTitle =>
    Intl.message("Choose a recovery password",
        name: "secureSetupPasswordTitle",
        desc: "Title of the screen for choosing a recovery password");

String get secureSetupPasswordBody => Intl.message(
    "Long and memorable beats short and clever. A short sentence works well.",
    name: "secureSetupPasswordBody",
    desc: "Body of the screen for choosing a recovery password");

String get secureSetupRecoveryPasswordLabel => Intl.message("Recovery password",
    name: "secureSetupRecoveryPasswordLabel",
    desc: "Field label: recovery password");

String get secureSetupHide => Intl.message("Hide",
    name: "secureSetupHide",
    desc: "Tooltip of the button that hides the password");

String get secureSetupShow => Intl.message("Show",
    name: "secureSetupShow",
    desc: "Tooltip of the button that shows the password");

String get secureSetupPasswordIsLoginTitle => Intl.message(
    "This is your login password",
    name: "secureSetupPasswordIsLoginTitle",
    desc: "Warning title when the recovery password equals the login password");

String get secureSetupPasswordIsLoginBody => Intl.message(
    "If you use the same one, anyone who gets your login password can also read your private messages. Pick something different.",
    name: "secureSetupPasswordIsLoginBody",
    desc: "Warning body when the recovery password equals the login password");

String get secureSetupPasswordForgetTitle => Intl.message("People forget these",
    name: "secureSetupPasswordForgetTitle",
    desc: "Warning title on the recovery password screen");

String get secureSetupPasswordForgetBody => Intl.message(
    "A password you only use here is easy to forget, and then your messages are gone. Save it in a password manager like Bitwarden too.",
    name: "secureSetupPasswordForgetBody",
    desc: "Warning body on the recovery password screen");

String get secureSetupCheckPasswordTitle => Intl.message("Type it once more",
    name: "secureSetupCheckPasswordTitle",
    desc: "Title of the screen checking the recovery password");

String get secureSetupCheckPasswordBody => Intl.message(
    "Your recovery password, from memory or your password manager. This makes sure there's no typo in it.",
    name: "secureSetupCheckPasswordBody",
    desc: "Body of the screen checking the recovery password");

String get secureSetupCheckPasswordForgot =>
    Intl.message("Forgot it already? Choose a different password",
        name: "secureSetupCheckPasswordForgot",
        desc: "Link to choose a different recovery password");

String get secureSetupCheckPasswordMismatch =>
    Intl.message("That's not the same password.",
        name: "secureSetupCheckPasswordMismatch",
        desc: "Error when the retyped recovery password differs");

String get secureSetupSigningIn => Intl.message("Signing in",
    name: "secureSetupSigningIn",
    desc: "Page title of the secure messaging sign-in steps");

String get secureSetupExistingTitle => Intl.message("Is this you?",
    name: "secureSetupExistingTitle",
    desc:
        "Title of the screen confirming a new device on an account with secure messaging");

String get secureSetupExistingBody => Intl.message(
    "You've used secure messaging before. Confirm this new device so it can read your messages.",
    name: "secureSetupExistingBody",
    desc: "Body of the screen confirming a new device");

String get secureSetupExistingApprove =>
    Intl.message("Approve from another device",
        name: "secureSetupExistingApprove",
        desc: "Option: approve this device from another device");

String get secureSetupExistingApproveDetail =>
    Intl.message("Open the app on your phone or computer and tap Approve.",
        name: "secureSetupExistingApproveDetail",
        desc: "Detail of the approve-from-another-device option");

String get secureSetupExistingApproveBadge => Intl.message("EASIEST",
    name: "secureSetupExistingApproveBadge",
    desc:
        "Badge on the approve-from-another-device option (short, upper case)");

String get secureSetupExistingEnterKey =>
    Intl.message("Enter recovery key or phrase",
        name: "secureSetupExistingEnterKey",
        desc: "Option: enter the recovery key or phrase");

String get secureSetupExistingEnterKeyDetail =>
    Intl.message("Or let your password manager fill it in.",
        name: "secureSetupExistingEnterKeyDetail",
        desc: "Detail of the enter-recovery-key option");

String get secureSetupExistingLostAll =>
    Intl.message("I've lost all my devices and my recovery key",
        name: "secureSetupExistingLostAll",
        desc: "Link for users who lost all devices and the recovery key");

String get secureSetupEnterKeyTitle => Intl.message("Enter your recovery key",
    name: "secureSetupEnterKeyTitle",
    desc: "Title of the screen for entering the recovery key");

String get secureSetupEnterKeyBody => Intl.message(
    "Or your recovery phrase or password, if you chose one. Your password manager can fill it in.",
    name: "secureSetupEnterKeyBody",
    desc: "Body of the screen for entering the recovery key");

String get secureSetupEnterKeyLabel =>
    Intl.message("Recovery key, phrase, or password",
        name: "secureSetupEnterKeyLabel",
        desc: "Field label on the screen for entering the recovery key");

String get secureSetupEnterKeyWhere => Intl.message("Where do I find it?",
    name: "secureSetupEnterKeyWhere",
    desc: "Link that opens help about where the recovery key is");

String get secureSetupEnterKeyUnlock => Intl.message("Unlock my messages",
    name: "secureSetupEnterKeyUnlock",
    desc: "Button that unlocks messages with the entered recovery key");

String get secureSetupWorkingUnlockTitle =>
    Intl.message("Unlocking your messages",
        name: "secureSetupWorkingUnlockTitle",
        desc: "Title of the progress screen while unlocking messages");

String get secureSetupWorkingUnlockBody => Intl.message(
    "Fetching the keys to your message history. This can take a minute on a big account.",
    name: "secureSetupWorkingUnlockBody",
    desc: "Body of the progress screen while unlocking messages");

String secureSetupApprovalFailedCode(String code) => Intl.message(
    "The approval was canceled or failed ($code). Try again, or use your recovery key.",
    args: [code],
    name: "secureSetupApprovalFailedCode",
    desc:
        "Error when approving this device from another device failed; code is the Matrix cancel code, e.g. m.user or m.timeout");

String get secureSetupApprovalNoDevice => Intl.message(
    "None of your other devices can approve this one yet. Use your recovery key, or approve from a device that already shows your messages.",
    name: "secureSetupApprovalNoDevice",
    desc:
        "Error when the account has no other confirmed device to send an approval request to");

String get secureSetupApprovalUnreachable =>
    Intl.message("Couldn't reach your other devices. Try your recovery key.",
        name: "secureSetupApprovalUnreachable",
        desc: "Error when the other devices could not be reached for approval");

String get secureSetupApproveTitle =>
    Intl.message("Approve on your other device",
        name: "secureSetupApproveTitle",
        desc: "Title of the screen waiting for approval from another device");

String get secureSetupApproveBody => Intl.message(
    "Open Vommet (or another Matrix app) on a phone or computer you're already signed in to. A request to approve this device will pop up there.",
    name: "secureSetupApproveBody",
    desc: "Body of the screen waiting for approval from another device");

String get secureSetupApproveWaiting =>
    Intl.message("Waiting for your other device…",
        name: "secureSetupApproveWaiting",
        desc: "Shown while waiting for the other device");

String get secureSetupApproveUseKey =>
    Intl.message("Use my recovery key instead",
        name: "secureSetupApproveUseKey",
        desc: "Link to use the recovery key instead of another device");

String get secureSetupResetTitle => Intl.message("Start over with a new key?",
    name: "secureSetupResetTitle",
    desc: "Title of the screen for starting over with a new key");

String get secureSetupResetBody => Intl.message(
    "Only do this if you've lost every signed-in device AND your recovery key.",
    name: "secureSetupResetBody",
    desc: "Body of the screen for starting over with a new key");

String get secureSetupResetBullet1 => Intl.message(
    "Your old private messages stay locked. Nobody can unlock them, not even your server's admins.",
    name: "secureSetupResetBullet1",
    desc: "Consequence bullet on the start-over screen");

String get secureSetupResetBullet2 => Intl.message(
    "People you talk to will see that your secure identity changed.",
    name: "secureSetupResetBullet2",
    desc: "Consequence bullet on the start-over screen");

String get secureSetupResetBullet3 => Intl.message(
    "Your other signed-in devices (if any turn up) will need approving again.",
    name: "secureSetupResetBullet3",
    desc: "Consequence bullet on the start-over screen");

String get secureSetupResetCheckFirstTitle => Intl.message("Check first",
    name: "secureSetupResetCheckFirstTitle",
    desc: "Hint title on the start-over screen");

String get secureSetupResetCheckFirstBody => Intl.message(
    "An old phone in a drawer, or a laptop that's still signed in, can approve this device and keep everything.",
    name: "secureSetupResetCheckFirstBody",
    desc: "Hint body on the start-over screen");

String get secureSetupResetHold => Intl.message("Hold to start over",
    name: "secureSetupResetHold",
    desc: "Hold-to-confirm button on the start-over screen");

String get secureSetupGoBack => Intl.message("Go back",
    name: "secureSetupGoBack", desc: "Link that goes back one step");

String get secureSetupNewKeyTitle => Intl.message("Make a new recovery key",
    name: "secureSetupNewKeyTitle",
    desc: "Title of the screen for making a new recovery key");

String get secureSetupNewKeyBody => Intl.message(
    "Good news: this device still has your messages, so nothing is lost. A new key backs them up again.",
    name: "secureSetupNewKeyBody",
    desc: "Body of the screen for making a new recovery key");

String get secureSetupNewKeyBullet1 => Intl.message(
    "Your old key stops working. If anyone finds it, it's useless.",
    name: "secureSetupNewKeyBullet1",
    desc: "Consequence bullet on the new recovery key screen");

String get secureSetupNewKeyBullet2 => Intl.message(
    "People you talk to will see your secure identity changed. It's still you; you can tell them why.",
    name: "secureSetupNewKeyBullet2",
    desc: "Consequence bullet on the new recovery key screen");

String get secureSetupNewKeyBullet3 =>
    Intl.message("Your other signed-in devices need approving again.",
        name: "secureSetupNewKeyBullet3",
        desc: "Consequence bullet on the new recovery key screen");

String get secureSetupNewKeyHold => Intl.message("Hold to make a new key",
    name: "secureSetupNewKeyHold",
    desc: "Hold-to-confirm button on the new recovery key screen");

String get secureSetupSecurity => Intl.message("Security",
    name: "secureSetupSecurity",
    desc: "Page title of the replace-recovery-key steps");

String get secureSetupReplaceTitle => Intl.message("Replace your recovery key",
    name: "secureSetupReplaceTitle",
    desc: "Title of the screen choosing how to replace the recovery key");

String get secureSetupReplaceBody => Intl.message("Pick the one that fits.",
    name: "secureSetupReplaceBody",
    desc: "Body of the screen choosing how to replace the recovery key");

String get secureSetupReplaceKeyOption =>
    Intl.message("Replace my recovery key",
        name: "secureSetupReplaceKeyOption",
        desc: "Option and title: replace the recovery key only");

String get secureSetupReplaceKeyOptionDetail => Intl.message(
    "For when someone might have seen it. Your identity stays the same, nobody sees a change, and the old key stops working. Only helps if nobody has used it yet.",
    name: "secureSetupReplaceKeyOptionDetail",
    desc: "Detail of the replace-key-only option");

String get secureSetupReplaceUsedOption =>
    Intl.message("Someone may have used my key",
        name: "secureSetupReplaceUsedOption",
        desc: "Option: someone may have used my recovery key");

String get secureSetupReplaceUsedOptionDetail => Intl.message(
    "Also resets your identity, so any copy someone made becomes worthless. People you talk to will see your identity changed; tell them it was you. Change your password too.",
    name: "secureSetupReplaceUsedOptionDetail",
    desc: "Detail of the someone-used-my-key option");

String get secureSetupReplaceUsedBadge => Intl.message("STRONGER",
    name: "secureSetupReplaceUsedBadge",
    desc: "Badge on the someone-used-my-key option (short, upper case)");

String get secureSetupCompareReplace => Intl.message("Replace",
    name: "secureSetupCompareReplace",
    desc:
        "Column header in the comparison table: replace the key only (short)");

String get secureSetupCompareUsed => Intl.message("Someone used it",
    name: "secureSetupCompareUsed",
    desc:
        "Column header in the comparison table: someone used the key (short)");

String get secureSetupCompareOldKey => Intl.message("Old key",
    name: "secureSetupCompareOldKey",
    desc: "Row label in the comparison table");

String get secureSetupCompareStopsWorking => Intl.message("Stops working",
    name: "secureSetupCompareStopsWorking",
    desc: "Comparison table cell: the old key stops working");

String get secureSetupCompareIdentity => Intl.message("Your identity",
    name: "secureSetupCompareIdentity",
    desc: "Row label in the comparison table");

String get secureSetupCompareStaysSame => Intl.message("Stays the same",
    name: "secureSetupCompareStaysSame", desc: "Comparison table cell");

String get secureSetupCompareNew => Intl.message("New",
    name: "secureSetupCompareNew",
    desc: "Comparison table cell: a new identity");

String get secureSetupCompareContactsSee => Intl.message("Contacts see",
    name: "secureSetupCompareContactsSee",
    desc: "Row label in the comparison table");

String get secureSetupCompareNothing => Intl.message("Nothing",
    name: "secureSetupCompareNothing",
    desc: "Comparison table cell: contacts see nothing");

String get secureSetupCompareIdentityChanged =>
    Intl.message("\"Identity changed\"",
        name: "secureSetupCompareIdentityChanged",
        desc: "Comparison table cell: contacts see an identity changed notice");

String get secureSetupCompareHistory => Intl.message("Message history",
    name: "secureSetupCompareHistory",
    desc: "Row label in the comparison table");

String get secureSetupCompareKept => Intl.message("Kept",
    name: "secureSetupCompareKept",
    desc: "Comparison table cell: message history is kept");

String get secureSetupCompareKeptOnDevice => Intl.message("Kept on this device",
    name: "secureSetupCompareKeptOnDevice",
    desc: "Comparison table cell: message history is kept on this device");

String get secureSetupComparePassword => Intl.message("Your password",
    name: "secureSetupComparePassword",
    desc: "Row label in the comparison table");

String get secureSetupCompareNoChange => Intl.message("No change",
    name: "secureSetupCompareNoChange",
    desc: "Comparison table cell: no password change needed");

String get secureSetupCompareChangeItToo => Intl.message("Change it too",
    name: "secureSetupCompareChangeItToo",
    desc: "Comparison table cell: change the password too");

String get secureSetupReplaceUnlockBody => Intl.message(
    "First, unlock with your current key, phrase, or password. Then you'll save a new one the same way as before.",
    name: "secureSetupReplaceUnlockBody",
    desc: "Body of the screen unlocking before replacing the recovery key");

String get secureSetupReplaceBullet1 =>
    Intl.message("Your identity stays the same. Nobody sees a change.",
        name: "secureSetupReplaceBullet1",
        desc: "Bullet on the replace-recovery-key screen");

String get secureSetupReplaceBullet2 =>
    Intl.message("Your message history is kept.",
        name: "secureSetupReplaceBullet2",
        desc: "Bullet on the replace-recovery-key screen");

String get secureSetupReplaceBullet3 =>
    Intl.message("The old key stops working once the new one is saved.",
        name: "secureSetupReplaceBullet3",
        desc: "Bullet on the replace-recovery-key screen");

String get secureSetupReplaceCurrentKeyLabel =>
    Intl.message("Current recovery key, phrase, or password",
        name: "secureSetupReplaceCurrentKeyLabel",
        desc: "Field label for the current recovery key");

String get secureSetupReplaceThinkUsedTitle =>
    Intl.message("Think someone already used it?",
        name: "secureSetupReplaceThinkUsedTitle",
        desc: "Hint title on the replace-recovery-key screen");

String get secureSetupReplaceThinkUsedBody => Intl.message(
    "Then this isn't enough: go back and choose \"Someone may have used my key.\"",
    name: "secureSetupReplaceThinkUsedBody",
    desc:
        "Hint body on the replace-recovery-key screen; quotes the option \"Someone may have used my key\"");

String get secureSetupReplaceUnlockContinue =>
    Intl.message("Unlock and continue",
        name: "secureSetupReplaceUnlockContinue",
        desc: "Button that unlocks and continues replacing the recovery key");

String get secureSetupReplaceWrongKey =>
    Intl.message("That key, phrase, or password didn't work. Check for typos.",
        name: "secureSetupReplaceWrongKey",
        desc: "Error when the current recovery key did not work");

String get secureSetupReplaceNoCurrentKey =>
    Intl.message("I don't have my current key",
        name: "secureSetupReplaceNoCurrentKey",
        desc: "Link for users without their current recovery key");

String get secureSetupLockOutTitle => Intl.message(
    "Lock out whoever has your key",
    name: "secureSetupLockOutTitle",
    desc: "Title of the screen resetting the key and identity after a leak");

String get secureSetupLockOutBody => Intl.message(
    "We'll make everything new, so a copy someone made can't be used. It takes three steps.",
    name: "secureSetupLockOutBody",
    desc: "Body of the lock-out screen");

String get secureSetupLockOutStep1 =>
    Intl.message("A new recovery key, saved the same way as before",
        name: "secureSetupLockOutStep1",
        desc: "Step bullet on the lock-out screen");

String get secureSetupLockOutStep2 => Intl.message(
    "A new identity and a new backup of everything this device can read",
    name: "secureSetupLockOutStep2",
    desc: "Step bullet on the lock-out screen");

String get secureSetupLockOutStep3 => Intl.message(
    "Then change your account password, so they can't sign in either",
    name: "secureSetupLockOutStep3",
    desc: "Step bullet on the lock-out screen");

String get secureSetupLockOutWarningTitle =>
    Intl.message("People will see a change",
        name: "secureSetupLockOutWarningTitle",
        desc: "Warning title on the lock-out screen");

String get secureSetupLockOutWarningBody => Intl.message(
    "Your contacts get an \"identity changed\" notice and may ask you to confirm it's you. That's how they stay safe too. Your other devices need approving again.",
    name: "secureSetupLockOutWarningBody",
    desc: "Warning body on the lock-out screen");

String get secureSetupLockOutHold => Intl.message("Hold to lock them out",
    name: "secureSetupLockOutHold",
    desc: "Hold-to-confirm button on the lock-out screen");

String get secureSetupLockedOutTitle => Intl.message("New key and identity",
    name: "secureSetupLockedOutTitle",
    desc: "Title of the screen after the key and identity were reset");

String get secureSetupLockedOutBody =>
    Intl.message("Whoever had your old key can't use it any more.",
        name: "secureSetupLockedOutBody",
        desc: "Body of the screen after the key and identity were reset");

String get secureSetupLockedOutPasswordTitle =>
    Intl.message("One more step: change your password",
        name: "secureSetupLockedOutPasswordTitle",
        desc: "Hint title after the reset, asking to change the password");

String get secureSetupLockedOutPasswordBody => Intl.message(
    "With your password they could still sign in as you. Change it now; it takes a minute.",
    name: "secureSetupLockedOutPasswordBody",
    desc: "Hint body after the reset, asking to change the password");

String get secureSetupLockedOutChangePassword =>
    Intl.message("Change my password",
        name: "secureSetupLockedOutChangePassword",
        desc: "Button that opens the change password dialog");

String get secureSetupLockedOutLater => Intl.message("I'll do it later",
    name: "secureSetupLockedOutLater",
    desc: "Link to change the password later");

String get secureSetupDoneTitle => Intl.message("You're all set",
    name: "secureSetupDoneTitle",
    desc: "Title of the final secure messaging setup screen");

String get secureSetupDoneBody => Intl.message(
    "Secure messaging is on. Your messages are backed up and only you can unlock them.",
    name: "secureSetupDoneBody",
    desc: "Body of the final secure messaging setup screen");

String get secureSetupDoneHintTitle =>
    Intl.message("Signing in somewhere else?",
        name: "secureSetupDoneHintTitle",
        desc: "Hint title on the final setup screen");

String get secureSetupDoneHintBody => Intl.message(
    "Just approve it from this device. You'll only need your recovery key if you lose every device.",
    name: "secureSetupDoneHintBody",
    desc: "Hint body on the final setup screen");

String get secureSetupDoneStart => Intl.message("Start chatting",
    name: "secureSetupDoneStart",
    desc: "Button that closes the setup and opens the app");

String get secureSetupSkipTitle => Intl.message("Skip secure messaging?",
    name: "secureSetupSkipTitle",
    desc: "Title of the first skip-secure-messaging dialog");

String get secureSetupSkipWithout => Intl.message("Without it:",
    name: "secureSetupSkipWithout",
    desc: "Lead-in above the list of what goes wrong without secure messaging");

String get secureSetupSkipBullet1 =>
    Intl.message("You can lose your private message history for good.",
        name: "secureSetupSkipBullet1",
        desc: "Consequence bullet in the skip dialog");

String get secureSetupSkipBullet2 =>
    Intl.message("Messages may not show on your other devices.",
        name: "secureSetupSkipBullet2",
        desc: "Consequence bullet in the skip dialog");

String get secureSetupSkipBullet3 =>
    Intl.message("People you talk to will see this device as unconfirmed.",
        name: "secureSetupSkipBullet3",
        desc: "Consequence bullet in the skip dialog");

String get secureSetupSkipGoBack => Intl.message("Go back and set up",
    name: "secureSetupSkipGoBack",
    desc: "Button in the skip dialog that returns to setup");

String get secureSetupSkipAnyway => Intl.message("Skip anyway",
    name: "secureSetupSkipAnyway",
    desc: "Link in the skip dialog that skips anyway");

String get secureSetupSkipDevTitle => Intl.message("This is for developers",
    name: "secureSetupSkipDevTitle", desc: "Title of the second skip dialog");

String get secureSetupSkipDevBody => Intl.message(
    "If you don't know exactly why you're skipping this, you almost certainly don't want to. Nobody, not even your server's admins, can recover messages you lose this way.",
    name: "secureSetupSkipDevBody",
    desc: "Body of the second skip dialog");

String get secureSetupSkipDevBack => Intl.message("Take me back",
    name: "secureSetupSkipDevBack",
    desc: "Button in the second skip dialog that returns to setup");

String get secureSetupSkipDevHold => Intl.message("Hold to skip",
    name: "secureSetupSkipDevHold",
    desc: "Hold-to-confirm button in the second skip dialog");

String get secureSetupSkipDevLater => Intl.message(
    "You can set it up later in Settings › Security.",
    name: "secureSetupSkipDevLater",
    desc:
        "Note under the second skip dialog; Settings › Security is the settings path");
