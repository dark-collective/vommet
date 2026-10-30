// Vommet: Settings › Security › Cross Signing & Backup › "Key file": export this account's message
// keys to a passphrase-protected file, or import one from Vommet, Element,
// Cinny or another Matrix app.
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/alert.dart';
import 'package:commet/client/matrix/key_export/matrix_key_export.dart';
import 'package:commet/client/matrix/key_export/megolm_key_file.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/alert_view.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A row in the "Cross Signing & Backup" panel, styled like "Message backup".
class KeyFileRow extends StatelessWidget {
  const KeyFileRow(this.client, {super.key});
  final MatrixClient client;

  @override
  Widget build(BuildContext context) {
    if (client.getMatrixClient().encryption == null) {
      return const SizedBox.shrink();
    }
    return KeyFileRowView(
      onExport: () => AdaptiveDialog.show(context,
          title: keyFileExportTitle,
          dismissible: false,
          builder: (_) => KeyExportDialog(client)),
      onImport: () => AdaptiveDialog.show(context,
          title: keyFileImportTitle,
          dismissible: false,
          builder: (_) => KeyImportDialog(client)),
    );
  }
}

class KeyFileRowView extends StatelessWidget {
  const KeyFileRowView(
      {required this.onExport, required this.onImport, super.key});
  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.label(keyFileRowTitle),
              tiamat.Text.labelLow(keyFileRowBody),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
          // Both buttons as wide as the wider one.
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                tiamat.Button.secondary(
                    text: keyFileExportButton, onTap: onExport),
                tiamat.Button.secondary(
                    text: keyFileImportButton, onTap: onImport),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _warning(BuildContext context, String title, String message,
        {AlertType type = AlertType.warning}) =>
    Container(
      decoration: BoxDecoration(
          color: ColorScheme.of(context).surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: AlertView(Alert(type,
            titleGetter: () => title, messageGetter: () => message)),
      ),
    );

String _count(int n) => NumberFormat.decimalPattern().format(n);

String _keys(int n) => keyFileKeyCount(n, _count(n));

// ---------------------------------------------------------------- export --

enum KeyFileStep { form, working, done }

class KeyExportDialog extends StatefulWidget {
  const KeyExportDialog(this.client, {super.key});
  final MatrixClient client;

  @override
  State<KeyExportDialog> createState() => _KeyExportDialogState();
}

class _KeyExportDialogState extends State<KeyExportDialog> {
  final passphrase = TextEditingController();
  final confirm = TextEditingController();
  KeyFileStep step = KeyFileStep.form;
  String? error;
  int? exported;
  String? savedTo;

  @override
  void dispose() {
    passphrase.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> run() async {
    if (passphrase.text.length < 8) {
      setState(() => error = keyFileTooShort);
      return;
    }
    if (passphrase.text != confirm.text) {
      setState(() => error = keyFileMismatch);
      return;
    }
    setState(() {
      error = null;
      step = KeyFileStep.working;
    });
    try {
      final result = await MatrixKeyExport.export(
          widget.client.getMatrixClient(), passphrase.text);
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final name = "vommet-keys-$date.txt";
      final bytes = utf8.encode(result.file);
      String? path;
      if (PlatformUtils.isAndroid || kIsWeb) {
        path = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
      } else {
        path = await FilePicker.platform.saveFile(fileName: name);
        if (path != null) await File(path).writeAsBytes(bytes, flush: true);
      }
      if (!mounted) return;
      if (path == null) {
        // The save dialog was cancelled: let them try again.
        setState(() => step = KeyFileStep.form);
        return;
      }
      setState(() {
        step = KeyFileStep.done;
        exported = result.count;
        savedTo = path;
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Key export failed");
      if (mounted) {
        setState(() {
          step = KeyFileStep.form;
          error = keyFileExportFailed(e.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => KeyExportBody(
        step: step,
        passphrase: passphrase,
        confirm: confirm,
        error: error,
        exported: exported,
        savedTo: savedTo,
        onExport: run,
        // true once a file was saved (the sign-out warning waits for it).
        onClose: () => Navigator.of(context).pop(step == KeyFileStep.done),
      );
}

class KeyExportBody extends StatelessWidget {
  const KeyExportBody(
      {required this.step,
      required this.passphrase,
      required this.confirm,
      required this.onExport,
      required this.onClose,
      this.error,
      this.exported,
      this.savedTo,
      super.key});

  final KeyFileStep step;
  final TextEditingController passphrase;
  final TextEditingController confirm;
  final VoidCallback onExport;
  final VoidCallback onClose;
  final String? error;
  final int? exported;
  final String? savedTo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: step == KeyFileStep.done
            ? [
                _warning(
                    context,
                    keyFileSaved(_keys(exported ?? 0)),
                    savedTo == null
                        ? keyFileSavedKeepSafe
                        : keyFileSavedIn(savedTo!),
                    type: AlertType.info),
                tiamat.Button(text: keyFileDone, onTap: onClose),
              ]
            : [
                _warning(context, keyFileExportWarningTitle,
                    keyFileExportWarningBody),
                tiamat.Text.label(keyFileChoosePassphrase),
                tiamat.TextInput(
                    placeholder: keyFilePassphrase,
                    controller: passphrase,
                    obscureText: true),
                tiamat.TextInput(
                    placeholder: keyFilePassphraseAgain,
                    controller: confirm,
                    obscureText: true),
                if (error != null) tiamat.Text.error(error!),
                if (step == KeyFileStep.working)
                  tiamat.Text.labelLow(keyFileLocking),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    if (step == KeyFileStep.form)
                      tiamat.Button.secondary(
                          text: keyFileCancel, onTap: onClose),
                    tiamat.Button(
                        text: keyFileExportButton,
                        isLoading: step == KeyFileStep.working,
                        onTap: step == KeyFileStep.form ? onExport : null),
                  ],
                ),
              ],
      ),
    );
  }
}

// ---------------------------------------------------------------- import --

class KeyImportDialog extends StatefulWidget {
  const KeyImportDialog(this.client, {super.key});
  final MatrixClient client;

  @override
  State<KeyImportDialog> createState() => _KeyImportDialogState();
}

class _KeyImportDialogState extends State<KeyImportDialog> {
  final passphrase = TextEditingController();
  KeyFileStep step = KeyFileStep.form;
  String? fileName;
  String? fileText;
  String? error;
  (int, int)? progress;
  KeyImportResult? result;

  @override
  void dispose() {
    passphrase.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    try {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      final file = picked?.files.firstOrNull;
      if (file == null) return;
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) return;
      final text = utf8.decode(bytes, allowMalformed: true);
      setState(() {
        fileName = file.name;
        if (MegolmKeyFile.looksLikeKeyFile(text)) {
          fileText = text;
          error = null;
        } else {
          fileText = null;
          error = keyFileNotAKeyFile;
        }
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Key import: picking a file failed");
    }
  }

  Future<void> run() async {
    final text = fileText;
    if (text == null) return;
    setState(() {
      error = null;
      step = KeyFileStep.working;
      progress = null;
    });
    try {
      final r = await MatrixKeyExport.import(
          widget.client.getMatrixClient(), text, passphrase.text,
          onProgress: (done, total) {
        if (mounted && (done % 50 == 0 || done == total)) {
          setState(() => progress = (done, total));
        }
      });
      if (mounted) {
        setState(() {
          step = KeyFileStep.done;
          result = r;
        });
      }
    } catch (e, s) {
      if (e is! WrongPassphraseException) {
        Log.onError(e, s, content: "Key import failed");
      }
      if (mounted) {
        setState(() {
          step = KeyFileStep.form;
          error = e is KeyFileException
              ? e.message
              : keyFileImportFailed(e.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => KeyImportBody(
        step: step,
        passphrase: passphrase,
        fileName: fileName,
        canImport: fileText != null,
        error: error,
        progress: progress,
        result: result,
        onPick: pick,
        onImport: run,
        onClose: () => Navigator.of(context).pop(),
      );
}

class KeyImportBody extends StatelessWidget {
  const KeyImportBody(
      {required this.step,
      required this.passphrase,
      required this.canImport,
      required this.onPick,
      required this.onImport,
      required this.onClose,
      this.fileName,
      this.error,
      this.progress,
      this.result,
      super.key});

  final KeyFileStep step;
  final TextEditingController passphrase;
  final bool canImport;
  final VoidCallback onPick;
  final VoidCallback onImport;
  final VoidCallback onClose;
  final String? fileName;
  final String? error;
  final (int, int)? progress;
  final KeyImportResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: step == KeyFileStep.done && r != null
            ? [
                _warning(
                    context,
                    r.imported == 0
                        ? keyFileNoNewKeys
                        : keyFileImported(_keys(r.imported)),
                    [
                      if (r.alreadyHad > 0)
                        keyFileAlreadyHad(_keys(r.alreadyHad)),
                      if (r.invalid > 0) keyFileInvalid(_keys(r.invalid)),
                      if (r.imported > 0) keyFileScrollBack,
                    ].join(" "),
                    type: AlertType.info),
                tiamat.Button(text: keyFileDone, onTap: onClose),
              ]
            : [
                tiamat.Text.label(keyFileImportExplain),
                Row(spacing: 8, children: [
                  tiamat.Button.secondary(
                      text: fileName == null
                          ? keyFileChooseFile
                          : keyFileChangeFile,
                      onTap: step == KeyFileStep.form ? onPick : null),
                  if (fileName != null)
                    Flexible(
                      child: tiamat.Text.labelLow(fileName!,
                          overflow: TextOverflow.ellipsis),
                    ),
                ]),
                tiamat.TextInput(
                    placeholder: keyFilePassphrase,
                    controller: passphrase,
                    obscureText: true),
                if (error != null) tiamat.Text.error(error!),
                if (step == KeyFileStep.working) ...[
                  LinearProgressIndicator(
                      value: progress == null || progress!.$2 == 0
                          ? null
                          : progress!.$1 / progress!.$2),
                  tiamat.Text.labelLow(progress == null
                      ? keyFileUnlocking
                      : keyFileImporting(
                          _count(progress!.$1), _keys(progress!.$2))),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    if (step == KeyFileStep.form)
                      tiamat.Button.secondary(
                          text: keyFileCancel, onTap: onClose),
                    tiamat.Button(
                        text: keyFileImportButton,
                        isLoading: step == KeyFileStep.working,
                        onTap: step == KeyFileStep.form && canImport
                            ? onImport
                            : null),
                  ],
                ),
              ],
      ),
    );
  }
}

String get keyFileExportTitle => Intl.message("Export message keys",
    name: "keyFileExportTitle",
    desc: "Title of the dialog that exports message keys to a file");

String get keyFileImportTitle => Intl.message("Import message keys",
    name: "keyFileImportTitle",
    desc: "Title of the dialog that imports message keys from a file");

String get keyFileRowTitle => Intl.message("Key file",
    name: "keyFileRowTitle",
    desc: "Title of the key file row in the security settings");

String get keyFileRowBody => Intl.message(
    "Save your message keys to a passphrase-locked file, to read your history in another Matrix app or keep an offline copy. Files from Element, Cinny, and others import here too.",
    name: "keyFileRowBody",
    desc: "Description of the key file row in the security settings");

String get keyFileExportButton => Intl.message("Export",
    name: "keyFileExportButton",
    desc: "Button that exports message keys (short)");

String get keyFileImportButton => Intl.message("Import",
    name: "keyFileImportButton",
    desc: "Button that imports message keys (short)");

String get keyFileTooShort => Intl.message("Use at least 8 characters",
    name: "keyFileTooShort",
    desc: "Error when the key file passphrase is too short");

String get keyFileMismatch => Intl.message("The passphrases don't match",
    name: "keyFileMismatch",
    desc: "Error when the two key file passphrases differ");

String keyFileExportFailed(String error) => Intl.message(
    "The export failed: $error",
    args: [error],
    name: "keyFileExportFailed",
    desc:
        "Error when exporting keys failed; error is the technical error text");

String keyFileSaved(String keys) => Intl.message("Saved $keys",
    args: [keys],
    name: "keyFileSaved",
    desc: "Title after exporting keys; keys is e.g. '1,234 keys'");

String get keyFileSavedKeepSafe =>
    Intl.message("Keep the file and its passphrase somewhere safe.",
        name: "keyFileSavedKeepSafe",
        desc: "Note after exporting keys when the save location is unknown");

String keyFileSavedIn(String place) => Intl.message(
    "In $place. Keep the file and its passphrase somewhere safe.",
    args: [place],
    name: "keyFileSavedIn",
    desc:
        "Note after exporting keys; place is the folder or file the keys were saved to");

String get keyFileDone => Intl.message("Done",
    name: "keyFileDone", desc: "Button that closes the key file dialog");

String get keyFileExportWarningTitle => Intl.message(
    "Anyone with this file and its passphrase can read your messages",
    name: "keyFileExportWarningTitle",
    desc: "Warning title in the key export dialog");

String get keyFileExportWarningBody => Intl.message(
    "Don't send the file in a chat or store it unencrypted in the cloud. Nobody from Vommet or your server will ever ask for it.",
    name: "keyFileExportWarningBody",
    desc: "Warning body in the key export dialog");

String get keyFileChoosePassphrase => Intl.message(
    "Choose a passphrase for the file. You'll need it to import the keys again.",
    name: "keyFileChoosePassphrase",
    desc: "Instruction in the key export dialog");

String get keyFilePassphrase => Intl.message("Passphrase",
    name: "keyFilePassphrase",
    desc: "Placeholder of the key file passphrase field");

String get keyFilePassphraseAgain => Intl.message("Passphrase again",
    name: "keyFilePassphraseAgain",
    desc: "Placeholder of the field repeating the key file passphrase");

String get keyFileLocking =>
    Intl.message("Locking the file. This takes a few seconds…",
        name: "keyFileLocking",
        desc: "Shown while encrypting the exported key file");

String get keyFileCancel => Intl.message("Cancel",
    name: "keyFileCancel", desc: "Cancel button of the key file dialogs");

String get keyFileNotAKeyFile =>
    Intl.message("That file isn't a Matrix key file",
        name: "keyFileNotAKeyFile",
        desc: "Error when the picked file is not a Matrix key file");

String keyFileImportFailed(String error) => Intl.message(
    "The import failed: $error",
    args: [error],
    name: "keyFileImportFailed",
    desc:
        "Error when importing keys failed; error is the technical error text");

String get keyFileNoNewKeys => Intl.message("No new keys",
    name: "keyFileNoNewKeys",
    desc: "Title after importing when no new keys were added");

String keyFileImported(String keys) => Intl.message("Imported $keys",
    args: [keys],
    name: "keyFileImported",
    desc: "Title after importing keys; keys is e.g. '1,234 keys'");

String keyFileAlreadyHad(String keys) => Intl.message("$keys you already had.",
    args: [keys],
    name: "keyFileAlreadyHad",
    desc: "Part of the import result; keys is e.g. '12 keys'");

String keyFileInvalid(String keys) => Intl.message("$keys couldn't be read.",
    args: [keys],
    name: "keyFileInvalid",
    desc: "Part of the import result; keys is e.g. '3 keys'");

String get keyFileScrollBack =>
    Intl.message("Messages they unlock appear as you scroll back.",
        name: "keyFileScrollBack", desc: "Part of the import result");

String get keyFileImportExplain => Intl.message(
    "Choose a key file exported from Vommet, Element, Cinny, or another Matrix app, and enter the passphrase it was saved with.",
    name: "keyFileImportExplain",
    desc: "Instruction in the key import dialog");

String get keyFileChooseFile => Intl.message("Choose file",
    name: "keyFileChooseFile", desc: "Button that picks a key file to import");

String get keyFileChangeFile => Intl.message("Change file",
    name: "keyFileChangeFile",
    desc: "Button that picks a different key file to import");

String get keyFileUnlocking =>
    Intl.message("Unlocking the file. This takes a few seconds…",
        name: "keyFileUnlocking",
        desc: "Shown while decrypting the key file to import");

String keyFileImporting(String done, String total) => Intl.message(
    "Importing $done of $total…",
    args: [done, total],
    name: "keyFileImporting",
    desc:
        "Import progress; done is a formatted number, total e.g. '1,234 keys'");

String keyFileKeyCount(int count, String formatted) => Intl.plural(count,
    one: "1 key",
    other: "$formatted keys",
    args: [count, formatted],
    name: "keyFileKeyCount",
    desc:
        "A number of message keys; formatted is the count with digit grouping");
