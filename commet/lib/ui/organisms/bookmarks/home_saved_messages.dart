import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages_account.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Home can show all accounts; a saved list always belongs to one account.
class HomeSavedMessages extends StatelessWidget {
  const HomeSavedMessages({super.key, this.manager, this.filterClient});

  final ClientManager? manager;
  final Client? filterClient;

  static String get chooseAccount => Intl.message('Choose an account',
      name: 'savedMessagesChooseAccount',
      desc: 'Prompt to select the account whose saved messages to open');

  static String get unavailable =>
      Intl.message('Saved messages are unavailable for the current accounts',
          name: 'savedMessagesAccountsUnavailable',
          desc: 'Explains why the Home Saved messages action is disabled');

  List<Client> get eligible => [
        for (final client in manager?.clients ?? <Client>[])
          if ((filterClient == null || identical(client, filterClient)) &&
              Bookmarks.supported(client))
            client,
      ];

  Future<void> open(BuildContext context) async {
    final accounts = eligible;
    if (accounts.isEmpty) return;
    Client? selected = accounts.length == 1 ? accounts.single : null;
    while (context.mounted) {
      selected ??= await AdaptiveDialog.show<Client>(context,
          title: SavedMessages.savedMessagesTitle,
          builder: (context) => StreamBuilder(
              stream: manager?.clients.onListUpdated,
              builder: (context, _) {
                final accounts = eligible;
                return SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                            accounts.isEmpty ? unavailable : chooseAccount),
                      ),
                      for (final client in accounts)
                        SavedMessagesAccount(
                          client: client,
                          onTap: () {
                            // Recheck in case logout preceded the stream rebuild.
                            if (eligible.contains(client)) {
                              Navigator.of(context).pop(client);
                            }
                          },
                        ),
                    ],
                  ),
                );
              }));
      if (!context.mounted || selected == null) return;
      if (eligible.contains(selected)) {
        await SavedMessages.show(context, selected);
        return;
      }
      // An account removed as the chooser closed must be chosen again.
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
      stream: manager?.clients.onListUpdated,
      builder: (context, _) {
        final enabled = eligible.isNotEmpty;
        return IconButton(
          key: const ValueKey('HomeSavedMessages'),
          tooltip: enabled ? SavedMessages.savedMessagesTitle : unavailable,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          icon: const Icon(Icons.bookmarks_outlined),
          onPressed: enabled ? () => open(context) : null,
        );
      });
}
