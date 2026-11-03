import 'dart:async';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/composer_notice.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: in a direct message with someone you've blocked, the composer
/// becomes a "You blocked …" footer with an Unblock button, so you can't
/// type to them by accident. Part of the block-users experiment.
class BlockedDmGate extends StatefulWidget {
  const BlockedDmGate({required this.room, required this.child, super.key});

  final Room room;

  /// The composer, shown when the DM partner isn't blocked.
  final Widget child;

  /// The blocked DM partner's user id, or null when [room] isn't a DM with
  /// someone you've blocked (or blocking is off).
  static String? blockedPartner(Room room) {
    if (!preferences.experimentBlockUsers.value) return null;
    final blocking = room.client.getComponent<UserBlockingComponent>();
    if (blocking == null) return null;
    final partner = room.client
        .getComponent<DirectMessagesComponent>()
        ?.getDirectMessagePartnerId(room);
    if (partner == null || !blocking.isBlocked(partner)) return null;
    return partner;
  }

  @override
  State<BlockedDmGate> createState() => _BlockedDmGateState();
}

class _BlockedDmGateState extends State<BlockedDmGate> {
  StreamSubscription? sub;
  bool unblocking = false;

  String youBlockedUser(String name) => Intl.message("You blocked $name",
      args: [name],
      name: "youBlockedUser",
      desc: "Shown in place of the message input in a DM with a blocked user");

  String get youBlockedUserExplanation =>
      Intl.message("You won't see their messages, invites, or calls.",
          name: "youBlockedUserExplanation",
          desc: "Explains what blocking does, under youBlockedUser");

  String get unblockUser => Intl.message("Unblock",
      name: "unblockUser",
      desc: "Button that unblocks the other person in a DM");

  @override
  void initState() {
    super.initState();
    listen();
  }

  @override
  void didUpdateWidget(covariant BlockedDmGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      sub?.cancel();
      listen();
    }
  }

  void listen() {
    sub = widget.room.client
        .getComponent<UserBlockingComponent>()
        ?.onChanged
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> unblock(String partner) async {
    final blocking = widget.room.client.getComponent<UserBlockingComponent>();
    if (blocking == null || unblocking) return;
    setState(() => unblocking = true);
    try {
      await blocking.unblock(partner);
    } catch (e, s) {
      if (mounted) await AdaptiveDialog.showError(context, e, s);
    } finally {
      if (mounted) setState(() => unblocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner = BlockedDmGate.blockedPartner(widget.room);
    if (partner == null) return widget.child;

    final name = widget.room.getMemberOrFallback(partner).displayName;
    return ComposerNotice(
      icon: Icons.block,
      title: youBlockedUser(name),
      subtitle: youBlockedUserExplanation,
      actionLabel: unblockUser,
      onAction: () => unblock(partner),
    );
  }
}
