import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/tiny_pill.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What this device knows about a session's encryption keys.
enum SessionKeysState { loading, missing, known }

class MatrixSessionView extends StatelessWidget {
  const MatrixSessionView(
      {this.displayName,
      required this.deviceId,
      this.lastSeenIp,
      this.lastSeenTimestamp,
      super.key,
      this.verified = false,
      this.keysState = SessionKeysState.known,
      this.isThisDevice = false,
      this.inactive = false,
      this.beginVerification,
      this.removeSession});

  final String? displayName;
  final String deviceId;
  final String? lastSeenIp;
  final int? lastSeenTimestamp;
  final bool verified;

  /// Whether this device knows the session's encryption keys. Without them
  /// (the session never uploaded any) there is nothing to verify against;
  /// while the device list is still loading we can't tell yet.
  final SessionKeysState keysState;
  final bool isThisDevice;
  final bool inactive;
  final Function? beginVerification;
  final Function? removeSession;

  String get promptMatrixVerifySession => Intl.message("Verify",
      desc: "Text on the button to verify a session",
      name: "promptMatrixVerifySession");

  String get labelMatrixSessionCannotVerify => Intl.message("Can't verify",
      desc:
          "Shown instead of the verify button for a session whose encryption keys are unknown",
      name: "labelMatrixSessionCannotVerify");

  String get labelMatrixSessionCannotVerifyExplanation => Intl.message(
      "This session hasn't shared its encryption keys, so it can't be verified. Sessions that don't support encryption (some bots and older sign-ins) never do.",
      desc:
          "Explains why a session whose encryption keys are unknown can't be verified",
      name: "labelMatrixSessionCannotVerifyExplanation");

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(5)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8.0, 16, 16, 16),
                      child: Icon(
                        getIcon(),
                        color: verified ? Colors.green : Colors.redAccent,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (displayName != null)
                          tiamat.Text.labelEmphasised(displayName!),
                        Row(
                          children: [
                            if (isThisDevice)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(0, 0, 8, 0),
                                child: TinyPill("This Device"),
                              ),
                            if (inactive)
                              Padding(
                                padding: EdgeInsets.fromLTRB(0, 0, 8, 0),
                                child: TinyPill(
                                  "Inactive",
                                  background: ColorScheme.of(context).error,
                                  foreground: ColorScheme.of(context).onError,
                                ),
                              ),
                            tiamat.Text.labelLow(deviceId),
                          ],
                        ),
                        if (lastSeenTimestamp != null)
                          tiamat.Text.tiny(
                              "Last Seen: ${DateFormat(DateFormat.YEAR_MONTH_WEEKDAY_DAY).format(DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp!))}"),
                        if (lastSeenIp != null)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
                            child: SizedBox(
                              width: 10,
                              child: tiamat.Seperator(
                                padding: 0,
                              ),
                            ),
                          ),
                        if (lastSeenIp != null) tiamat.Text.tiny(lastSeenIp!),
                      ],
                    ),
                  ],
                ),
                if (MediaQuery.of(context).desktop) verifyButton()
              ],
            ),
            if (MediaQuery.of(context).mobile) Align(child: verifyButton()),
          ],
        ),
      ),
    );
  }

  Row verifyButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (verified == false && keysState == SessionKeysState.known)
          tiamat.Button.secondary(
            text: promptMatrixVerifySession,
            onTap: () => beginVerification?.call(),
          ),
        if (verified == false && keysState == SessionKeysState.missing)
          Tooltip(
            message: labelMatrixSessionCannotVerifyExplanation,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tiamat.Text.labelLow(labelMatrixSessionCannotVerify),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 0, 0),
                  child: Icon(Icons.info_outline, size: 16),
                ),
              ],
            ),
          ),
        if (!isThisDevice && removeSession != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
            child: tiamat.IconButton(
              icon: Icons.delete,
              size: 24,
              onPressed: () => removeSession?.call(),
            ),
          )
      ],
    );
  }

  IconData getIcon() {
    if (displayName == null) return Icons.device_unknown;

    if (["ios", "android", "mobile"]
        .any((element) => displayName!.toLowerCase().contains(element))) {
      return Icons.smartphone;
    }

    if ([
      "desktop",
      "linux",
      "windows",
      "mac",
    ].any((element) => displayName!.toLowerCase().contains(element))) {
      return Icons.desktop_windows_rounded;
    }

    if (displayName!.toLowerCase().contains("web")) {
      return Icons.web;
    }

    return Icons.device_unknown;
  }
}
