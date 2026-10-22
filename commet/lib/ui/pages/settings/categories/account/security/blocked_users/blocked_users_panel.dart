import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' show Panel, TileType;
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: Settings › Security › Blocked users (experiment).
class BlockedUsersPanel extends StatefulWidget {
  const BlockedUsersPanel(this.client, {super.key});
  final Client client;

  @override
  State<BlockedUsersPanel> createState() => _BlockedUsersPanelState();
}

class _BlockedUsersPanelState extends State<BlockedUsersPanel> {
  UserBlockingComponent? get component =>
      widget.client.getComponent<UserBlockingComponent>();

  StreamSubscription? _sub;
  final TextEditingController _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = component?.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() change) async {
    setState(() => _busy = true);
    try {
      await change();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not change the block list");
      if (mounted) {
        AdaptiveDialog.show(context,
            title: blockedUsersUpdateFailedTitle,
            builder: (_) => tiamat.Text.label(e is ArgumentError
                ? "${e.message}"
                : blockedUsersUpdateFailedBody));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _blockTyped() async {
    final id = _input.text.trim();
    if (id.isEmpty) return;
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: blockedUsersBlockTitle(id),
        prompt: blockedUsersBlockPrompt,
        confirmationText: blockedUsersBlockConfirm,
        cancelText: blockedUsersCancel,
        dangerous: true);
    if (confirmed != true) return;
    await _run(() => component!.block(id));
    if (mounted && component?.isBlocked(id) == true) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final component = this.component;
    if (component == null) return const SizedBox.shrink();
    final users = component.blockedUsers;
    return Panel(
      header: blockedUsersHeader,
      mode: TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: tiamat.Text.labelLow(blockedUsersExplain),
          ),
          if (users.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: tiamat.Text.label(blockedUsersEmpty),
            ),
          for (final id in users)
            _BlockedUserRow(
              key: ValueKey("blocked-$id"),
              client: widget.client,
              userId: id,
              busy: _busy,
              onUnblock: () => _run(() => component.unblock(id)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey("block-user-input"),
                    controller: _input,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "@someone:example.org",
                      labelText: blockedUsersInputLabel,
                    ),
                    onSubmitted: (_) => _blockTyped(),
                  ),
                ),
                const SizedBox(width: 8),
                tiamat.Button(
                  text: blockedUsersBlockButton,
                  isLoading: _busy,
                  onTap: _blockTyped,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedUserRow extends StatelessWidget {
  const _BlockedUserRow(
      {required this.client,
      required this.userId,
      required this.busy,
      required this.onUnblock,
      super.key});
  final Client client;
  final String userId;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: client
          .getComponent<UserProfileComponent>()
          ?.getProfile(userId)
          .then<Profile?>((p) => p)
          .catchError((_) => null),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final name = profile?.displayName ?? userId;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              tiamat.Avatar(
                image: profile?.avatar,
                placeholderText: name,
                placeholderColor: profile?.defaultColor,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tiamat.Text.label(name, maxLines: 1),
                    if (name != userId)
                      tiamat.Text.labelLow(userId, maxLines: 1),
                  ],
                ),
              ),
              TextButton(
                key: ValueKey("unblock-$userId"),
                onPressed: busy ? null : onUnblock,
                child: Text(blockedUsersUnblock),
              ),
            ],
          ),
        );
      },
    );
  }
}

String get blockedUsersUpdateFailedTitle =>
    Intl.message("Couldn't update your block list",
        name: "blockedUsersUpdateFailedTitle",
        desc: "Title of the error dialog when changing the block list failed");

String get blockedUsersUpdateFailedBody => Intl.message(
    "Your server didn't accept the change. Try again.",
    name: "blockedUsersUpdateFailedBody",
    desc:
        "Body of the error dialog when the server refused the block list change");

String blockedUsersBlockTitle(String id) => Intl.message("Block $id?",
    args: [id],
    name: "blockedUsersBlockTitle",
    desc: "Title of the block confirmation; id is the Matrix user ID");

String get blockedUsersBlockPrompt => Intl.message(
    "You won't see their messages, invites, or calls, on any of your devices. They aren't told.",
    name: "blockedUsersBlockPrompt",
    desc: "Body of the block confirmation in the Blocked users settings");

String get blockedUsersBlockConfirm => Intl.message("Block",
    name: "blockedUsersBlockConfirm",
    desc: "Confirm button of the block dialog");

String get blockedUsersCancel => Intl.message("Cancel",
    name: "blockedUsersCancel", desc: "Cancel button of the block dialog");

String get blockedUsersHeader => Intl.message("Blocked users",
    name: "blockedUsersHeader",
    desc: "Header of the Blocked users settings panel");

String get blockedUsersExplain => Intl.message(
    "Blocked people's messages, invites, and calls are hidden on all your devices (your account's ignore list, which other Matrix apps honour too). They aren't told.",
    name: "blockedUsersExplain",
    desc: "Explanation at the top of the Blocked users settings panel");

String get blockedUsersEmpty => Intl.message("You haven't blocked anyone.",
    name: "blockedUsersEmpty", desc: "Shown when the user has blocked nobody");

String get blockedUsersInputLabel => Intl.message("Block someone by Matrix ID",
    name: "blockedUsersInputLabel",
    desc: "Label of the field for blocking someone by Matrix ID");

String get blockedUsersBlockButton => Intl.message("Block",
    name: "blockedUsersBlockButton",
    desc: "Button next to the Matrix ID field that blocks the user");

String get blockedUsersUnblock => Intl.message("Unblock",
    name: "blockedUsersUnblock",
    desc: "Button that unblocks a user in the Blocked users list");
