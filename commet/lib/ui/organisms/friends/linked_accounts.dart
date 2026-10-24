import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/friends/friends_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_model.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// One Matrix account of a person, for the Accounts dialog.
class LinkedAccount {
  const LinkedAccount(this.userId, this.status, {required this.main});
  final String userId;

  /// The account's status line ("Online", "Away", a status message).
  final String status;
  final bool main;
}

/// Vommet (Vommet issue 638): one contact for a person with several Matrix
/// accounts, shared by the Friends tab and New Home's People. Linking is by
/// hand only, never guessed from matching names, so nobody can be merged
/// into a contact by copying a name and avatar.
class LinkedAccounts {
  /// Messages a person: straight to [open] with one account, else a sheet
  /// to pick which account to write to, the ones with a DM first.
  static Future<void> message(BuildContext context,
      {required Client client,
      required String name,
      required List<String> accounts,
      required Future<void> Function(String userId) open}) async {
    if (accounts.length < 2) return open(accounts.first);
    final dms = client.getComponent<DirectMessagesComponent>();
    final lastDm = <String, DateTime>{};
    for (final room in dms?.directMessageRooms ?? <Room>[]) {
      final id = dms!.getDirectMessagePartnerId(room);
      if (id == null || !accounts.contains(id)) continue;
      final at = room.lastEventTimestamp;
      if (lastDm[id]?.isAfter(at) != true) lastDm[id] = at;
    }
    final order = FriendsModel.dmPickOrder(accounts, lastDm);
    final picked = await AdaptiveDialog.show<String>(
      context,
      title: "Message $name",
      builder: (context) => _PickAccount(order, lastDm),
    );
    if (picked != null) await open(picked);
  }

  /// The person's accounts, with Make main, Unlink and Link another account.
  static Future<void> showAccounts(BuildContext context,
      {required Client client,
      required String name,
      required List<LinkedAccount> accounts,
      required List<(String, String)> candidates}) async {
    final picked = await AdaptiveDialog.show<(_Action, String)>(
      context,
      title: name,
      builder: (context) => _Accounts(accounts),
    );
    if (picked == null || !context.mounted) return;
    final friends = client.getComponent<FriendsComponent>();
    if (friends == null) return;
    switch (picked) {
      case (_Action.makeMain, final id):
        await _attempt(context, "change the main account",
            () => friends.setMainFriend(id));
      case (_Action.unlink, final id):
        await _attempt(
            context, "unlink the account", () => friends.unlinkFriend(id));
      case (_Action.link, _):
        await linkAnother(context,
            client: client,
            mainId: accounts.firstWhere((a) => a.main).userId,
            name: name,
            candidates: candidates);
    }
  }

  /// Links another account into [mainId]'s contact: one of your other
  /// [candidates] (user ID, name), or a typed Matrix ID that exists.
  static Future<void> linkAnother(BuildContext context,
      {required Client client,
      required String mainId,
      required String name,
      required List<(String, String)> candidates}) async {
    final friends = client.getComponent<FriendsComponent>();
    if (friends == null) return;
    final id = await AdaptiveDialog.show<String>(
      context,
      title: "Link an account to $name",
      builder: (context) => _LinkForm(friends, candidates),
    );
    if (id == null) return;
    await _attempt(
        context, "link the account", () => friends.linkFriend(mainId, id));
  }

  static Future<void> _attempt(
      BuildContext context, String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      Log.w("Linked accounts: couldn't $what: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text("Couldn't $what.")));
    }
  }
}

class _PickAccount extends StatelessWidget {
  const _PickAccount(this.accounts, this.lastDm);
  final List<String> accounts;
  final Map<String, DateTime> lastDm;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final now = DateTime.now();
    return SizedBox(
      width: 380,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final id in accounts)
              InkWell(
                key: ValueKey("LinkedAccountsPick-$id"),
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).pop(id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(id,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w700)),
                        Text(
                            switch (lastDm[id]) {
                              final at? =>
                                "Open your DM · ${PeopleModel.relativeTime(at, now)}",
                              null => "No DM yet, starts one",
                            },
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ]),
                ),
              ),
          ]),
    );
  }
}

enum _Action { makeMain, unlink, link }

class _Accounts extends StatelessWidget {
  const _Accounts(this.accounts);
  final List<LinkedAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    void act(_Action action, String userId) =>
        Navigator.of(context).pop((action, userId));

    return SizedBox(
      width: 420,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Text("${accounts.length} linked accounts. Only you see this.",
                style: TextStyle(color: scheme.onSurfaceVariant)),
            for (final a in accounts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(spacing: 8, children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Row(spacing: 6, children: [
                            Flexible(
                              child: Text(a.userId,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (a.main) const AccountsTag("Main"),
                          ]),
                          Text(a.status,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant)),
                        ]),
                  ),
                  if (!a.main)
                    TextButton(
                      onPressed: () => act(_Action.makeMain, a.userId),
                      child: const Text("Make main"),
                    ),
                  TextButton(
                    onPressed: () => act(_Action.unlink, a.userId),
                    child: const Text("Unlink"),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            tiamat.Button(
              text: "Link another account",
              onTap: () => act(_Action.link, ""),
            ),
          ]),
    );
  }
}

class _LinkForm extends StatefulWidget {
  const _LinkForm(this.friends, this.candidates);
  final FriendsComponent friends;
  final List<(String, String)> candidates;

  @override
  State<_LinkForm> createState() => _LinkFormState();
}

class _LinkFormState extends State<_LinkForm> {
  String text = "";

  /// The typed Matrix ID being checked, and whether it exists (null while
  /// checking or when we can't tell).
  String? checkedId;
  bool? exists;
  bool checking = false;

  Future<void> onChanged(String value) async {
    final id = value.trim();
    setState(() {
      text = value;
      checkedId = FriendsModel.isUserId(id) ? id : null;
      exists = null;
      checking = checkedId != null;
    });
    if (checkedId == null) return;
    final found = await widget.friends.accountExists(id);
    if (!mounted || checkedId != id) return;
    setState(() {
      exists = found;
      checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final q = text.trim().toLowerCase().replaceFirst("@", "");
    final shown = [
      for (final (id, name) in widget.candidates)
        if (q.isEmpty ||
            id.toLowerCase().contains(q) ||
            name.toLowerCase().contains(q))
          (id, name)
    ];
    final typed = checkedId;
    final typedListed =
        typed != null && widget.candidates.any((c) => c.$1 == typed);
    return SizedBox(
      width: 420,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const Text("Pick another Matrix account this person uses. "
                "They show as one contact; only you see the link."),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: "A contact, or @name:server.org",
              ),
              onChanged: onChanged,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(shrinkWrap: true, children: [
                for (final (id, name) in shown)
                  _LinkRow(
                    key: ValueKey("LinkedAccountsCandidate-$id"),
                    title: name,
                    subtitle: id,
                    onLink: () => Navigator.of(context).pop(id),
                  ),
                if (typed != null && !typedListed)
                  _LinkRow(
                    title: typed,
                    subtitle: switch ((checking, exists)) {
                      (true, _) => "Checking this account…",
                      (_, true) => "Account found",
                      (_, false) =>
                        "No account with this ID. Check the spelling.",
                      _ =>
                        "Couldn't check this account. Link it only if you're sure.",
                    },
                    onLink: checking || exists == false
                        ? null
                        : () => Navigator.of(context).pop(typed),
                  ),
              ]),
            ),
            if (shown.isEmpty && typed == null)
              Text(
                  widget.candidates.isEmpty
                      ? "Type their other account's full Matrix ID, like @name:server.org."
                      : "No matches. Try a full Matrix ID, like @name:server.org.",
                  style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(
      {required this.title,
      required this.subtitle,
      required this.onLink,
      super.key});
  final String title;
  final String subtitle;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(spacing: 10, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text(subtitle,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ]),
        ),
        TextButton(onPressed: onLink, child: const Text("Link")),
      ]),
    );
  }
}

/// The small "2 accounts" / "Main" tag.
class AccountsTag extends StatelessWidget {
  const AccountsTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
          color: scheme.primary.withAlpha(40),
          borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: scheme.primary)),
    );
  }
}
