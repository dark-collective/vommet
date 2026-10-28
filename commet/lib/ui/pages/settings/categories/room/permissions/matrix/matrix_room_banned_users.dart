// Vommet: "Banned users" section of the room/space Permissions page, like
// Element's Roles & Permissions: who is banned, by whom, why, and Unban.
import 'dart:async';

import 'package:commet/client/matrix/matrix_member.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart' show Panel, TileType;

class BannedUserItem {
  const BannedUserItem({
    required this.userId,
    required this.displayName,
    required this.color,
    this.bannedBy,
    this.reason,
  });
  final String userId;
  final String displayName;
  final Color color;

  /// Display name of whoever sent the ban.
  final String? bannedBy;
  final String? reason;
}

/// Pure view of the banned list. Hidden by the caller when empty.
class BannedUsersView extends StatelessWidget {
  const BannedUsersView({
    super.key,
    required this.items,
    required this.canUnban,
    this.onUnban,
    this.busy = const {},
  });
  final List<BannedUserItem> items;
  final bool canUnban;
  final void Function(BannedUserItem item)? onUnban;

  /// User ids with an unban in flight.
  final Set<String> busy;

  static String get labelBannedUsers => Intl.message(
        "Banned users",
        name: "labelBannedUsers",
        desc: "Header of the room permissions section listing banned people",
      );

  static String labelBannedBy(String name) => Intl.message(
        "Banned by $name",
        name: "labelBannedBy",
        args: [name],
        desc: "Who banned a user, under their name in the banned users list",
      );

  static String labelBanReason(String reason) => Intl.message(
        "Reason: $reason",
        name: "labelBanReason",
        args: [reason],
        desc: "The reason given for a ban, in the banned users list",
      );

  static String get labelUnban => Intl.message(
        "Unban",
        name: "labelUnbanUser",
        desc: "Button to lift a user's ban from the room",
      );

  @override
  Widget build(BuildContext context) {
    return Panel(
      header: labelBannedUsers,
      mode: TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final item in items) _row(context, item)],
      ),
    );
  }

  Widget _row(BuildContext context, BannedUserItem item) {
    final name = item.displayName.isNotEmpty ? item.displayName : item.userId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: [
          tiamat.Avatar.small(
            placeholderText: name.replaceFirst("@", "").characters.first,
            placeholderColor: item.color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(name,
                    overflow: TextOverflow.ellipsis),
                tiamat.Text.labelLow(item.userId,
                    overflow: TextOverflow.ellipsis),
                if (item.bannedBy != null)
                  tiamat.Text.labelLow(labelBannedBy(item.bannedBy!)),
                if (item.reason != null && item.reason!.trim().isNotEmpty)
                  tiamat.Text.labelLow(labelBanReason(item.reason!.trim()),
                      maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (canUnban && onUnban != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
              child: tiamat.Button.secondary(
                text: labelUnban,
                isLoading: busy.contains(item.userId),
                onTap: () => onUnban!(item),
              ),
            ),
        ],
      ),
    );
  }
}

/// Live section: banned members from the room state plus the server's member
/// list (lazy loading may leave bans out of the local state).
class MatrixRoomBannedUsers extends StatefulWidget {
  const MatrixRoomBannedUsers(this.room, {super.key});
  final matrix.Room room;

  @override
  State<MatrixRoomBannedUsers> createState() => _MatrixRoomBannedUsersState();
}

class _MatrixRoomBannedUsersState extends State<MatrixRoomBannedUsers> {
  StreamSubscription? sub;
  final Map<String, matrix.StrippedStateEvent> fetched = {};
  final Set<String> busy = {};

  static String unbanPrompt(String name) => Intl.message(
        "Unban $name? They'll be able to join again.",
        name: "promptUnbanUser",
        args: [name],
        desc: "Confirmation before lifting a user's ban",
      );

  @override
  void initState() {
    super.initState();
    sub = widget.room.onUpdate.stream.listen((_) {
      if (mounted) setState(() {});
    });
    fetchBans();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> fetchBans() async {
    try {
      final events = await widget.room.client
          .getMembersByRoom(widget.room.id, membership: matrix.Membership.ban);
      if (events == null || !mounted) return;
      setState(() {
        for (final e in events) {
          final key = e.stateKey;
          if (key != null) fetched[key] = e;
        }
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't load the room's banned members");
    }
  }

  List<BannedUserItem> get items {
    // Local state wins: it reflects unbans that happened after the fetch.
    final byId = <String, matrix.StrippedStateEvent>{...fetched};
    final local = widget.room.states[matrix.EventTypes.RoomMember];
    if (local != null) {
      for (final e in local.entries) {
        byId[e.key] = e.value;
      }
    }

    final result = <BannedUserItem>[];
    for (final e in byId.entries) {
      if (e.value.content["membership"] != "ban") continue;
      final userId = e.key;
      final reason = e.value.content["reason"];
      final sender = e.value.senderId;
      result.add(BannedUserItem(
        userId: userId,
        displayName: _name(userId, e.value.content["displayname"]),
        color: MatrixMember.hashColor(userId),
        bannedBy: sender.isEmpty ? null : _name(sender, null),
        reason: reason is String ? reason : null,
      ));
    }
    result.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return result;
  }

  String _name(String userId, Object? fromEvent) {
    if (fromEvent is String && fromEvent.isNotEmpty) return fromEvent;
    return widget.room
        .unsafeGetUserFromMemoryOrFallback(userId)
        .calcDisplayname();
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list.isEmpty) return const SizedBox.shrink();
    return BannedUsersView(
      items: list,
      canUnban: widget.room.canBan,
      busy: busy,
      onUnban: unban,
    );
  }

  Future<void> unban(BannedUserItem item) async {
    final ok = await AdaptiveDialog.confirmation(context,
        prompt: unbanPrompt(item.displayName),
        confirmationText: BannedUsersView.labelUnban);
    if (ok != true || !mounted) return;

    setState(() => busy.add(item.userId));
    await ErrorUtils.tryRun(context, () async {
      await widget.room.unban(item.userId);
      fetched.remove(item.userId);
    });
    if (mounted) setState(() => busy.remove(item.userId));
  }
}
