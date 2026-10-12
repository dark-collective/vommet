import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' show Panel, TileType;
import 'package:tiamat/tiamat.dart' as tiamat;

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
            title: "Couldn't update your block list",
            builder: (_) => tiamat.Text.label(e is ArgumentError
                ? "${e.message}"
                : "Your server didn't accept the change. Try again."));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _blockTyped() async {
    final id = _input.text.trim();
    if (id.isEmpty) return;
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: "Block $id?",
        prompt: "You won't see their messages, invites or calls, on any of "
            "your devices. They aren't told.",
        confirmationText: "Block",
        cancelText: "Cancel",
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
      header: "Blocked users",
      mode: TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: tiamat.Text.labelLow(
                "Blocked people's messages, invites and calls are hidden on "
                "all your devices (your account's ignore list, which other "
                "Matrix apps honour too). They aren't told."),
          ),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: tiamat.Text.label("You haven't blocked anyone."),
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
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: "@someone:example.org",
                      labelText: "Block someone by Matrix ID",
                    ),
                    onSubmitted: (_) => _blockTyped(),
                  ),
                ),
                const SizedBox(width: 8),
                tiamat.Button(
                  text: "Block",
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
                child: const Text("Unblock"),
              ),
            ],
          ),
        );
      },
    );
  }
}
