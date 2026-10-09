import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/room_directory/directory_account_handle.dart';
import 'package:commet/ui/pages/room_directory/directory_strings.dart';
import 'package:commet/utils/room_directory/directory_accounts.dart';
import 'package:commet/utils/room_directory/directory_servers.dart';
import 'package:flutter/material.dart';

class DirectoryServerChoice {
  final String server;

  /// Also add it to the saved servers
  final bool save;

  const DirectoryServerChoice(this.server, {this.save = false});
}

/// Server chooser: your servers, saved servers, suggestions, plus a search
/// box that narrows them all and offers "Browse <typed server>". Every
/// section is capped, so a long saved list never crowds the popup.
class DirectoryServerChooser extends StatefulWidget {
  const DirectoryServerChooser({
    required this.accounts,
    required this.current,
    required this.store,
    required this.onChosen,
    super.key,
  });

  final List<DirectoryAccountHandle> accounts;
  final DirectoryAccountHandle current;
  final DirectoryServerStore store;
  final void Function(DirectoryServerChoice choice) onChosen;

  static Future<DirectoryServerChoice?> show(
    BuildContext context, {
    required List<DirectoryAccountHandle> accounts,
    required DirectoryAccountHandle current,
    required DirectoryServerStore store,
  }) {
    return AdaptiveDialog.show<DirectoryServerChoice>(
      context,
      title: directoryServerChoose,
      builder: (dialogContext) => SizedBox(
        width: 420,
        child: DirectoryServerChooser(
          accounts: accounts,
          current: current,
          store: store,
          onChosen: (choice) => Navigator.of(dialogContext).pop(choice),
        ),
      ),
    );
  }

  @override
  State<DirectoryServerChooser> createState() => _DirectoryServerChooserState();
}

class _DirectoryServerChooserState extends State<DirectoryServerChooser> {
  String search = "";

  @override
  Widget build(BuildContext context) {
    var all = widget.accounts.map((a) => a.account).toList();
    var sections = DirectoryServers.sections(
      own: DirectoryAccounts.ownServers(widget.current.account, all),
      saved: widget.store.saved,
      showSuggestions: widget.store.showSuggestions,
      search: search,
    );
    var theme = Theme.of(context);

    Widget header(String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
          child: Row(children: [
            Expanded(child: Text(text, style: theme.textTheme.labelLarge)),
            if (trailing != null) trailing,
          ]),
        );

    String? viaFor(String server) {
      if (server == widget.current.account.homeserver) return null;
      for (var a in widget.accounts) {
        if (a.account.homeserver == server) return a.userId;
      }
      return null;
    }

    Widget tile(String server, {Widget? trailing, IconData? icon}) => ListTile(
          key: ValueKey("directory_server_$server"),
          dense: true,
          leading: Icon(icon ?? Icons.dns_outlined, size: 20),
          title: Text(server),
          subtitle: viaFor(server) == null
              ? null
              : Text(directoryServerVia(viaFor(server)!)),
          trailing: trailing,
          onTap: () => widget.onChosen(DirectoryServerChoice(server)),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey("directory_server_search"),
          autofocus: true,
          decoration: InputDecoration(
            hintText: directoryServerSearch,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => search = v),
          onSubmitted: (v) {
            var server = DirectoryServers.normalize(v);
            if (server != null) widget.onChosen(DirectoryServerChoice(server));
          },
        ),
        if (sections.customServer != null)
          ListTile(
            key: const ValueKey("directory_server_custom"),
            dense: true,
            leading: const Icon(Icons.travel_explore, size: 20),
            title: Text(directoryServerBrowse(sections.customServer!)),
            trailing: IconButton(
              key: const ValueKey("directory_server_custom_save"),
              tooltip: directoryServerSave,
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () => widget.onChosen(
                  DirectoryServerChoice(sections.customServer!, save: true)),
            ),
            onTap: () =>
                widget.onChosen(DirectoryServerChoice(sections.customServer!)),
          ),
        if (sections.own.isNotEmpty) ...[
          header(directoryServerYours),
          for (var s in sections.own) tile(s, icon: Icons.home_outlined),
        ],
        if (sections.saved.isNotEmpty) ...[
          header(directoryServerSaved),
          for (var s in sections.saved)
            tile(s,
                icon: Icons.bookmark_outline,
                trailing: IconButton(
                  key: ValueKey("directory_server_remove_$s"),
                  tooltip: directoryServerUnsave,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    await widget.store.setSaved(
                        DirectoryServers.remove(widget.store.saved, s));
                    if (mounted) setState(() {});
                  },
                )),
          if (sections.hiddenSaved > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: Text(directoryServerMoreSaved(sections.hiddenSaved),
                  key: const ValueKey("directory_server_more_saved"),
                  style: theme.textTheme.bodySmall),
            ),
        ],
        if (sections.suggested.isNotEmpty) ...[
          header(directoryServerSuggested,
              trailing: TextButton(
                key: const ValueKey("directory_server_hide_suggested"),
                onPressed: () async {
                  await widget.store.setShowSuggestions(false);
                  if (mounted) setState(() {});
                },
                child: Text(directoryServerHideSuggested),
              )),
          for (var s in sections.suggested)
            tile(s,
                icon: Icons.public,
                trailing: IconButton(
                  tooltip: directoryServerSave,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  onPressed: () =>
                      widget.onChosen(DirectoryServerChoice(s, save: true)),
                )),
        ],
      ],
    );
  }
}
