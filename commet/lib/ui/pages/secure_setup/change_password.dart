import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:intl/intl.dart';

/// Vommet issue 129: "Change my password" after "Someone may have used my
/// key". Accounts that sign in through the browser (OIDC) change it on their
/// server's account page; password accounts get a small dialog, which by
/// default also signs out every other device.
class ChangePassword {
  static Future<bool> start(BuildContext context, MatrixClient client) async {
    final mx = client.getMatrixClient();
    Uri? accountPage;
    try {
      final metadata =
          await mx.request(matrix.RequestType.GET, "/client/v1/auth_metadata");
      final uri = metadata["account_management_uri"];
      if (uri is String) accountPage = Uri.tryParse(uri);
    } catch (_) {
      // Not an OIDC server.
    }
    if (!context.mounted) return false;
    if (accountPage != null) {
      await LinkUtils.open(accountPage,
          context: context,
          filterTrackingParameters: false,
          bypassConfirmation: true);
      return true;
    }
    return await showDialog<bool>(
            context: context, builder: (_) => _ChangePasswordDialog(mx)) ??
        false;
  }
}

/// The change-password dialog on its own, for layout tests.
Widget changePasswordDialogForTest(matrix.Client mx) =>
    _ChangePasswordDialog(mx);

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog(this.mx);
  final matrix.Client mx;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  bool signOutOthers = true;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (_new.text.length < 8) {
      return setState(() => error = changePasswordTooShort);
    }
    if (_new.text != _again.text) {
      return setState(() => error = changePasswordMismatch);
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.mx.changePassword(_new.text,
          oldPassword: _current.text, logoutDevices: signOutOthers);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, s) {
      Log.onError(e, s, content: "Changing the password failed");
      if (mounted) {
        setState(() {
          busy = false;
          error = e is matrix.MatrixException &&
                  e.error == matrix.MatrixError.M_FORBIDDEN
              ? changePasswordWrongCurrent
              : changePasswordFailed(e.toString());
        });
      }
    }
  }

  Widget field(TextEditingController c, String label, List<String> hints) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: true,
          autofillHints: hints,
          decoration: InputDecoration(
              labelText: label,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(changePasswordTitle),
      content: AutofillGroup(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          field(_current, changePasswordCurrentLabel,
              const [AutofillHints.password]),
          field(
              _new, changePasswordNewLabel, const [AutofillHints.newPassword]),
          field(_again, changePasswordAgainLabel,
              const [AutofillHints.newPassword]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: signOutOthers,
            onChanged: (v) => setState(() => signOutOthers = v ?? true),
            title: Text(changePasswordSignOutOthers),
          ),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(false),
            child: Text(changePasswordCancel)),
        FilledButton(
            onPressed: busy ? null : submit,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(changePasswordSubmit)),
      ],
    );
  }
}

String get changePasswordTooShort => Intl.message("Use at least 8 characters.",
    name: "changePasswordTooShort",
    desc:
        "Error in the change password dialog when the new password is too short");

String get changePasswordMismatch => Intl.message(
    "The new passwords don't match.",
    name: "changePasswordMismatch",
    desc:
        "Error in the change password dialog when the two new passwords differ");

String get changePasswordWrongCurrent => Intl.message(
    "Your current password isn't right.",
    name: "changePasswordWrongCurrent",
    desc:
        "Error in the change password dialog when the current password is wrong");

String changePasswordFailed(String error) => Intl.message(
    "Couldn't change it: $error",
    args: [error],
    name: "changePasswordFailed",
    desc:
        "Error in the change password dialog; error is the technical error text");

String get changePasswordTitle => Intl.message("Change your password",
    name: "changePasswordTitle", desc: "Title of the change password dialog");

String get changePasswordCurrentLabel => Intl.message("Current password",
    name: "changePasswordCurrentLabel",
    desc: "Field label in the change password dialog");

String get changePasswordNewLabel => Intl.message("New password",
    name: "changePasswordNewLabel",
    desc: "Field label in the change password dialog");

String get changePasswordAgainLabel => Intl.message("New password again",
    name: "changePasswordAgainLabel",
    desc:
        "Field label in the change password dialog (repeat the new password)");

String get changePasswordSignOutOthers => Intl.message(
    "Also sign me out everywhere else",
    name: "changePasswordSignOutOthers",
    desc:
        "Checkbox in the change password dialog that signs out all other devices");

String get changePasswordCancel => Intl.message("Cancel",
    name: "changePasswordCancel",
    desc: "Cancel button of the change password dialog");

String get changePasswordSubmit => Intl.message("Change password",
    name: "changePasswordSubmit",
    desc: "Confirm button of the change password dialog");
