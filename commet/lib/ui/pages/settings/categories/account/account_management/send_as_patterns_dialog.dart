import 'package:commet/client/client.dart';
import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 597: the send-as patterns of one account (was "Set Prefix").
/// Each pattern is the text typed before and/or after a message to send it
/// from this account.
class SendAsPatternsDialog extends StatefulWidget {
  const SendAsPatternsDialog(
      {required this.accountName,
      required this.patterns,
      required this.usedByOthers,
      super.key});

  final String accountName;
  final List<SendAsPattern> patterns;

  /// Patterns of the other accounts, with the name of the account using each.
  final Map<SendAsPattern, String> usedByOthers;

  static String get title => Intl.message("Send-as patterns",
      name: "sendAsPatternsTitle",
      desc:
          "Title of the dialog for the text that sends a message from another account");

  static Future<void> show(BuildContext context, Client client) async {
    final component = client.getComponent<AccountSwitchPrefix>();
    if (component == null) return;

    final usedByOthers = <SendAsPattern, String>{};
    for (final other in clientManager?.clients ?? <Client>[]) {
      if (other == client) continue;
      final name = other.self?.displayName ?? other.identifier;
      for (final pattern
          in other.getComponent<AccountSwitchPrefix>()?.patterns ?? []) {
        usedByOthers.putIfAbsent(pattern, () => name);
      }
    }

    final result = await AdaptiveDialog.show<List<SendAsPattern>>(context,
        title: title,
        builder: (context) => SendAsPatternsDialog(
            accountName: client.self?.displayName ?? client.identifier,
            patterns: component.patterns,
            usedByOthers: usedByOthers));
    if (result == null) return;

    await component.setPatterns(result);
  }

  @override
  State<SendAsPatternsDialog> createState() => _SendAsPatternsDialogState();
}

class _PatternRow {
  final TextEditingController before;
  final TextEditingController after;

  _PatternRow(SendAsPattern pattern)
      : before = TextEditingController(text: pattern.before),
        after = TextEditingController(text: pattern.after);

  SendAsPattern? get pattern =>
      SendAsPattern.normalize(before.text, after.text);

  void dispose() {
    before.dispose();
    after.dispose();
  }
}

class _SendAsPatternsDialogState extends State<SendAsPatternsDialog> {
  late final List<_PatternRow> rows;
  final tryController = TextEditingController();

  String description(String name) => Intl.message(
      "When more than one of your accounts is in a room, type these around a message to send it from $name. Spaces between them and the message are removed.",
      args: [name],
      name: "sendAsPatternsDescription",
      desc: "Explains send-as patterns in their settings dialog");

  String get labelBefore => Intl.message("Before",
      name: "sendAsPatternsBefore",
      desc: "Column of text typed before the message");

  String get labelAfter => Intl.message("After",
      name: "sendAsPatternsAfter",
      desc: "Column of text typed after the message");

  String get labelMessage => Intl.message("message",
      name: "sendAsPatternsMessage",
      desc: "Stands for the message between the before and after text");

  String get promptAddPattern => Intl.message("Add pattern",
      name: "sendAsPatternsAdd", desc: "Adds a row for another pattern");

  String get placeholderTry => Intl.message("Try a message",
      name: "sendAsPatternsTry",
      desc: "Placeholder of a box to test the patterns");

  String usedBy(String name) => Intl.message("Already used by $name",
      args: [name],
      name: "sendAsPatternsUsedBy",
      desc: "Shown under a pattern another account already uses");

  String sendsAs(String message, String name) =>
      Intl.message("Sends “$message” as $name",
          args: [message, name],
          name: "sendAsPatternsSendsAs",
          desc: "Result of testing a message against the patterns");

  String get sendsNormally => Intl.message(
      "No pattern matches; sent from the account that has the room open",
      name: "sendAsPatternsNoMatch",
      desc: "Result of testing a message that matches no pattern");

  @override
  void initState() {
    rows = widget.patterns.map(_PatternRow.new).toList();
    if (rows.isEmpty) rows.add(_PatternRow(const SendAsPattern()));
    super.initState();
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    tryController.dispose();
    super.dispose();
  }

  String? conflictOf(_PatternRow row) {
    final pattern = row.pattern;
    return pattern == null ? null : widget.usedByOthers[pattern];
  }

  String? tryResult() {
    final text = tryController.text;
    if (text.isEmpty) return null;

    SendAsPattern? best;
    for (final pattern in rows.map((r) => r.pattern).nonNulls) {
      if (pattern.matches(text) && (best == null || pattern.beats(best))) {
        best = pattern;
      }
    }

    return best == null
        ? sendsNormally
        : sendsAs(best.messageIn(text)!, widget.accountName);
  }

  Widget patternRow(_PatternRow row) {
    final conflict = conflictOf(row);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: tiamat.TextInput(
                      controller: row.before,
                      placeholder: labelBefore,
                      onChanged: (_) => setState(() {}))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: tiamat.Text.labelLow(labelMessage),
              ),
              Expanded(
                  child: tiamat.TextInput(
                      controller: row.after,
                      placeholder: labelAfter,
                      onChanged: (_) => setState(() {}))),
              IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: CommonStrings.promptRemove,
                  onPressed: () => setState(() {
                        rows.remove(row);
                        row.dispose();
                      })),
            ],
          ),
          if (conflict != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 0, 0),
              child: tiamat.Text.error(usedBy(conflict)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasConflict = rows.any((r) => conflictOf(r) != null);
    final result = tryResult();

    return SizedBox(
      width: 480,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text.labelLow(description(widget.accountName)),
            const SizedBox(height: 10),
            for (final row in rows) patternRow(row),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(promptAddPattern),
                  onPressed: () => setState(
                      () => rows.add(_PatternRow(const SendAsPattern())))),
            ),
            const Divider(),
            tiamat.TextInput(
                controller: tryController,
                placeholder: placeholderTry,
                onChanged: (_) => setState(() {})),
            if (result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 0, 0),
                child: tiamat.Text.labelLow(result),
              ),
            const SizedBox(height: 10),
            tiamat.Button(
              text: CommonStrings.promptSubmit,
              onTap: hasConflict
                  ? null
                  : () => Navigator.of(context).pop(SendAsPattern.distinct(
                      rows.map((r) => r.pattern).nonNulls)),
            )
          ],
        ),
      ),
    );
  }
}
