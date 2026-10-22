import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: how a verification ended, from the SDK's cancel code.
enum VerificationEnd {
  /// Another of our devices answered a request sent to all of them.
  handledElsewhere,
  cancelledHere,
  cancelledThere,
  expired,
  mismatch,
  failed,
}

VerificationEnd verificationEndFor(String? code, {required bool here}) {
  if (here) return VerificationEnd.cancelledHere;
  switch (code) {
    case "m.accepted":
      return VerificationEnd.handledElsewhere;
    case "m.user":
      return VerificationEnd.cancelledThere;
    case "m.timeout":
      return VerificationEnd.expired;
    case "m.mismatched_sas":
    case "m.key_mismatch":
    case "m.mismatched_commitment":
      return VerificationEnd.mismatch;
    default:
      return VerificationEnd.failed;
  }
}

/// Vommet: one layout for every state of a verification (icon, headline,
/// explanation, optional middle part, buttons), instead of raw state names.
class MatrixVerificationPageView extends StatelessWidget {
  const MatrixVerificationPageView(
      {required this.state,
      required this.sasTypes,
      required this.sasNumbers,
      required this.sasEmoji,
      required this.userID,
      required this.ownUser,
      required this.otherName,
      this.otherDetail,
      this.startedHere = false,
      this.awaitingAnswer = false,
      this.canceledCode,
      this.cancelledHere = false,
      this.recoveryKeyError,
      this.busy = false,
      super.key,
      this.onVerificationRequestAccepted,
      this.onVerificationRequestRejected,
      this.onSasAccepted,
      this.onSasRejected,
      this.onCancel,
      this.onRecoveryKey,
      this.onSkipRecoveryKey,
      this.onClose,
      this.onRestart});

  final Function? onVerificationRequestAccepted;
  final Function? onVerificationRequestRejected;
  final Function? onSasAccepted;
  final Function? onSasRejected;
  final VoidCallback? onCancel;
  final void Function(String key)? onRecoveryKey;
  final VoidCallback? onSkipRecoveryKey;
  final VoidCallback? onClose;
  final VoidCallback? onRestart;
  final List<String> sasTypes;
  final List<KeyVerificationEmoji> sasEmoji;
  final List<int> sasNumbers;
  final String userID;

  /// Verifying one of our own devices (rather than another person).
  final bool ownUser;

  /// The other device's name, or the other person's name.
  final String otherName;

  /// Second line under [otherName]: device ID or Matrix ID.
  final String? otherDetail;
  final bool startedHere;

  /// Vommet: we sent the request and nothing has come back yet. Only then is
  /// the other side still to accept; afterwards waitingAccept/askChoice mean
  /// the two devices are exchanging keys.
  final bool awaitingAnswer;
  final String? canceledCode;
  final bool cancelledHere;
  final String? recoveryKeyError;
  final bool busy;

  final KeyVerificationState state;

  String get messageVerifyOwnRequest => Intl.message(
      "One of your devices wants to be verified",
      name: "messageVerifyOwnRequest",
      desc: "Headline when another of the user's own devices asks to verify");

  String get messageVerifyOwnRequestBody => Intl.message(
      "Verifying lets it read your encrypted messages and marks it as yours.",
      name: "messageVerifyOwnRequestBody",
      desc: "Explains what accepting a verification from an own device does");

  String get messageVerifyOwnRequestWarning => Intl.message(
      "Only accept if you just asked for this on that device. If you didn't, decline. Someone may be trying to get into your account.",
      name: "messageVerifyOwnRequestWarning",
      desc: "Warning under an own-device verification request");

  String messageVerifyUserRequest(String name) =>
      Intl.message("$name wants to verify you",
          args: [name],
          name: "messageVerifyUserRequest",
          desc: "Headline when another person asks to verify the user");

  String get messageVerifyUserRequestBody => Intl.message(
      "You'll compare a few emoji with each other, ideally in person or on a call.",
      name: "messageVerifyUserRequestBody",
      desc: "Explains how verifying another person works");

  String get messageVerifyWaitingAccept => Intl.message(
      "Accept on another device",
      name: "messageVerifyWaitingAccept",
      desc: "Headline while waiting for another device to accept our request");

  String get messageVerifyWaitingAcceptBody => Intl.message(
      "Open Vommet (or another Matrix app) on the other device and accept the request.",
      name: "messageVerifyWaitingAcceptBody",
      desc: "Explains what to do while waiting for another device to accept");

  String messageVerifyWaitingUser(String name) => Intl.message(
      "Waiting for $name to accept",
      args: [name],
      name: "messageVerifyWaitingUser",
      desc: "Headline while waiting for another person to accept our request");

  String get messageVerifyConnecting =>
      Intl.message("Setting up a secure check…",
          name: "messageVerifyConnecting",
          desc: "Headline after a verification was accepted, before the emoji");

  String messageVerifyConnectingBody(String name) =>
      Intl.message("Connecting to $name. This only takes a moment.",
          args: [name],
          name: "messageVerifyConnectingBody",
          desc: "Body after a verification was accepted, before the emoji");

  String get messageVerifyCompareEmoji => Intl.message("Compare emoji",
      name: "messageVerifyCompareEmoji",
      desc: "Headline above the emoji to compare");

  String messageVerifyCompareEmojiBody(String name) => Intl.message(
      "Check that $name shows the same emoji in the same order.",
      args: [name],
      name: "messageVerifyCompareEmojiBody",
      desc:
          "Explains the emoji comparison. Must say same emoji AND same order");

  String get messageVerifyCompareNumbers => Intl.message("Compare numbers",
      name: "messageVerifyCompareNumbers",
      desc: "Headline above the numbers to compare");

  String messageVerifyCompareNumbersBody(String name) =>
      Intl.message("Check that $name shows these numbers in this order.",
          args: [name],
          name: "messageVerifyCompareNumbersBody",
          desc: "Explains the number comparison");

  String get messageVerifyWaitingConfirm =>
      Intl.message("Waiting for the other side",
          name: "messageVerifyWaitingConfirm",
          desc: "Headline after the user confirmed the emoji matched");

  String messageVerifyWaitingConfirmBody(String name) =>
      Intl.message("You confirmed the match. Now confirm it on $name too.",
          args: [name],
          name: "messageVerifyWaitingConfirmBody",
          desc: "Body after the user confirmed the emoji matched");

  String get messageVerifyRecoveryKey => Intl.message("One more step",
      name: "messageVerifyRecoveryKey",
      desc: "Headline when the recovery key is needed to finish verifying");

  String messageVerifyRecoveryKeyBody(String name) => Intl.message(
      "The emoji matched. To vouch for $name so your other devices and contacts trust it too, enter your recovery key.",
      args: [name],
      name: "messageVerifyRecoveryKeyBody",
      desc: "Body when the recovery key is needed to finish verifying");

  String get labelVerifyRecoveryKey =>
      Intl.message("Recovery key or passphrase",
          name: "labelVerifyRecoveryKey",
          desc: "Hint of the recovery key field while verifying");

  String get promptVerifySkip => Intl.message("Skip for now",
      name: "promptVerifySkip",
      desc: "Button to finish verifying without the recovery key");

  String messageVerifyDone(String name) => Intl.message("$name is verified",
      args: [name],
      name: "messageVerifyDone",
      desc: "Headline when a device or person was verified");

  String get messageVerifyDoneThisDevice =>
      Intl.message("This device is verified",
          name: "messageVerifyDoneThisDevice",
          desc: "Headline when this device was verified by another one");

  String get messageVerifyDoneOwnBody => Intl.message(
      "Your encrypted messages are shared with it, and your contacts will see it as yours.",
      name: "messageVerifyDoneOwnBody",
      desc: "Body when one of the user's devices was verified");

  String get messageVerifyDoneUserBody => Intl.message(
      "You'll see a check next to their name. If their devices change, Vommet will tell you.",
      name: "messageVerifyDoneUserBody",
      desc: "Body when another person was verified");

  String get messageVerifyHandledElsewhere => Intl.message(
      "Handled on another device",
      name: "messageVerifyHandledElsewhere",
      desc: "Headline when another of the user's devices answered the request");

  String get messageVerifyHandledElsewhereBody => Intl.message(
      "Another of your devices answered this request, so there's nothing to do here.",
      name: "messageVerifyHandledElsewhereBody",
      desc: "Body when another of the user's devices answered the request");

  String get messageVerifyCancelled => Intl.message("Verification cancelled",
      name: "messageVerifyCancelled",
      desc: "Headline when a verification was cancelled");

  String messageVerifyCancelledThere(String name) =>
      Intl.message("It was cancelled on $name. Nothing was changed.",
          args: [name],
          name: "messageVerifyCancelledThere",
          desc: "Body when the other side cancelled a verification");

  String get messageVerifyCancelledHere =>
      Intl.message("You cancelled it. Nothing was changed.",
          name: "messageVerifyCancelledHere",
          desc: "Body when the user cancelled a verification");

  String get messageVerifyExpired => Intl.message("Request expired",
      name: "messageVerifyExpired",
      desc: "Headline when a verification timed out");

  String get messageVerifyExpiredBody => Intl.message(
      "Nobody answered within 10 minutes. Make sure Vommet or another Matrix app is open on the other device, then try again.",
      name: "messageVerifyExpiredBody",
      desc: "Body when a verification timed out");

  String get messageVerifyMismatch => Intl.message("The emoji didn't match",
      name: "messageVerifyMismatch",
      desc: "Headline when the compared emoji or keys didn't match");

  String messageVerifyMismatchBody(String name) => Intl.message(
      "Verification stopped and $name was not trusted. If you're sure both screens were the right ones, try again.",
      args: [name],
      name: "messageVerifyMismatchBody",
      desc: "Body when the compared emoji or keys didn't match");

  String get messageVerifyMismatchWarning => Intl.message(
      "If they still don't match, someone may be interfering with your connection. Don't trust the device, and sign out of any session you don't recognise in Settings › Security.",
      name: "messageVerifyMismatchWarning",
      desc: "Security warning after a mismatch");

  String get messageVerifyFailed => Intl.message("Verification failed",
      name: "messageVerifyFailed",
      desc: "Headline when a verification failed for another reason");

  String get messageVerifyFailedBody => Intl.message(
      "The other app sent something Vommet didn't expect. Updating both apps usually fixes this.",
      name: "messageVerifyFailedBody",
      desc: "Body when a verification failed for another reason");

  String get labelVerifyDetails => Intl.message("Details",
      name: "labelVerifyDetails",
      desc: "Label in front of the technical error code");

  String get promptVerifyStartAgain => Intl.message("Start again",
      name: "promptVerifyStartAgain",
      desc: "Button to start a new verification after one ended");

  String get promptVerifyClose => Intl.message("Close",
      name: "promptVerifyClose", desc: "Button to close the verification");

  String get promptConfirmEmojiMatches => Intl.message("They match!",
      name: "promptConfirmEmojiMatches",
      desc: "Button text to confirm that the emoji matches");

  String get promptEmojiDoNotMatch => Intl.message("They don't match",
      name: "promptEmojiDoNotMatch",
      desc: "Button text to confirm that the emoji do NOT match");

  String get messageVerificationComplete => Intl.message(
      "Verification Complete!",
      name: "messageVerificationComplete",
      desc:
          "Message to show when verification was completed successfully, and the session has been verified");

  static const _green = Color(0xff3ba55d);
  static const _amber = Color(0xffe0a43a);
  static const _red = Color(0xffed4245);

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: determineStage(context),
      ),
    );
    // Scrolls when embedded in a page (secure setup); a scroll view also
    // reports intrinsic sizes, which AlertDialog asks its content for.
    return SingleChildScrollView(child: Center(child: content));
  }

  Widget determineStage(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    switch (state) {
      case KeyVerificationState.askAccept:
        return _layout(
          context,
          badge: _badge(
              ownUser ? Icons.devices_rounded : Icons.person_search_rounded,
              primary),
          headline: ownUser
              ? messageVerifyOwnRequest
              : messageVerifyUserRequest(otherName),
          body: ownUser
              ? messageVerifyOwnRequestBody
              : messageVerifyUserRequestBody,
          middle: _chip(context),
          footnote: ownUser
              ? _foot(context, messageVerifyOwnRequestWarning,
                  Icons.shield_outlined)
              : null,
          buttons: [
            tiamat.Button(
                text: CommonStrings.promptAccept,
                isLoading: busy,
                onTap: onVerificationRequestAccepted?.call),
            tiamat.Button.secondary(
                text: CommonStrings.promptDecline,
                onTap: onVerificationRequestRejected?.call),
          ],
        );
      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.askChoice:
        if (!awaitingAnswer) {
          return _layout(
            context,
            badge: _badge(Icons.sync_lock_rounded, primary, spinner: true),
            headline: messageVerifyConnecting,
            body: messageVerifyConnectingBody(otherName),
            buttons: [_cancelButton()],
          );
        }
        return _layout(
          context,
          badge: _badge(Icons.phonelink_ring_rounded, primary, spinner: true),
          headline: ownUser
              ? messageVerifyWaitingAccept
              : messageVerifyWaitingUser(otherName),
          body: ownUser ? messageVerifyWaitingAcceptBody : null,
          buttons: [_cancelButton()],
        );
      case KeyVerificationState.waitingSas:
        if (sasEmoji.isEmpty && sasNumbers.isEmpty) {
          return _layout(
            context,
            badge: _badge(Icons.sync_lock_rounded, primary, spinner: true),
            headline: messageVerifyConnecting,
            body: messageVerifyConnectingBody(otherName),
            buttons: [_cancelButton()],
          );
        }
        return _layout(
          context,
          badge: _badge(Icons.hourglass_top_rounded, primary, spinner: true),
          headline: messageVerifyWaitingConfirm,
          body: messageVerifyWaitingConfirmBody(otherName),
          middle: Opacity(opacity: 0.45, child: _comparison(context)),
          buttons: [_cancelButton()],
        );
      case KeyVerificationState.askSas:
        final emoji = sasTypes.contains('emoji') && sasEmoji.isNotEmpty;
        return _layout(
          context,
          badge: _badge(
              emoji ? Icons.compare_arrows_rounded : Icons.pin_outlined,
              primary),
          headline:
              emoji ? messageVerifyCompareEmoji : messageVerifyCompareNumbers,
          body: emoji
              ? messageVerifyCompareEmojiBody(otherName)
              : messageVerifyCompareNumbersBody(otherName),
          middle: _comparison(context),
          buttons: [
            tiamat.Button.success(
                text: promptConfirmEmojiMatches, onTap: onSasAccepted?.call),
            tiamat.Button.danger(
                text: promptEmojiDoNotMatch, onTap: onSasRejected?.call),
          ],
        );
      case KeyVerificationState.askSSSS:
        return _RecoveryKeyStep(
          view: this,
          badge: _badge(Icons.key_rounded, _amber),
        );
      case KeyVerificationState.done:
        return _layout(
          context,
          badge: _badge(
              ownUser ? Icons.verified_user_rounded : Icons.verified_rounded,
              _green),
          headline: ownUser && startedHere
              ? messageVerifyDoneThisDevice
              : messageVerifyDone(otherName),
          body: ownUser ? messageVerifyDoneOwnBody : messageVerifyDoneUserBody,
          buttons: [
            tiamat.Button.success(
                text: messageVerificationComplete, onTap: onClose),
          ],
        );
      case KeyVerificationState.error:
        return ended(
            context, verificationEndFor(canceledCode, here: cancelledHere));
      default:
        // QR states: Vommet only offers emoji, so these don't normally occur.
        return _layout(
          context,
          badge: _badge(Icons.sync_lock_rounded, primary, spinner: true),
          headline: messageVerifyConnecting,
          body: messageVerifyConnectingBody(otherName),
          buttons: [_cancelButton()],
        );
    }
  }

  Widget ended(BuildContext context, VerificationEnd end) {
    final close =
        tiamat.Button.secondary(text: promptVerifyClose, onTap: onClose);
    final restart = onRestart == null
        ? null
        : tiamat.Button(text: promptVerifyStartAgain, onTap: onRestart);
    switch (end) {
      case VerificationEnd.handledElsewhere:
        return _layout(context,
            badge: _badge(Icons.task_alt_rounded, _green),
            headline: messageVerifyHandledElsewhere,
            body: messageVerifyHandledElsewhereBody,
            buttons: [close]);
      case VerificationEnd.cancelledHere:
      case VerificationEnd.cancelledThere:
        return _layout(context,
            badge: _badge(Icons.do_not_disturb_on_outlined, _amber),
            headline: messageVerifyCancelled,
            body: end == VerificationEnd.cancelledHere
                ? messageVerifyCancelledHere
                : messageVerifyCancelledThere(otherName),
            buttons: [if (restart != null) restart, close]);
      case VerificationEnd.expired:
        return _layout(context,
            badge: _badge(Icons.timer_off_outlined, _amber),
            headline: messageVerifyExpired,
            body: messageVerifyExpiredBody,
            buttons: [if (restart != null) restart, close]);
      case VerificationEnd.mismatch:
        return _layout(context,
            badge: _badge(Icons.gpp_bad_rounded, _red),
            headline: messageVerifyMismatch,
            body: messageVerifyMismatchBody(otherName),
            footnote: _foot(context, messageVerifyMismatchWarning,
                Icons.warning_amber_rounded),
            buttons: [if (restart != null) restart, close]);
      case VerificationEnd.failed:
        return _layout(context,
            badge: _badge(Icons.error_outline_rounded, _red),
            headline: messageVerifyFailed,
            body: messageVerifyFailedBody,
            footnote: _foot(context,
                "$labelVerifyDetails: ${canceledCode ?? "unknown"}", null),
            buttons: [if (restart != null) restart, close]);
    }
  }

  Widget _cancelButton() => tiamat.Button.secondary(
      text: CommonStrings.promptCancel, onTap: onCancel);

  Widget _layout(
    BuildContext context, {
    required Widget badge,
    required String headline,
    String? body,
    Widget? middle,
    Widget? footnote,
    List<Widget> buttons = const [],
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      badge,
      const SizedBox(height: 14),
      Text(headline,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: "NunitoSans",
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface)),
      if (body != null) ...[
        const SizedBox(height: 8),
        Text(body,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14.5, height: 1.4, color: scheme.onSurfaceVariant)),
      ],
      if (middle != null) ...[const SizedBox(height: 18), middle],
      if (footnote != null) ...[const SizedBox(height: 14), footnote],
      const SizedBox(height: 10),
      for (final b in buttons)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(height: 40, width: double.infinity, child: b),
        ),
    ]);
  }

  Widget _badge(IconData icon, Color color, {bool spinner = false}) => SizedBox(
        width: 64,
        height: 64,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withAlpha(36)),
          ),
          if (spinner)
            SizedBox.expand(
                child: CircularProgressIndicator(strokeWidth: 3, color: color)),
          Icon(icon, size: 32, color: color),
        ]),
      );

  Widget _tile(BuildContext context,
          {required Widget child, EdgeInsets? padding}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withAlpha(140),
            borderRadius: BorderRadius.circular(10)),
        child: child,
      );

  Widget _chip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _tile(context,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ownUser ? Icons.devices_other_rounded : Icons.person_rounded,
              size: 26, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(otherName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface)),
                  if (otherDetail != null)
                    Text(otherDetail!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
          ),
        ]));
  }

  // Rows rather than Wrap: Wrap leaves its spacing out of its intrinsic
  // width, and AlertDialog sizes itself from that, so it wrapped early.
  Widget _comparison(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sasEmoji.isNotEmpty && sasTypes.contains('emoji')) {
      Widget tile(KeyVerificationEmoji e) => Padding(
            padding: const EdgeInsets.all(4),
            child: _tile(context,
                child: SizedBox(
                  width: 78,
                  height: 84,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        EmojiWidget(UnicodeEmoticon(e.emoji), height: 40),
                        const SizedBox(height: 6),
                        Text(e.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant)),
                      ]),
                )),
          );
      // Scales down on narrow phones instead of overflowing.
      return FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < sasEmoji.length; i += 4)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final e in sasEmoji.skip(i).take(4)) tile(e)],
              ),
          ]));
    }
    return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final n in sasNumbers)
              Padding(
                padding: const EdgeInsets.all(5),
                child: _tile(context,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Text(n.toString().padLeft(4, "0"),
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: scheme.onSurface))),
              ),
          ],
        ));
  }

  Widget _foot(BuildContext context, String text, IconData? icon) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
      ],
      Expanded(
          child: Text(text,
              textAlign: icon == null ? TextAlign.center : TextAlign.start,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: color))),
    ]);
  }
}

class _RecoveryKeyStep extends StatefulWidget {
  const _RecoveryKeyStep({required this.view, required this.badge});
  final MatrixVerificationPageView view;
  final Widget badge;

  @override
  State<_RecoveryKeyStep> createState() => _RecoveryKeyStepState();
}

class _RecoveryKeyStepState extends State<_RecoveryKeyStep> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final key = controller.text.trim();
    if (key.isEmpty || widget.view.busy) return;
    widget.view.onRecoveryKey?.call(key);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    return v._layout(
      context,
      badge: widget.badge,
      headline: v.messageVerifyRecoveryKey,
      body: v.messageVerifyRecoveryKeyBody(v.otherName),
      middle: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        onSubmitted: (_) => submit(),
        decoration: InputDecoration(
          hintText: v.labelVerifyRecoveryKey,
          errorText: v.recoveryKeyError,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
      buttons: [
        tiamat.Button(
            text: CommonStrings.promptContinue,
            isLoading: v.busy,
            onTap: submit),
        tiamat.Button.secondary(
            text: v.promptVerifySkip, onTap: v.onSkipRecoveryKey),
      ],
    );
  }
}
