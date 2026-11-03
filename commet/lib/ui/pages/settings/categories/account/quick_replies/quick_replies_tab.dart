import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/quick_replies/quick_replies.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/account_selector.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/current_account.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Settings › Account › Quick replies. Add, edit, delete and
/// reorder the texts you insert by typing `/name` in the message box.
class QuickRepliesTab extends StatefulWidget {
  const QuickRepliesTab({required this.clientManager, super.key});
  final ClientManager clientManager;

  static String get labelSettingsTabQuickReplies =>
      Intl.message("Quick replies",
          name: "labelSettingsTabQuickReplies",
          desc: "Label for the settings page of saved texts you insert with "
              "/name");

  static String get labelQuickRepliesHelp => Intl.message(
      "Type / and a quick reply's name in the message box to put its text "
      "there. You can still change it before sending.",
      name: "labelQuickRepliesHelp",
      desc: "Explains how quick replies are used, on their settings page");

  static String get labelQuickRepliesPrivacy => Intl.message(
      "Quick replies sync to your other devices through your homeserver, "
      "which can read them.",
      name: "labelQuickRepliesPrivacy",
      desc: "Note on the quick replies settings page about who can read them");

  static String get labelNoQuickReplies => Intl.message("No quick replies yet.",
      name: "labelNoQuickReplies",
      desc: "Shown on the quick replies settings page when there are none");

  static String get promptAddQuickReply => Intl.message("Add quick reply",
      name: "promptAddQuickReply", desc: "Button that adds a new quick reply");

  static String get promptMoveQuickReplyUp => Intl.message("Move up",
      name: "promptMoveQuickReplyUp",
      desc: "Button that moves a quick reply up the list");

  static String get promptMoveQuickReplyDown => Intl.message("Move down",
      name: "promptMoveQuickReplyDown",
      desc: "Button that moves a quick reply down the list");

  static String get promptDeleteQuickReply => Intl.message("Delete",
      name: "promptDeleteQuickReply",
      desc: "Button that deletes a quick reply");

  @override
  State<QuickRepliesTab> createState() => _QuickRepliesTabState();
}

class _QuickRepliesTabState extends State<QuickRepliesTab> {
  late Client client;

  @override
  void initState() {
    super.initState();
    client = currentAccount(
            widget.clientManager.clients, preferences.filterClient.value) ??
        widget.clientManager.clients.first;
    QuickReplies.changed.addListener(refresh);
  }

  @override
  void dispose() {
    QuickReplies.changed.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void move(List<QuickReply> items, int from, int to) {
    final list = [...items];
    final q = list.removeAt(from);
    list.insert(to, q);
    QuickReplies.set(client, list);
  }

  @override
  Widget build(BuildContext context) {
    final items = QuickReplies.of(client);
    final full = items.length >= QuickReplies.maxItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.clientManager.clients.length > 1)
          AccountSelector(
            widget.clientManager.clients,
            initialClient: client,
            onClientSelected: (c) => setState(() => client = c),
          ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: QuickRepliesTab.labelSettingsTabQuickReplies,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tiamat.Text.labelLow(QuickRepliesTab.labelQuickRepliesHelp),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: tiamat.Text.label(QuickRepliesTab.labelNoQuickReplies),
                ),
              for (var i = 0; i < items.length; i++) row(items, i),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: tiamat.Button(
                  text: QuickRepliesTab.promptAddQuickReply,
                  onTap: full
                      ? null
                      : () => QuickReplyEditor.show(context, client),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.lock_outline,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                    child: tiamat.Text.labelLow(
                        QuickRepliesTab.labelQuickRepliesPrivacy)),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget row(List<QuickReply> items, int i) {
    final q = items[i];
    return Material(
      key: ValueKey("quick-reply-${q.name}"),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => QuickReplyEditor.show(context, client, editing: q),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(children: [
            SizedBox(
                width: 120, child: tiamat.Text.labelEmphasised("/${q.name}")),
            Expanded(child: tiamat.Text.labelLow(QuickReplies.preview(q.body))),
            IconButton(
              tooltip: QuickRepliesTab.promptMoveQuickReplyUp,
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward),
              onPressed: i == 0 ? null : () => move(items, i, i - 1),
            ),
            IconButton(
              tooltip: QuickRepliesTab.promptMoveQuickReplyDown,
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward),
              onPressed:
                  i == items.length - 1 ? null : () => move(items, i, i + 1),
            ),
            IconButton(
              key: ValueKey("quick-reply-delete-${q.name}"),
              tooltip: QuickRepliesTab.promptDeleteQuickReply,
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => QuickReplies.remove(client, q.name),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Vommet: add or edit one quick reply. Names are letters, digits and
/// dashes, and can't be a built-in command's.
class QuickReplyEditor extends StatefulWidget {
  const QuickReplyEditor(
      {required this.client, this.editing, this.initialBody, super.key});
  final Client client;
  final QuickReply? editing;
  final String? initialBody;

  static String get newQuickReplyTitle => Intl.message("New quick reply",
      name: "newQuickReplyTitle",
      desc: "Title of the dialog that adds a quick reply");

  static String get editQuickReplyTitle => Intl.message("Edit quick reply",
      name: "editQuickReplyTitle",
      desc: "Title of the dialog that edits a quick reply");

  static String get labelQuickReplyName => Intl.message("Name",
      name: "labelQuickReplyName",
      desc: "Label of the quick reply name field (typed after /)");

  static String get labelQuickReplyText => Intl.message("Text",
      name: "labelQuickReplyText", desc: "Label of the quick reply text field");

  static String get errorQuickReplyNameEmpty => Intl.message("Give it a name",
      name: "errorQuickReplyNameEmpty",
      desc: "Error when a quick reply has no name");

  static String get errorQuickReplyNameInvalid =>
      Intl.message("Use only letters, digits and -",
          name: "errorQuickReplyNameInvalid",
          desc: "Error when a quick reply name has other characters");

  static String get errorQuickReplyNameCommand =>
      Intl.message("That's a built-in command",
          name: "errorQuickReplyNameCommand",
          desc: "Error when a quick reply name is the same as a slash command");

  static String get errorQuickReplyNameTaken =>
      Intl.message("You already have a quick reply with that name",
          name: "errorQuickReplyNameTaken",
          desc: "Error when a quick reply name is already used");

  static String get promptSaveQuickReply => Intl.message("Save",
      name: "promptSaveQuickReply", desc: "Button that saves a quick reply");

  static Future<void> show(BuildContext context, Client client,
          {QuickReply? editing, String? initialBody}) =>
      AdaptiveDialog.show(context,
          title: editing == null ? newQuickReplyTitle : editQuickReplyTitle,
          builder: (context) => QuickReplyEditor(
              client: client, editing: editing, initialBody: initialBody));

  @override
  State<QuickReplyEditor> createState() => _QuickReplyEditorState();
}

class _QuickReplyEditorState extends State<QuickReplyEditor> {
  late final TextEditingController name =
      TextEditingController(text: widget.editing?.name ?? "");
  late final TextEditingController body = TextEditingController(
      text: widget.editing?.body ?? widget.initialBody ?? "");
  bool tried = false;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    body.dispose();
    super.dispose();
  }

  QuickReplyNameProblem? get problem => QuickReplies.checkName(name.text,
      commands: QuickReplies.commandNames(widget.client),
      existing: QuickReplies.of(widget.client),
      editing: widget.editing?.name);

  String? get nameError {
    if (!tried && name.text.isEmpty) return null;
    return switch (problem) {
      null => null,
      QuickReplyNameProblem.empty => QuickReplyEditor.errorQuickReplyNameEmpty,
      QuickReplyNameProblem.invalid =>
        QuickReplyEditor.errorQuickReplyNameInvalid,
      QuickReplyNameProblem.command =>
        QuickReplyEditor.errorQuickReplyNameCommand,
      QuickReplyNameProblem.taken => QuickReplyEditor.errorQuickReplyNameTaken,
    };
  }

  Future<void> save() async {
    setState(() => tried = true);
    if (problem != null || body.text.trim().isEmpty) return;
    setState(() => saving = true);
    await QuickReplies.put(
        widget.client, QuickReply(name: name.text, body: body.text),
        previousName: widget.editing?.name);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: TextField(
              key: const ValueKey("quick-reply-name"),
              controller: name,
              autofocus: widget.editing == null,
              maxLength: QuickReplies.maxNameLength,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: QuickReplyEditor.labelQuickReplyName,
                prefixText: "/",
                errorText: nameError,
                counterText: "",
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: TextField(
              key: const ValueKey("quick-reply-body"),
              controller: body,
              minLines: 3,
              maxLines: 8,
              maxLength: 4000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: QuickReplyEditor.labelQuickReplyText,
                counterText: "",
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child:
                tiamat.Text.labelLow(QuickRepliesTab.labelQuickRepliesPrivacy),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: tiamat.Button(
              text: QuickReplyEditor.promptSaveQuickReply,
              isLoading: saving,
              onTap: body.text.trim().isEmpty ? null : save,
            ),
          ),
        ],
      ),
    );
  }
}
