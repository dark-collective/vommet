import 'dart:async';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/rust/api/telegram_import.dart';
import 'package:commet/ui/pages/secure_setup/secure_screen.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/utils/telegram_account_import.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 801: "Import all packs from your Telegram account", inside
/// the Import packs dialog. Explains what happens, signs in by QR code (or
/// the Telegram app on Android), asks for the cloud password when there is
/// one, and hands back the pack list once Vommet has signed out again.
class TelegramAccountImportView extends StatefulWidget {
  const TelegramAccountImportView(
      {required this.onPacks, required this.onClose, super.key});

  /// Signed out (or the user gave up waiting for it to be confirmed) with
  /// at least one pack.
  final void Function(List<TelegramPack> packs) onPacks;

  /// Back to the import dialog.
  final VoidCallback onClose;

  @override
  State<TelegramAccountImportView> createState() =>
      _TelegramAccountImportViewState();
}

enum _Step {
  intro,
  connecting,
  approve,
  password,
  reading,
  signOutUnconfirmed,
  noPacks,
  failed
}

class _TelegramAccountImportViewState extends State<TelegramAccountImportView> {
  _Step step = _Step.intro;
  TelegramAccountImport? import;
  StreamSubscription<TelegramImportEvent>? subscription;

  String? loginUrl;
  DateTime? loginUrlExpires;
  Timer? countdown;
  bool canOpenApp = false;
  bool showQrOnPhone = false;

  String? passwordHint;
  bool passwordWrong = false;
  bool passwordSent = false;
  final TextEditingController passwordController = TextEditingController();

  List<TelegramPack>? packs;
  String? failure;
  bool retryingSignOut = false;

  /// The session is gone (or the user moved on); nothing to cancel.
  bool finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(TelegramAccountImport.canOpenTelegramApp()
        .then((v) => mounted ? setState(() => canOpenApp = v) : null));
  }

  @override
  void dispose() {
    // Leaving early still signs out (in the background).
    if (!finished) import?.cancel();
    subscription?.cancel();
    countdown?.cancel();
    passwordController.dispose();
    super.dispose();
  }

  void start() {
    final run = TelegramAccountImport();
    setState(() {
      import = run;
      step = _Step.connecting;
      failure = null;
      packs = null;
      finished = false;
    });
    subscription = run.start().listen(onEvent,
        onError: (Object e) => setState(() {
              failure = "$e";
              step = _Step.failed;
              finished = true;
            }),
        onDone: onDone);
    countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && step == _Step.approve) setState(() {});
    });
  }

  void onEvent(TelegramImportEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.kind) {
        case TelegramImportEventKind.loginUrl:
          loginUrl = event.loginUrl;
          loginUrlExpires = DateTime.fromMillisecondsSinceEpoch(
              event.loginUrlExpiresAt * 1000);
          step = _Step.approve;
        case TelegramImportEventKind.passwordNeeded:
          passwordHint = event.passwordHint;
          passwordWrong = event.passwordWrong;
          passwordSent = false;
          step = _Step.password;
        case TelegramImportEventKind.signedIn:
          loginUrl = null;
          step = _Step.reading;
        case TelegramImportEventKind.packs:
          packs = event.packs;
        case TelegramImportEventKind.signedOut:
          finished = true;
          finish();
        case TelegramImportEventKind.signOutUnconfirmed:
          retryingSignOut = false;
          step = _Step.signOutUnconfirmed;
        case TelegramImportEventKind.failed:
          failure = event.failure;
      }
    });
  }

  void onDone() {
    if (!mounted || finished) return;
    finished = true;
    setState(() {
      if (failure != null) {
        step = _Step.failed;
      } else if (step != _Step.signOutUnconfirmed) {
        widget.onClose();
      }
    });
  }

  /// Signed out: show the packs, or say why there are none.
  void finish() {
    final found = packs;
    if (found != null && found.isNotEmpty) {
      widget.onPacks(found);
    } else if (failure != null) {
      step = _Step.failed;
    } else if (found != null) {
      step = _Step.noPacks;
    } else {
      widget.onClose();
    }
  }

  void cancel() {
    import?.cancel();
    widget.onClose();
  }

  void sendPassword() {
    final password = passwordController.text;
    if (password.isEmpty) return;
    passwordController.clear();
    setState(() => passwordSent = true);
    import?.password(password);
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (step) {
      _Step.intro => intro(context),
      _Step.connecting => waiting(context, labelTelegramImportConnecting),
      _Step.approve => approve(context),
      _Step.password => password(context),
      _Step.reading => waiting(context, labelTelegramImportReading),
      _Step.signOutUnconfirmed => signOutUnconfirmed(context),
      _Step.noPacks => message(context, labelTelegramImportNoPacks),
      _Step.failed => message(
          context, labelTelegramImportFailed(failure ?? "unknown"),
          error: true),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: SingleChildScrollView(child: body),
    );
  }

  Widget intro(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.body(labelTelegramImportIntro),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            card(context,
                icon: Icons.check,
                color: Colors.green.shade300,
                title: labelTelegramImportReads,
                points: [
                  labelTelegramImportReadsPacks,
                  labelTelegramImportReadsNothingElse
                ]),
            card(context,
                icon: Icons.close,
                color: colors.error,
                title: labelTelegramImportCant,
                points: [
                  labelTelegramImportCantReadChats,
                  labelTelegramImportCantAllowlist
                ]),
          ],
        ),
        const SizedBox(height: 16),
        stepLine(context, 1, labelTelegramImportStepScan),
        stepLine(context, 2, labelTelegramImportStepSignOut),
        stepLine(context, 3,
            labelTelegramImportStepChoose(preferences.proxyUrl.value)),
        const SizedBox(height: 8),
        note(context, Icons.warning_amber, colors.tertiary,
            labelTelegramImportRisk),
        buttons([
          tiamat.Button.secondary(
              text: promptTelegramImportCancel, onTap: widget.onClose),
          tiamat.Button(
              text: PlatformUtils.isAndroid
                  ? promptTelegramImportContinue
                  : promptTelegramImportShowQr,
              onTap: start),
        ]),
      ],
    );
  }

  Widget approve(BuildContext context) {
    final url = loginUrl;
    if (url == null) return waiting(context, labelTelegramImportConnecting);
    final left = loginUrlExpires == null
        ? 0
        : loginUrlExpires!.difference(DateTime.now()).inSeconds.clamp(0, 999);
    final phone = PlatformUtils.isAndroid && canOpenApp && !showQrOnPhone;

    final qr = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 260,
            height: 260,
            child: PrettyQrView.data(
              data: url,
              decoration: const PrettyQrDecoration(
                  quietZone: PrettyQrQuietZone.standard,
                  shape: PrettyQrSmoothSymbol(color: Colors.black),
                  background: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 8),
        tiamat.Text.labelLow(labelTelegramImportNewCodeIn(left)),
      ],
    );

    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: phone
          ? [
              tiamat.Text.body(labelTelegramImportApproveInApp),
              const SizedBox(height: 12),
              tiamat.Button(
                  text: promptTelegramImportOpenTelegram,
                  onTap: () => TelegramAccountImport.openInTelegramApp(url)),
              const SizedBox(height: 8),
              tiamat.Button.secondary(
                  text: promptTelegramImportShowQrOther,
                  onTap: () => setState(() => showQrOnPhone = true)),
            ]
          : [
              stepLine(context, 1, labelTelegramImportQrStepOpen),
              stepLine(context, 2, labelTelegramImportQrStepDevices),
              stepLine(context, 3, labelTelegramImportQrStepPoint),
            ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          if (phone) return steps;
          if (constraints.maxWidth < 560) {
            return Column(children: [qr, const SizedBox(height: 16), steps]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              qr,
              const SizedBox(width: 24),
              Expanded(child: steps),
            ],
          );
        }),
        const SizedBox(height: 16),
        note(
            context,
            Icons.shield_outlined,
            Theme.of(context).colorScheme.error,
            phone
                ? labelTelegramImportApproveWarning
                : labelTelegramImportQrWarning),
        tiamat.Text.labelLow(PlatformUtils.isAndroid
            ? labelTelegramImportScreenshotsBlocked
            : labelTelegramImportCodeNotShared),
        const SizedBox(height: 12),
        Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          tiamat.Text.labelLow(labelTelegramImportWaiting),
        ]),
        buttons([
          tiamat.Button.secondary(
              text: promptTelegramImportCancel, onTap: cancel),
        ]),
      ],
    );

    // The QR code and login link are a key to the account while they're
    // valid: no screenshots or screen recording on Android.
    return ScreenshotGuard(setSecure: SecureScreen.setSecure, child: content);
  }

  Widget password(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.body(labelTelegramImportPasswordIntro),
        const SizedBox(height: 12),
        tiamat.TextInput(
          controller: passwordController,
          label: labelTelegramImportPassword,
          obscureText: true,
          onSubmitted: (_) => sendPassword(),
        ),
        if (passwordHint != null && passwordHint!.isNotEmpty)
          tiamat.Text.labelLow(labelTelegramImportPasswordHint(passwordHint!)),
        if (passwordWrong) tiamat.Text.error(labelTelegramImportPasswordWrong),
        const SizedBox(height: 12),
        note(context, Icons.lock_outline, Theme.of(context).colorScheme.primary,
            labelTelegramImportPasswordLocal),
        buttons([
          tiamat.Button.secondary(
              text: promptTelegramImportCancel, onTap: cancel),
          tiamat.Button(
              text: promptTelegramImportSignIn,
              isLoading: passwordSent,
              onTap: passwordSent ? null : sendPassword),
        ]),
      ],
    );
  }

  Widget signOutUnconfirmed(BuildContext context) {
    final found = packs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        note(context, Icons.warning_amber, Theme.of(context).colorScheme.error,
            labelTelegramImportSignOutUnconfirmed),
        const SizedBox(height: 8),
        tiamat.Text.labelEmphasised(labelTelegramImportEndItYourself),
        stepLine(context, 1, labelTelegramImportEndStepDevices),
        stepLine(context, 2, labelTelegramImportEndStepTerminate),
        tiamat.Text.labelLow(labelTelegramImportSessionInMemory),
        buttons([
          tiamat.Button.secondary(
              text: promptTelegramImportRetrySignOut,
              isLoading: retryingSignOut,
              onTap: retryingSignOut
                  ? null
                  : () {
                      setState(() => retryingSignOut = true);
                      import?.retrySignOut();
                    }),
          tiamat.Button(
              text: promptTelegramImportEndedIt,
              onTap: () {
                // Drops the session; Vommet won't use it again.
                import?.cancel();
                finished = true;
                if (found != null && found.isNotEmpty) {
                  widget.onPacks(found);
                } else {
                  widget.onClose();
                }
              }),
        ]),
      ],
    );
  }

  Widget waiting(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          tiamat.Text.labelLow(text),
          buttons([
            tiamat.Button.secondary(
                text: promptTelegramImportCancel, onTap: cancel),
          ]),
        ],
      ),
    );
  }

  Widget message(BuildContext context, String text, {bool error = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        error ? tiamat.Text.error(text) : tiamat.Text.body(text),
        buttons([
          tiamat.Button.secondary(
              text: promptTelegramImportBack, onTap: widget.onClose),
          if (error)
            tiamat.Button(text: promptTelegramImportTryAgain, onTap: start),
        ]),
      ],
    );
  }

  Widget card(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      required List<String> points}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 350),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                tiamat.Text.labelEmphasised(title, color: color),
              ]),
              const SizedBox(height: 8),
              for (final point in points)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const tiamat.Text.label("•  "),
                      Expanded(child: tiamat.Text.label(point)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget stepLine(BuildContext context, int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            child: tiamat.Text.labelEmphasised("$number"),
          ),
          const SizedBox(width: 12),
          Expanded(child: tiamat.Text.label(text)),
        ],
      ),
    );
  }

  Widget note(BuildContext context, IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(child: tiamat.Text.label(text)),
            ],
          ),
        ),
      ),
    );
  }

  // Wraps onto a second line on narrow phones.
  Widget buttons(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: children,
      ),
    );
  }
}

/// The banner above the pack list once Vommet has signed out of Telegram.
class TelegramSignedOutBanner extends StatelessWidget {
  const TelegramSignedOutBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.green.withAlpha(30),
            borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 20, color: Colors.green.shade300),
              const SizedBox(width: 10),
              Expanded(
                  child: tiamat.Text.label(labelTelegramImportSignedOutBanner)),
            ],
          ),
        ),
      ),
    );
  }
}

String get promptTelegramImportAccount =>
    Intl.message("Import all packs from your Telegram account",
        name: "promptTelegramImportAccount",
        desc: "Title of the card in the pack import dialog that imports every "
            "pack from the user's Telegram account (Vommet issue 801)");

String get labelTelegramImportAccountCard => Intl.message(
    "Sign in by QR code. Vommet reads your list of packs, then signs out right away.",
    name: "labelTelegramImportAccountCard",
    desc: "Text on the Telegram account import card in the pack import dialog");

String get labelTelegramImportIntro => Intl.message(
    "To find your packs, Vommet signs in to your Telegram account for a few seconds. Here is exactly what happens.",
    name: "labelTelegramImportIntro",
    desc: "First line of the Telegram account import explanation");

String get labelTelegramImportReads => Intl.message("Vommet reads",
    name: "labelTelegramImportReads",
    desc: "Heading of the list of what the Telegram import reads");

String get labelTelegramImportReadsPacks => Intl.message(
    "The names of the sticker packs and custom emoji packs you have added in Telegram.",
    name: "labelTelegramImportReadsPacks",
    desc: "What the Telegram import reads");

String get labelTelegramImportReadsNothingElse => Intl.message("That's all.",
    name: "labelTelegramImportReadsNothingElse",
    desc: "Second point under 'Vommet reads': nothing else is read");

String get labelTelegramImportCant => Intl.message("Vommet can't",
    name: "labelTelegramImportCant",
    desc: "Heading of the list of what the Telegram import can't do");

String get labelTelegramImportCantReadChats => Intl.message(
    "Read your chats, contacts or files, send messages, or change anything in your account.",
    name: "labelTelegramImportCantReadChats",
    desc: "What the Telegram import can't do");

String get labelTelegramImportCantAllowlist =>
    Intl.message("The app only allows the calls it needs to list your packs.",
        name: "labelTelegramImportCantAllowlist",
        desc: "Second point under 'Vommet can't'");

String get labelTelegramImportStepScan => Intl.message(
    "You scan a QR code with Telegram on your phone. Telegram will alert you about a new login named \"Vommet sticker import\".",
    name: "labelTelegramImportStepScan",
    desc: "Step 1 of the Telegram import explanation");

String get labelTelegramImportStepSignOut => Intl.message(
    "Vommet reads your pack list and signs out straight away, before you pick anything. Nothing about your Telegram account is saved.",
    name: "labelTelegramImportStepSignOut",
    desc: "Step 2 of the Telegram import explanation");

String labelTelegramImportStepChoose(String proxy) => Intl.message(
    "You choose which packs to import. They download through $proxy like any pack link, so $proxy sees which packs you import.",
    args: [proxy],
    name: "labelTelegramImportStepChoose",
    desc: "Step 3 of the Telegram import explanation; proxy is a host name");

String get labelTelegramImportRisk => Intl.message(
    "Telegram sometimes flags logins from apps it doesn't know. The risk from one short, read-only login is small, but it isn't zero. If Vommet is closed partway through, end the session yourself in Telegram › Settings › Devices.",
    name: "labelTelegramImportRisk",
    desc: "Warning before the Telegram import signs in");

String get promptTelegramImportShowQr => Intl.message("Show QR code",
    name: "promptTelegramImportShowQr",
    desc: "Button that starts the Telegram login with a QR code");

String get promptTelegramImportContinue => Intl.message("Continue",
    name: "promptTelegramImportContinue",
    desc: "Button that starts the Telegram login on a phone");

String get promptTelegramImportCancel => Intl.message("Cancel",
    name: "promptTelegramImportCancel",
    desc: "Cancels the Telegram account import");

String get promptTelegramImportBack => Intl.message("Back",
    name: "promptTelegramImportBack",
    desc: "Goes back from the Telegram account import to the import dialog");

String get promptTelegramImportTryAgain => Intl.message("Try again",
    name: "promptTelegramImportTryAgain",
    desc: "Starts the Telegram account import again after it failed");

String get labelTelegramImportConnecting =>
    Intl.message("Connecting to Telegram…",
        name: "labelTelegramImportConnecting",
        desc: "Shown while the Telegram login is being prepared");

String get labelTelegramImportReading =>
    Intl.message("Reading your packs and signing out…",
        name: "labelTelegramImportReading",
        desc: "Shown after the Telegram login worked");

String labelTelegramImportNewCodeIn(int seconds) =>
    Intl.message("New code in $seconds s",
        args: [seconds],
        name: "labelTelegramImportNewCodeIn",
        desc: "Under the Telegram login QR code: seconds until it's replaced");

String get labelTelegramImportQrStepOpen =>
    Intl.message("Open Telegram on your phone.",
        name: "labelTelegramImportQrStepOpen",
        desc: "Step 1 next to the Telegram login QR code");

String get labelTelegramImportQrStepDevices =>
    Intl.message("Go to Settings › Devices › Link Desktop Device.",
        name: "labelTelegramImportQrStepDevices",
        desc: "Step 2 next to the Telegram login QR code");

String get labelTelegramImportQrStepPoint => Intl.message(
    "Point your phone at this code. The login is named \"Vommet sticker import\".",
    name: "labelTelegramImportQrStepPoint",
    desc: "Step 3 next to the Telegram login QR code");

String get labelTelegramImportQrWarning => Intl.message(
    "Only scan a code that your own Vommet shows you. Anyone who sends you a Telegram login QR code is trying to get into your account.",
    name: "labelTelegramImportQrWarning",
    desc: "Warning next to the Telegram login QR code");

String get labelTelegramImportCodeNotShared => Intl.message(
    "This code can't be copied or shared. Have two-step verification on? Vommet asks for your password next.",
    name: "labelTelegramImportCodeNotShared",
    desc: "Note under the Telegram login QR code on desktop");

String get labelTelegramImportApproveInApp => Intl.message(
    "Telegram opens and asks you to confirm the login \"Vommet sticker import\". Then come back here.",
    name: "labelTelegramImportApproveInApp",
    desc: "Phone: explains the Open Telegram button");

String get promptTelegramImportOpenTelegram => Intl.message("Open Telegram",
    name: "promptTelegramImportOpenTelegram",
    desc: "Phone: hands the login to the Telegram app");

String get promptTelegramImportShowQrOther =>
    Intl.message("Telegram on another device? Show QR code",
        name: "promptTelegramImportShowQrOther",
        desc: "Phone: shows the login QR code instead");

String get labelTelegramImportApproveWarning => Intl.message(
    "Only approve a login that you started just now in Vommet. If Telegram shows a different app name, deny it.",
    name: "labelTelegramImportApproveWarning",
    desc: "Phone: warning on the approve-in-Telegram step");

String get labelTelegramImportScreenshotsBlocked => Intl.message(
    "Screenshots and screen recording are blocked on this screen. The login link goes straight to the Telegram app and is never shown or copied.",
    name: "labelTelegramImportScreenshotsBlocked",
    desc: "Android: note on the Telegram login step");

String get labelTelegramImportWaiting => Intl.message("Waiting for Telegram…",
    name: "labelTelegramImportWaiting",
    desc: "Shown while waiting for the user to approve the Telegram login");

String get labelTelegramImportPasswordIntro => Intl.message(
    "Your Telegram account has a cloud password. Enter it to finish signing in.",
    name: "labelTelegramImportPasswordIntro",
    desc: "Telegram two-step verification step");

String get labelTelegramImportPassword => Intl.message("Telegram password",
    name: "labelTelegramImportPassword",
    desc: "Label of the Telegram cloud password field");

String labelTelegramImportPasswordHint(String hint) =>
    Intl.message("Hint from Telegram: \"$hint\"",
        args: [hint],
        name: "labelTelegramImportPasswordHint",
        desc: "The user's own password hint, from Telegram");

String get labelTelegramImportPasswordWrong =>
    Intl.message("That password isn't right. Try again.",
        name: "labelTelegramImportPasswordWrong",
        desc: "Telegram said the cloud password was wrong");

String get labelTelegramImportPasswordLocal => Intl.message(
    "Your password is checked on this device the way Telegram's own apps do it, and is never sent as plain text. Vommet forgets it as soon as you're signed in.",
    name: "labelTelegramImportPasswordLocal",
    desc: "Explains how the Telegram cloud password is handled");

String get promptTelegramImportSignIn => Intl.message("Sign in",
    name: "promptTelegramImportSignIn",
    desc: "Sends the Telegram cloud password");

String get labelTelegramImportSignOutUnconfirmed => Intl.message(
    "Vommet asked Telegram to end its session, but Telegram didn't answer. The session may still be active.",
    name: "labelTelegramImportSignOutUnconfirmed",
    desc: "The Telegram sign-out wasn't confirmed");

String get labelTelegramImportEndItYourself =>
    Intl.message("To be sure, end it yourself in Telegram:",
        name: "labelTelegramImportEndItYourself",
        desc: "Before the steps to end the Telegram session by hand");

String get labelTelegramImportEndStepDevices =>
    Intl.message("Open Settings › Devices.",
        name: "labelTelegramImportEndStepDevices",
        desc: "Step 1 of ending the Telegram session by hand");

String get labelTelegramImportEndStepTerminate =>
    Intl.message("Tap \"Vommet sticker import\", then Terminate Session.",
        name: "labelTelegramImportEndStepTerminate",
        desc: "Step 2 of ending the Telegram session by hand");

String get labelTelegramImportSessionInMemory => Intl.message(
    "Vommet holds the session in memory only so it can try again, and throws it away when you leave this screen. It's never saved.",
    name: "labelTelegramImportSessionInMemory",
    desc: "Explains what happens to an unconfirmed Telegram session");

String get promptTelegramImportRetrySignOut =>
    Intl.message("Try signing out again",
        name: "promptTelegramImportRetrySignOut",
        desc: "Asks Telegram again to end the session");

String get promptTelegramImportEndedIt =>
    Intl.message("I've ended it, continue",
        name: "promptTelegramImportEndedIt",
        desc: "The user ended the Telegram session by hand; go on");

String get labelTelegramImportNoPacks => Intl.message(
    "Signed out of Telegram. Your account has no sticker or emoji packs to import.",
    name: "labelTelegramImportNoPacks",
    desc: "The Telegram account has no packs");

String labelTelegramImportFailed(String reason) =>
    Intl.message("The Telegram import stopped ($reason).",
        args: [reason],
        name: "labelTelegramImportFailed",
        desc: "The Telegram import failed; reason is a short error name");

String get labelTelegramImportSignedOutBanner => Intl.message(
    "Signed out of Telegram. Vommet got your pack list and ended its session. Nothing from your Telegram account was saved.",
    name: "labelTelegramImportSignedOutBanner",
    desc: "Banner above the pack list after the Telegram account import");
