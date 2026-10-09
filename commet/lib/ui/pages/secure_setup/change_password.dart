import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

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
      return setState(() => error = "Use at least 8 characters.");
    }
    if (_new.text != _again.text) {
      return setState(() => error = "The new passwords don't match.");
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
              ? "Your current password isn't right."
              : "Couldn't change it: $e";
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
      title: const Text("Change your password"),
      content: AutofillGroup(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          field(_current, "Current password", const [AutofillHints.password]),
          field(_new, "New password", const [AutofillHints.newPassword]),
          field(
              _again, "New password again", const [AutofillHints.newPassword]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: signOutOthers,
            onChanged: (v) => setState(() => signOutOthers = v ?? true),
            title: const Text("Also sign me out everywhere else"),
          ),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(false),
            child: const Text("Cancel")),
        FilledButton(
            onPressed: busy ? null : submit,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Change password")),
      ],
    );
  }
}
