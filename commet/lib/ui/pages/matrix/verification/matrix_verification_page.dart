import 'package:commet/debug/log.dart';
import 'package:commet/ui/pages/matrix/verification/matrix_verification_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:matrix/encryption/utils/key_verification.dart';

class MatrixVerificationPage extends StatefulWidget {
  final KeyVerification request;

  /// Vommet: starts a new verification after this one ended (shows a
  /// "Start again" button).
  final VoidCallback? onRestart;

  const MatrixVerificationPage(
      {required this.request, this.onRestart, super.key});

  @override
  State<MatrixVerificationPage> createState() => MatrixVerificationPageState();
}

class MatrixVerificationPageState extends State<MatrixVerificationPage> {
  void Function()? originalOnUpdate;

  // Vommet: the SDK frees the emoji/numbers once the comparison is answered;
  // keep them so "waiting for the other side" can still show them.
  List<String> sasTypes = [];
  List<KeyVerificationEmoji> sasEmoji = [];
  List<int> sasNumbers = [];
  bool cancelledHere = false;
  bool busy = false;
  String? recoveryKeyError;
  bool _closed = false;

  static String get messageVerifyHandledElsewhereToast => Intl.message(
      "Verification request answered on another device",
      name: "messageVerifyHandledElsewhereToast",
      desc:
          "Toast when another of the user's devices answered a verification request this device was also showing");

  String get labelVerifyOtherDevice => Intl.message("your other device",
      name: "labelVerifyOtherDevice",
      desc: "Stands in for a device name when it isn't known yet");

  String get messageVerifyRecoveryKeyWrong =>
      Intl.message("That key or passphrase didn't work",
          name: "messageVerifyRecoveryKeyWrong",
          desc: "Error under the recovery key field while verifying");

  @override
  void initState() {
    super.initState();

    originalOnUpdate = widget.request.onUpdate;
    widget.request.onUpdate = () {
      originalOnUpdate?.call();
      if (mounted) onUpdate();
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onUpdate();
    });
  }

  void onUpdate() {
    final request = widget.request;
    if (request.state == KeyVerificationState.askSas) {
      try {
        sasTypes = request.sasTypes;
        sasEmoji = request.sasTypes.contains('emoji') ? request.sasEmojis : [];
        sasNumbers = request.sasNumbers;
      } catch (e, s) {
        Log.onError(e, s, content: "Couldn't read the verification codes");
      }
    }
    // Vommet: another of our devices answered a request that went to all of
    // them. Nothing to do here: close quietly and say why.
    if (request.state == KeyVerificationState.error &&
        request.canceledCode == "m.accepted" &&
        !cancelledHere &&
        _inPopup) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      _close();
      messenger?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(children: [
          const Icon(Icons.task_alt_rounded, color: Color(0xff3ba55d)),
          const SizedBox(width: 10),
          Expanded(child: Text(messageVerifyHandledElsewhereToast)),
        ]),
      ));
      return;
    }
    setState(() {});
  }

  /// In a dialog or bottom sheet (rather than embedded in a page), so the
  /// page may close itself.
  bool get _inPopup => ModalRoute.of(context) is PopupRoute;

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    if (_inPopup) Navigator.of(context).maybePop();
  }

  bool get ownUser => widget.request.userId == widget.request.client.userID;

  /// The other device's name, or the other person's.
  String get otherName {
    final request = widget.request;
    if (ownUser) {
      final id = request.deviceId;
      final keys = id == null || id == "*"
          ? null
          : request.client.userDeviceKeys[request.userId]?.deviceKeys[id];
      final name = keys?.deviceDisplayName;
      if (name != null && name.isNotEmpty) return name;
      return id == null || id == "*" ? labelVerifyOtherDevice : id;
    }
    final member = request.room?.unsafeGetUserFromMemoryOrFallback(
      request.userId,
    );
    return member?.calcDisplayname() ?? request.userId;
  }

  String? get otherDetail {
    final request = widget.request;
    if (!ownUser) return request.userId;
    final id = request.deviceId;
    return id == null || id == "*" ? null : id;
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return MatrixVerificationPageView(
      state: request.state,
      sasTypes: sasTypes,
      sasEmoji: sasEmoji,
      sasNumbers: sasNumbers,
      userID: request.userId,
      ownUser: ownUser,
      otherName: otherName,
      otherDetail: otherDetail,
      startedHere: request.startedVerification,
      canceledCode: request.canceledCode,
      cancelledHere: cancelledHere,
      recoveryKeyError: recoveryKeyError,
      busy: busy,
      onSasAccepted: acceptSas,
      onSasRejected: rejectSas,
      onVerificationRequestAccepted: acceptRequest,
      onVerificationRequestRejected: rejectRequest,
      onCancel: cancel,
      onRecoveryKey: unlockWithRecoveryKey,
      onSkipRecoveryKey: skipRecoveryKey,
      onClose: _close,
      onRestart: widget.onRestart == null
          ? null
          : () {
              _close();
              widget.onRestart!();
            },
    );
  }

  void acceptRequest() async {
    setState(() => busy = true);
    try {
      await widget.request.acceptVerification();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void rejectRequest() async {
    cancelledHere = true;
    await widget.request.rejectVerification();
    _close();
  }

  void cancel() async {
    cancelledHere = true;
    await widget.request.cancel('m.user');
    _close();
  }

  void acceptSas() async {
    await widget.request.acceptSas();
  }

  void rejectSas() async {
    await widget.request.rejectSas();
  }

  void unlockWithRecoveryKey(String key) async {
    setState(() {
      busy = true;
      recoveryKeyError = null;
    });
    try {
      await widget.request.openSSSS(keyOrPassphrase: key);
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't unlock with the recovery key");
      if (mounted) {
        setState(() => recoveryKeyError = messageVerifyRecoveryKeyWrong);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void skipRecoveryKey() async {
    await widget.request.openSSSS(skip: true);
  }
}
