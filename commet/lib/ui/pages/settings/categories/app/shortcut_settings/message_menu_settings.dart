// Vommet issue 1213: menu bindings work even without OS-wide shortcut support.
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/message_menu_bindings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MessageMenuSettings extends StatefulWidget {
  const MessageMenuSettings({super.key, required this.bindings});
  final MessageMenuBindings bindings;

  static String get title => Intl.message(
        'Message menu',
        name: 'messageMenuKeysTitle',
        desc:
            'Settings section for single-letter message context menu bindings',
      );
  static String get description => Intl.message(
        'Press a letter while a message menu is open to activate its action. Saved on this device for all accounts.',
        name: 'messageMenuKeysDescription',
        desc: 'Explains the scope of menu keys',
      );
  static String get prompt => Intl.message(
        'Press a letter (A–Z)',
        name: 'messageMenuKeyPrompt',
        desc: 'Prompt for one menu accelerator letter',
      );
  static String get clear => Intl.message(
        'Clear binding',
        name: 'messageMenuKeyClear',
        desc: 'Remove the key assigned to a menu action',
      );
  static String get restore => Intl.message(
        'Restore defaults',
        name: 'messageMenuKeysRestore',
        desc: 'Restore all message menu key defaults together',
      );
  static String get unbound => Intl.message(
        'Unbound',
        name: 'messageMenuKeyUnbound',
        desc: 'A menu action with no assigned key',
      );
  static String duplicate(String key, String action) => Intl.message(
        '$key is already assigned to $action in Message menu. Choose another letter.',
        name: 'messageMenuKeyDuplicate',
        args: [key, action],
        desc:
            'Explains a duplicate menu key; key is a letter, action is an action label',
      );

  @override
  State<MessageMenuSettings> createState() => _MessageMenuSettingsState();
}

class _MessageMenuSettingsState extends State<MessageMenuSettings> {
  Future<void> _edit(MessageMenuAction action) async {
    String? candidate;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(action.label),
          content: SizedBox(
            width: 320,
            child: TextField(
              autofocus: true,
              maxLength: 1,
              decoration: InputDecoration(
                labelText: MessageMenuSettings.prompt,
                errorText: error,
                errorMaxLines: 4,
              ),
              onChanged: (value) => update(() {
                candidate = MessageMenuBindings.normalize(value);
                final conflict = candidate == null
                    ? null
                    : widget.bindings.conflict(action, candidate!);
                error = conflict == null
                    ? null
                    : MessageMenuSettings.duplicate(candidate!, conflict.label);
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(CommonStrings.promptCancel),
            ),
            TextButton(
              onPressed: () async {
                await widget.bindings.set(action, null);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(MessageMenuSettings.clear),
            ),
            TextButton(
              onPressed: candidate == null || error != null
                  ? null
                  : () async {
                      if (await widget.bindings.set(action, candidate) &&
                          dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
              child: Text(CommonStrings.promptSubmit),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => tiamat.Panel(
        mode: tiamat.TileType.surfaceContainerLow,
        header: MessageMenuSettings.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(MessageMenuSettings.description),
            for (final entry in widget.bindings.keys.entries)
              ListTile(
                title: Text(entry.key.label),
                trailing: Text(entry.value ?? MessageMenuSettings.unbound),
                onTap: () => _edit(entry.key),
              ),
            TextButton(
              onPressed: () async {
                await widget.bindings.reset();
                if (mounted) setState(() {});
              },
              child: Text(MessageMenuSettings.restore),
            ),
          ],
        ),
      );
}
