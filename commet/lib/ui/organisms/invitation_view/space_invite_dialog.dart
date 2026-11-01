// Vommet: inviting someone to a space also offers its rooms and subspaces,
// ticked by default, each saying whether its history goes along (MSC4268:
// an invite to an encrypted room whose history is visible to new members
// also sends the keys to its earlier messages). The tree scrolls up and down
// for long lists and sideways for deep subspace nesting.
// Vommet issue 744: a tick to also share history in the space's rooms the
// person is already in (a history grant, sent after the invites).

import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/client/matrix/matrix_space_hierarchy.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/profile/mini_profile_view.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/share_history/share_history.dart';
import 'package:commet/ui/organisms/space_join_picker/leave_space_dialog.dart';
import 'package:commet/ui/organisms/space_join_picker/space_tree_view.dart';
import 'package:commet/utils/space_hierarchy/invite_plan.dart';
import 'package:commet/utils/space_hierarchy/leave_plan.dart';
import 'package:commet/utils/space_hierarchy/room_batch_task.dart';
import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

class SpaceInviteDialog extends StatefulWidget {
  static String spaceInviteTitle(String space) => Intl.message(
      "Invite to $space",
      args: [space],
      name: "spaceInviteTitle",
      desc:
          "Dialog for inviting someone to a space and its rooms: title; space is the space's name");

  const SpaceInviteDialog(
      {required this.space,
      required this.userId,
      required this.tree,
      required this.statuses,
      this.historyRooms = const [],
      this.shareHistory,
      super.key});

  final Space space;
  final String userId;
  final SpaceTree tree;
  final Map<String, InviteHistory> statuses;

  /// Encrypted rooms of the space [userId] has already joined, offered for
  /// a history grant through [shareHistory].
  final List<String> historyRooms;
  final ValueNotifier<bool>? shareHistory;

  /// The space's rooms [userId] has joined where we could share history.
  static List<String> joinedHistoryRooms(
      Client client, Iterable<String> roomIds, String userId) {
    return [
      for (final id in roomIds)
        if (client.getRoom(id) case final MatrixRoom room
            when ShareHistory.canShare(room, userId) &&
                room.matrixRoom
                        .getState(matrix.EventTypes.RoomMember, userId)
                        ?.content
                        .tryGet<String>("membership") ==
                    "join")
          id,
    ];
  }

  /// How a room's history goes along when inviting [userId] to [roomId].
  static InviteHistory statusOf(Client client, String roomId, String userId) {
    final space = client.getSpace(roomId);
    final room = client.getRoom(roomId);
    final matrix.Room? mx = space is MatrixSpace
        ? space.matrixRoom
        : room is MatrixRoom
            ? room.matrixRoom
            : null;
    final membership = mx
        ?.getState(matrix.EventTypes.RoomMember, userId)
        ?.content
        .tryGet<String>("membership");
    if (membership == "join" || membership == "invite") {
      return InviteHistory.alreadyMember;
    }
    final canInvite = space?.permissions.canInviteUser ??
        room?.permissions.canInviteUser ??
        false;
    if (!canInvite) return InviteHistory.cannotInvite;
    if (space != null) return InviteHistory.space;
    if (room?.isE2EE != true) return InviteHistory.notEncrypted;
    final visibility = mx?.historyVisibility;
    return visibility == matrix.HistoryVisibility.shared ||
            visibility == matrix.HistoryVisibility.worldReadable
        ? InviteHistory.included
        : InviteHistory.newMessagesOnly;
  }

  /// Whether we've never shared a direct message or a joined room with
  /// [userId] (as far as this device knows).
  static bool isFirstContact(Client client, String userId) {
    final dms = client.getComponent<DirectMessagesComponent>();
    if (dms != null &&
        dms.directMessageRooms
            .any((r) => dms.getDirectMessagePartnerId(r) == userId)) {
      return false;
    }
    for (final room in client.rooms) {
      if (room is! MatrixRoom) continue;
      final membership = room.matrixRoom
          .getState(matrix.EventTypes.RoomMember, userId)
          ?.content
          .tryGet<String>("membership");
      if (membership == "join") return false;
    }
    return true;
  }

  /// Asks which of [space]'s rooms to include, then invites [userId] to the
  /// space and those rooms (in the background when there are several).
  /// Returns false when cancelled.
  static Future<bool> invite(
      BuildContext context, Space space, String userId) async {
    final client = space.client;
    final component = client.getComponent<InvitationComponent>();
    if (component == null) return false;

    final index = LeaveSpaceDialog.indexOf(space);
    final statuses = {
      for (final id in index.infos.keys)
        if (id != space.identifier) id: statusOf(client, id, userId),
    };
    final tree = SpaceTree(
      spaceId: space.identifier,
      rootInfo: index.infos[space.identifier],
      fetch: index.fetcher,
      isJoined: (id) => !(statuses[id]?.invitable ?? false),
      selectionCap: SpaceTree.totalCap,
      // Local data: every level, however deep the subspaces go.
      depthLimit: 64,
    );
    await JoinedSpaceIndex.loadAll(tree);
    await tree.selectAll();
    if (!context.mounted) return false;

    final historyRooms = joinedHistoryRooms(client, statuses.keys, userId);
    final shareHistory = ValueNotifier(false);
    final ids = await AdaptiveDialog.show<List<String>>(context,
        title: spaceInviteTitle(space.displayName),
        scrollable: false,
        builder: (context) => SpaceInviteDialog(
            space: space,
            userId: userId,
            tree: tree,
            statuses: statuses,
            historyRooms: historyRooms,
            shareHistory: shareHistory));
    if (ids == null) return false;

    final sharing = historyRooms.isEmpty
        ? null
        : ShareHistory.sharingOf(client.getRoom(historyRooms.first)!);
    if (shareHistory.value && sharing != null) {
      unawaited(sharing
          .grantHistory(userId, historyRooms, spaceId: space.identifier)
          .catchError((Object e, StackTrace s) {
        Log.onError(e, s, content: "Sharing history from the invite dialog");
        return <String, String>{};
      }));
    }

    if (ids.length <= 1) {
      await component.inviteUserToRoom(userId: userId, roomId: ids.first);
      return true;
    }
    final names = {
      for (final e in index.infos.entries) e.key: e.value.name ?? e.key
    };
    final task = RoomBatchTask(
      verb: "Inviting $userId to",
      doneVerb: "Invited $userId to",
      failVerb: "invited to",
      spaceName: space.displayName,
      items: [for (final id in ids) RoomBatchItem(id, names[id] ?? id)],
      run: (item) =>
          component.inviteUserToRoom(userId: userId, roomId: item.roomId),
      retryAfter: MatrixSpaceHierarchy.retryAfter,
      reasonFor: (item, e) => MatrixSpaceHierarchy.failureReason(e),
    );
    backgroundTaskManager.addTask(task);
    unawaited(task.start());
    return true;
  }

  @override
  State<SpaceInviteDialog> createState() => _SpaceInviteDialogState();
}

class _SpaceInviteDialogState extends State<SpaceInviteDialog> {
  String get spaceInviteHistoryIncluded => Intl.message("History included",
      name: "spaceInviteHistoryIncluded",
      desc:
          "Dialog for inviting someone to a space and its rooms: status chip on a room whose earlier messages the invitee will be able to read");

  String get spaceInviteNewMessagesOnly => Intl.message("New messages only",
      name: "spaceInviteNewMessagesOnly",
      desc:
          "Dialog for inviting someone to a space and its rooms: status chip on a room where the invitee will only see new messages");

  String get spaceInviteNotEncrypted => Intl.message("Not encrypted",
      name: "spaceInviteNotEncrypted",
      desc:
          "Dialog for inviting someone to a space and its rooms: status chip on a room that isn't encrypted");

  String get spaceInviteCannotInvite => Intl.message("You can't invite here",
      name: "spaceInviteCannotInvite",
      desc:
          "Dialog for inviting someone to a space and its rooms: status chip on a room you lack permission to invite to");

  String get spaceInviteAlreadyMember => Intl.message("Already a member",
      name: "spaceInviteAlreadyMember",
      desc:
          "Dialog for inviting someone to a space and its rooms: status chip on a room the person is already in");

  String get spaceInviteAlsoInviteTo => Intl.message("ALSO INVITE TO",
      name: "spaceInviteAlsoInviteTo",
      desc:
          "Dialog for inviting someone to a space and its rooms: header above the list of rooms (all caps section header)");

  String get spaceInviteSelectAll => Intl.message("Select all",
      name: "spaceInviteSelectAll",
      desc:
          "Dialog for inviting someone to a space and its rooms: button that ticks every room");

  String get spaceInviteSelectNone => Intl.message("Select none",
      name: "spaceInviteSelectNone",
      desc:
          "Dialog for inviting someone to a space and its rooms: button that unticks every room");

  String spaceInviteHistoryExplainer(String userId) => Intl.message(
      "Rooms marked History included send $userId the keys to their earlier messages. In New messages only rooms, history isn't shared with new members.",
      args: [userId],
      name: "spaceInviteHistoryExplainer",
      desc:
          "Dialog for inviting someone to a space and its rooms: explanation under the room list; userId is the invitee's Matrix ID");

  String spaceInviteFirstContactHistory(String userId) => Intl.message(
      "You haven't talked with $userId before. Check it's the right person: they'll be able to read the history of the rooms marked History included.",
      args: [userId],
      name: "spaceInviteFirstContactHistory",
      desc:
          "Dialog for inviting someone to a space and its rooms: warning when inviting someone you've never talked with; userId is their Matrix ID");

  String spaceInviteFirstContact(String userId) => Intl.message(
      "You haven't talked with $userId before. Check it's the right person.",
      args: [userId],
      name: "spaceInviteFirstContact",
      desc:
          "Dialog for inviting someone to a space and its rooms: warning when inviting someone you've never talked with; userId is their Matrix ID");

  SpaceTree get tree => widget.tree;

  late final bool firstContact =
      SpaceInviteDialog.isFirstContact(widget.space.client, widget.userId);

  int get selectedRooms => tree.selected
      .where((id) => widget.statuses[id] != InviteHistory.space)
      .length;
  int get selectedSpaces => tree.selected
      .where((id) => widget.statuses[id] == InviteHistory.space)
      .length;

  bool get anyIncluded =>
      widget.statuses.values.contains(InviteHistory.included);

  Widget chip(BuildContext context, String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: color.withAlpha(36), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(text,
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget? statusFor(BuildContext context, SpaceTreeNode n) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return switch (widget.statuses[n.roomId]) {
      InviteHistory.included => chip(context, spaceInviteHistoryIncluded,
          Colors.green.shade500, Icons.history),
      InviteHistory.newMessagesOnly => chip(context, spaceInviteNewMessagesOnly,
          Colors.amber.shade600, Icons.schedule),
      InviteHistory.notEncrypted =>
        chip(context, spaceInviteNotEncrypted, dim, Icons.lock_open),
      InviteHistory.cannotInvite =>
        chip(context, spaceInviteCannotInvite, dim, Icons.block),
      InviteHistory.alreadyMember =>
        chip(context, spaceInviteAlreadyMember, dim, Icons.check),
      InviteHistory.space || null => null,
    };
  }

  Future<void> setAll(bool value) async {
    if (value) {
      await tree.selectAll();
    } else {
      tree.selectNone();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = scheme.onSurfaceVariant;
    final client = widget.space.client;
    final rows = tree.visibleRows().length;
    final maxTree = MediaQuery.of(context).size.height * 0.45;
    final treeHeight = (rows * SpaceTreeView.rowHeight + 8)
        .clamp(120.0, maxTree < 160 ? 160.0 : maxTree);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiniProfileView(client: client, userId: widget.userId),
            if (tree.loadedCount > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: tiamat.Text.labelLow(spaceInviteAlsoInviteTo)),
                TextButton(
                    key: const ValueKey("space-invite-select-all"),
                    onPressed: () => setAll(true),
                    child: Text(spaceInviteSelectAll)),
                TextButton(
                    key: const ValueKey("space-invite-select-none"),
                    onPressed: () => setAll(false),
                    child: Text(spaceInviteSelectNone)),
              ]),
              Container(
                height: treeHeight,
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10)),
                clipBehavior: Clip.antiAlias,
                child: SpaceTreeView(
                  tree: tree,
                  joinMode: false,
                  statusFor: (n) => statusFor(context, n),
                  statusWidth: 170,
                  avatarFor: (n) => client.getSpace(n.roomId)?.avatar,
                  colorFor: MatrixPeer.hashColor,
                  onChanged: () => setState(() {}),
                ),
              ),
              if (anyIncluded) ...[
                const SizedBox(height: 8),
                Text(spaceInviteHistoryExplainer(widget.userId),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: dim)),
              ],
            ],
            if (widget.historyRooms.isNotEmpty &&
                widget.shareHistory != null) ...[
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: widget.shareHistory!,
                builder: (context, value, _) => CheckboxListTile(
                  key: const ValueKey("space-invite-share-history"),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: value,
                  onChanged: (v) => widget.shareHistory!.value = v ?? false,
                  title: tiamat.Text.body(ShareHistoryStrings.alsoShareJoined(
                      widget.historyRooms.length)),
                ),
              ),
            ],
            if (firstContact) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey("space-invite-first-contact"),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(28),
                    border: Border.all(color: Colors.amber.withAlpha(90)),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.amber.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                          child: tiamat.Text.body(anyIncluded
                              ? spaceInviteFirstContactHistory(widget.userId)
                              : spaceInviteFirstContact(widget.userId))),
                    ]),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: tiamat.Button(
                key: const ValueKey("space-invite-confirm"),
                text: InvitePlan.buttonLabel(
                    rooms: selectedRooms, subspaces: selectedSpaces),
                onTap: () => Navigator.pop(context, InvitePlan.order(tree)),
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
