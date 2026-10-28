import 'package:commet/client/client.dart';
import 'package:commet/client/components/message_filters/message_filters.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Settings › Account › Message filters. Words, phrases and regexes
/// that hide messages, on this account only (account data, see
/// [MessageFilters]).
class MessageFiltersPreferences extends StatefulWidget {
  const MessageFiltersPreferences({required this.client, super.key});
  final Client client;

  @override
  State<MessageFiltersPreferences> createState() =>
      _MessageFiltersPreferencesState();
}

class _MessageFiltersPreferencesState extends State<MessageFiltersPreferences> {
  String get labelMessageFiltersTitle => Intl.message("Message filters",
      desc: "Header for the message filters section in settings",
      name: "labelMessageFiltersTitle");

  String get labelMessageFiltersDescription => Intl.message(
      "Hide messages that match, on this account only. Nobody else is told; nothing is deleted.",
      desc: "Description of the message filters section in settings",
      name: "labelMessageFiltersDescription");

  String get labelMessageFilterAddHint =>
      Intl.message("Add a word, a phrase or /regex/",
          desc: "Hint in the box for adding a message filter",
          name: "labelMessageFilterAddHint");

  String get labelMessageFilterAdd => Intl.message("Add",
      desc: "Button that adds a message filter", name: "labelMessageFilterAdd");

  String get labelMessageFilterInvalidRegex =>
      Intl.message("That regex can't be read.",
          desc: "Error shown when a message filter's regex is invalid",
          name: "labelMessageFilterInvalidRegex");

  String get labelMessageFilterWord => Intl.message("Whole word",
      desc: "Kind of a message filter that matches a whole word",
      name: "labelMessageFilterWord");

  String get labelMessageFilterPhrase => Intl.message("Phrase",
      desc: "Kind of a message filter that matches a phrase anywhere",
      name: "labelMessageFilterPhrase");

  String get labelMessageFilterRegex => Intl.message("Regex",
      desc: "Kind of a message filter that matches a regular expression",
      name: "labelMessageFilterRegex");

  String get labelMessageFilterAllRooms => Intl.message("All rooms",
      desc: "Scope of a message filter that applies in every room",
      name: "labelMessageFilterAllRooms");

  String labelMessageFilterOnlyRooms(String rooms) =>
      Intl.message("Only: $rooms",
          args: [rooms],
          desc: "Scope of a message filter that applies only in some rooms",
          name: "labelMessageFilterOnlyRooms");

  String get labelMessageFilterRoomsTitle => Intl.message("Filter in",
      desc:
          "Title of the dialog choosing the rooms a message filter applies in",
      name: "labelMessageFilterRoomsTitle");

  String get labelMessageFilterDone => Intl.message("Done",
      desc: "Closes the dialog choosing a message filter's rooms",
      name: "labelMessageFilterDone");

  String get labelFilteredShowAs => Intl.message("Hidden messages show as",
      desc: "Heading for how messages hidden by a filter show",
      name: "labelFilteredShowAs");

  String get labelFilteredShowAsNote =>
      Intl.message("A one-line note you can tap to show",
          desc: "Option: a hidden message leaves a one-line note",
          name: "labelFilteredShowAsNote");

  String get labelFilteredShowAsNothing =>
      Intl.message("Nothing: the message is gone from the timeline",
          desc: "Option: a hidden message leaves nothing",
          name: "labelFilteredShowAsNothing");

  String get labelFilteredNoNotifications =>
      Intl.message("No notifications for filtered messages",
          desc: "Checkbox in message filter settings",
          name: "labelFilteredNoNotifications");

  String get labelFilteredSkipOwnAndDms =>
      Intl.message("Never filter my own messages or my DMs",
          desc: "Checkbox in message filter settings",
          name: "labelFilteredSkipOwnAndDms");

  String get labelFilteredMatchSenderNames =>
      Intl.message("Also match sender names",
          desc: "Checkbox in message filter settings",
          name: "labelFilteredMatchSenderNames");

  final TextEditingController input = TextEditingController();
  String? error;
  late MessageFilterSettings settings;

  @override
  void initState() {
    settings = MessageFilters.of(widget.client);
    super.initState();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> save(MessageFilterSettings next) async {
    setState(() => settings = next);
    await ErrorUtils.tryRun(
        context, () => MessageFilters.save(widget.client, next));
  }

  void add() {
    final rule = MessageFilterRule.fromInput(input.text);
    if (rule == null) return;
    if (rule.pattern == null) {
      setState(() => error = labelMessageFilterInvalidRegex);
      return;
    }
    input.clear();
    error = null;
    save(settings.copyWith(rules: [...settings.rules, rule]));
  }

  String kindLabel(MessageFilterKind kind) => switch (kind) {
        MessageFilterKind.word => labelMessageFilterWord,
        MessageFilterKind.phrase => labelMessageFilterPhrase,
        MessageFilterKind.regex => labelMessageFilterRegex,
      };

  String scopeLabel(MessageFilterRule rule) {
    if (rule.rooms.isEmpty) return labelMessageFilterAllRooms;
    final names =
        rule.rooms.map((id) => widget.client.getRoom(id)?.displayName ?? id);
    return labelMessageFilterOnlyRooms(names.join(", "));
  }

  Future<void> pickRooms(int index) async {
    final rule = settings.rules[index];
    final rooms = widget.client.rooms.toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final chosen = rule.rooms.toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(labelMessageFilterRoomsTitle),
          content: SizedBox(
            width: 400,
            height: 420,
            child: ListView(children: [
              CheckboxListTile(
                value: chosen.isEmpty,
                title: Text(labelMessageFilterAllRooms),
                onChanged: (_) => setDialogState(chosen.clear),
              ),
              for (final room in rooms)
                CheckboxListTile(
                  value: chosen.contains(room.identifier),
                  title: Text(room.displayName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onChanged: (on) => setDialogState(() => on == true
                      ? chosen.add(room.identifier)
                      : chosen.remove(room.identifier)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(chosen),
                child: Text(labelMessageFilterDone)),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final rules = [...settings.rules];
    rules[index] = rule.withRooms(result.toList());
    await save(settings.copyWith(rules: rules));
  }

  Widget chip(String text, {VoidCallback? onTap}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ActionChip(
        label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        visualDensity: VisualDensity.compact,
        backgroundColor: colors.primaryContainer.withAlpha(90),
        side: BorderSide.none,
        onPressed: onTap,
      ),
    );
  }

  Widget ruleRow(int index) {
    final rule = settings.rules[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
          child: Text(rule.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: rule.kind == MessageFilterKind.regex
                      ? "monospace"
                      : null)),
        ),
        chip(kindLabel(rule.kind)),
        Flexible(child: chip(scopeLabel(rule), onTap: () => pickRooms(index))),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => save(
              settings.copyWith(rules: [...settings.rules]..removeAt(index))),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Panel(
      header: labelMessageFiltersTitle,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tiamat.Text.labelLow(labelMessageFiltersDescription),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    onSubmitted: (_) => add(),
                    decoration: InputDecoration(
                        hintText: labelMessageFilterAddHint,
                        errorText: error,
                        isDense: true,
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: add, child: Text(labelMessageFilterAdd)),
              ]),
              const SizedBox(height: 8),
              for (var i = 0; i < settings.rules.length; i++) ruleRow(i),
              const Divider(),
              tiamat.Text.labelEmphasised(labelFilteredShowAs),
              tiamat.RadioButton<FilteredMessageDisplay>(
                value: FilteredMessageDisplay.note,
                groupValue: settings.display,
                text: labelFilteredShowAsNote,
                onChanged: (v) => save(settings.copyWith(display: v)),
              ),
              tiamat.RadioButton<FilteredMessageDisplay>(
                value: FilteredMessageDisplay.nothing,
                groupValue: settings.display,
                text: labelFilteredShowAsNothing,
                onChanged: (v) => save(settings.copyWith(display: v)),
              ),
              const Divider(),
              CheckboxListTile(
                value: settings.noNotifications,
                title: Text(labelFilteredNoNotifications),
                onChanged: (v) =>
                    save(settings.copyWith(noNotifications: v ?? true)),
              ),
              CheckboxListTile(
                value: settings.skipOwnAndDms,
                title: Text(labelFilteredSkipOwnAndDms),
                onChanged: (v) =>
                    save(settings.copyWith(skipOwnAndDms: v ?? true)),
              ),
              CheckboxListTile(
                value: settings.matchSenderNames,
                title: Text(labelFilteredMatchSenderNames),
                onChanged: (v) =>
                    save(settings.copyWith(matchSenderNames: v ?? true)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
