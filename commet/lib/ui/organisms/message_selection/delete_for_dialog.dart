import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Who "Delete" removes the selected messages for.
enum DeleteFor { me, everyone }

/// Vommet issue 533: the Telegram-style "Delete for me / Delete for
/// everyone" prompt for selected messages. "For everyone" only shows when
/// at least one of them may be deleted; the rest are then only hidden.
class DeleteForDialog extends StatelessWidget {
  const DeleteForDialog(
      {required this.count, required this.deletable, super.key});

  /// How many messages are selected.
  final int count;

  /// How many of them you may delete for everyone.
  final int deletable;

  static String deleteForTitle(int count) => Intl.plural(count,
      one: "Delete 1 message?",
      other: "Delete $count messages?",
      args: [count],
      name: "deleteForTitle",
      desc:
          "Selecting several messages: title of the Delete for me / Delete for everyone dialog");

  static String get deleteForPrompt => Intl.message(
      "Are you sure you want to delete these messages?",
      name: "deleteForPrompt",
      desc:
          "Selecting several messages: text of the Delete for me / Delete for everyone dialog");

  static String deleteForKept(int count) => Intl.plural(count,
      one:
          "1 message can't be deleted for everyone, so it's only hidden for you.",
      other:
          "$count messages can't be deleted for everyone, so they're only hidden for you.",
      args: [count],
      name: "deleteForKept",
      desc:
          "Selecting several messages: note in the delete dialog when some selected messages can't be deleted for everyone");

  static String get deleteForNone => Intl.message(
      "You can't delete these for everyone, so they're only hidden for you.",
      name: "deleteForNone",
      desc:
          "Selecting several messages: note in the delete dialog when none of the selected messages can be deleted for everyone");

  static String get deleteForEveryone => Intl.message("Delete for everyone",
      name: "deleteForEveryone",
      desc:
          "Selecting several messages: button that deletes the messages for everyone in the room");

  static String get deleteForMe => Intl.message("Delete for me",
      name: "deleteForMe",
      desc:
          "Selecting several messages: button that hides the messages only for you, on all your Vommet devices");

  static Future<DeleteFor?> ask(BuildContext context,
          {required int count, required int deletable}) =>
      AdaptiveDialog.show<DeleteFor>(context,
          title: deleteForTitle(count),
          builder: (_) => DeleteForDialog(count: count, deletable: deletable));

  @override
  Widget build(BuildContext context) {
    final kept = count - deletable;
    return SizedBox(
      width: MediaQuery.of(context).desktop ? 500 : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: tiamat.Text.label(deleteForPrompt),
            ),
            if (kept > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: tiamat.Text.labelLow(
                    deletable == 0 ? deleteForNone : deleteForKept(kept)),
              ),
            if (deletable > 0) ...[
              SizedBox(
                height: 40,
                child: tiamat.Button.critical(
                  text: deleteForEveryone,
                  onTap: () => Navigator.pop(context, DeleteFor.everyone),
                ),
              ),
              const SizedBox(height: 5),
            ],
            SizedBox(
              height: 40,
              child: tiamat.Button.danger(
                text: deleteForMe,
                onTap: () => Navigator.pop(context, DeleteFor.me),
              ),
            ),
            const SizedBox(height: 5),
            tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
