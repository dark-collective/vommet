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
          title: "Export message keys",
          dismissible: false,
          builder: (_) => KeyExportDialog(client)),
      onImport: () => AdaptiveDialog.show(context,
          title: "Import message keys",
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
              tiamat.Text.label("Key file"),
              tiamat.Text.labelLow(
                  "Save your message keys to a passphrase-locked file, to "
                  "read your history in another Matrix app or keep an offline "
                  "copy. Files from Element, Cinny and others import here too."),
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
                tiamat.Button.secondary(text: "Export", onTap: onExport),
                tiamat.Button.secondary(text: "Import", onTap: onImport),
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

String _keys(int n) => n == 1 ? "1 key" : "${_count(n)} keys";

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
      setState(() => error = "Use at least 8 characters");
      return;
    }
    if (passphrase.text != confirm.text) {
      setState(() => error = "The passphrases don't match");
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
          error = "The export failed: $e";
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
        onClose: () => Navigator.of(context).pop(),
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
                    "Saved ${_keys(exported ?? 0)}",
                    savedTo == null
                        ? "Keep the file and its passphrase somewhere safe."
                        : "In $savedTo. Keep the file and its passphrase "
                            "somewhere safe.",
                    type: AlertType.info),
                tiamat.Button(text: "Done", onTap: onClose),
              ]
            : [
                _warning(
                    context,
                    "Anyone with this file and its passphrase can read your "
                        "messages",
                    "Don't send the file in a chat or store it unencrypted "
                        "in the cloud. Nobody from Vommet or your server will "
                        "ever ask for it."),
                tiamat.Text.label("Choose a passphrase for the file. You'll "
                    "need it to import the keys again."),
                tiamat.TextInput(
                    placeholder: "Passphrase",
                    controller: passphrase,
                    obscureText: true),
                tiamat.TextInput(
                    placeholder: "Passphrase again",
                    controller: confirm,
                    obscureText: true),
                if (error != null) tiamat.Text.error(error!),
                if (step == KeyFileStep.working)
                  tiamat.Text.labelLow(
                      "Locking the file. This takes a few seconds…"),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    if (step == KeyFileStep.form)
                      tiamat.Button.secondary(text: "Cancel", onTap: onClose),
                    tiamat.Button(
                        text: "Export",
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
          error = "That file isn't a Matrix key file";
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
          error = e is KeyFileException ? e.message : "The import failed: $e";
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
                        ? "No new keys"
                        : "Imported ${_keys(r.imported)}",
                    [
                      if (r.alreadyHad > 0)
                        "${_keys(r.alreadyHad)} you already had.",
                      if (r.invalid > 0)
                        "${_keys(r.invalid)} couldn't be read.",
                      if (r.imported > 0)
                        "Messages they unlock appear as you scroll back.",
                    ].join(" "),
                    type: AlertType.info),
                tiamat.Button(text: "Done", onTap: onClose),
              ]
            : [
                tiamat.Text.label("Choose a key file exported from Vommet, "
                    "Element, Cinny or another Matrix app, and enter the "
                    "passphrase it was saved with."),
                Row(spacing: 8, children: [
                  tiamat.Button.secondary(
                      text: fileName == null ? "Choose file" : "Change file",
                      onTap: step == KeyFileStep.form ? onPick : null),
                  if (fileName != null)
                    Flexible(
                      child: tiamat.Text.labelLow(fileName!,
                          overflow: TextOverflow.ellipsis),
                    ),
                ]),
                tiamat.TextInput(
                    placeholder: "Passphrase",
                    controller: passphrase,
                    obscureText: true),
                if (error != null) tiamat.Text.error(error!),
                if (step == KeyFileStep.working) ...[
                  LinearProgressIndicator(
                      value: progress == null || progress!.$2 == 0
                          ? null
                          : progress!.$1 / progress!.$2),
                  tiamat.Text.labelLow(progress == null
                      ? "Unlocking the file. This takes a few seconds…"
                      : "Importing ${_count(progress!.$1)} of "
                          "${_keys(progress!.$2)}…"),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    if (step == KeyFileStep.form)
                      tiamat.Button.secondary(text: "Cancel", onTap: onClose),
                    tiamat.Button(
                        text: "Import",
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
