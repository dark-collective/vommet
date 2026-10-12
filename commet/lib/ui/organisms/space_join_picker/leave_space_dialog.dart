// Vommet: "Leave '<space>'" confirmation. Leaving a Matrix space doesn't
// leave its rooms, so it lists the rooms and subspaces you're in under it as
// a tick-box tree (subspaces open with the arrow): everything ticked, except
// what you're also in through another space ("also in <space>"). A
// half-ticked subspace stays joined; only its ticked rooms are left.

import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/client/matrix/matrix_space_hierarchy.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/space_join_picker/space_tree_view.dart';
import 'package:commet/utils/space_hierarchy/leave_plan.dart';
import 'package:commet/utils/space_hierarchy/room_batch_task.dart';
import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class LeaveSpaceDialog extends StatefulWidget {
  const LeaveSpaceDialog(this.space, this.index, {this.avatarFor, super.key});

  final Space space;
  final JoinedSpaceIndex index;

  /// A subspace's avatar (default: the client's copy of the space).
  final ImageProvider? Function(String spaceId)? avatarFor;

  /// The joined rooms and subspaces under [space].
  static JoinedSpaceIndex indexOf(Space space) {
    final index = JoinedSpaceIndex(space.identifier);
    void walk(Space s) {
      final ids = [
        ...s.rooms.map((r) => r.identifier),
        ...s.subspaces.map((c) => c.identifier),
      ];
      if (!index.addSpace(s.identifier, s.displayName, ids)) return;
      for (final r in s.rooms) {
        index.addRoom(r.identifier, r.displayName,
            roomType: r.getComponent<VoipRoomComponent>() != null
                ? "org.matrix.msc3417.call"
                : null);
      }
      for (final c in s.subspaces) {
        walk(c);
      }
    }

    walk(space);

    // What you're also in through your other spaces starts unticked.
    List<String> childrenOf(String id) {
      final s = space.client.getSpace(id);
      if (s == null) return const [];
      return [
        ...s.rooms.map((r) => r.identifier),
        ...s.subspaces.map((c) => c.identifier),
      ];
    }

    for (final other in space.client.spaces) {
      if (index.children.containsKey(other.identifier)) continue;
      index.markShared(other.identifier, other.displayName, childrenOf);
    }
    return index;
  }

  /// Asks, then leaves (in the background when rooms go too). Returns
  /// whether the user confirmed. [onConfirmed] runs before leaving (e.g. to
  /// close the space's settings).
  static Future<bool> leave(BuildContext context, Space space,
      {VoidCallback? onConfirmed}) async {
    final index = indexOf(space);
    final ids = await AdaptiveDialog.show<List<String>>(context,
        title: "Leave '${space.displayName}'",
        scrollable: false,
        builder: (context) => LeaveSpaceDialog(space, index));
    if (ids == null) return false;
    onConfirmed?.call();

    final client = space.client;
    if (ids.length <= 1) {
      await client.leaveSpace(space);
      return true;
    }

    final names = {
      for (final e in index.infos.entries) e.key: e.value.name ?? e.key
    };
    final task = RoomBatchTask(
      verb: "Leaving",
      doneVerb: "Left",
      failVerb: "left",
      spaceName: space.displayName,
      lastAlone: true,
      items: [for (final id in ids) RoomBatchItem(id, names[id] ?? id)],
      run: (item) async {
        final s = client.getSpace(item.roomId);
        if (s != null) return client.leaveSpace(s);
        final r = client.getRoom(item.roomId);
        if (r != null) return client.leaveRoom(r);
      },
      retryAfter: MatrixSpaceHierarchy.retryAfter,
      reasonFor: (item, e) => MatrixSpaceHierarchy.failureReason(e),
    );
    backgroundTaskManager.addTask(task);
    unawaited(task.start());
    return true;
  }

  @override
  State<LeaveSpaceDialog> createState() => _LeaveSpaceDialogState();
}

class _LeaveSpaceDialogState extends State<LeaveSpaceDialog> {
  SpaceTree? tree;

  JoinedSpaceIndex get index => widget.index;

  @override
  void initState() {
    super.initState();
    if (index.total > 0) load();
  }

  Future<void> load() async {
    final t = index.tree();
    await JoinedSpaceIndex.loadAll(t);
    await index.selectDefault(t);
    if (mounted) setState(() => tree = t);
  }

  void changed() {
    final t = tree;
    if (t != null) JoinedSpaceIndex.syncSpaces(t);
    setState(() {});
  }

  Future<void> setAll(bool value) async {
    final t = tree;
    if (t == null) return;
    if (value) {
      await t.selectAll();
    } else {
      t.selectNone();
    }
    if (mounted) changed();
  }

  static String _count(int n, String one, String many) =>
      n == 1 ? "1 $one" : "$n $many";

  String get buttonLabel {
    final t = tree;
    if (t == null) return "Leave Space";
    final (rooms, spaces) = index.selectedCounts(t);
    final parts = [
      if (spaces > 0) _count(spaces, "subspace", "subspaces"),
      if (rooms > 0) _count(rooms, "room", "rooms"),
    ];
    if (parts.isEmpty) return "Leave Space";
    if (parts.length == 1) return "Leave space and ${parts.first}";
    return "Leave space, ${parts.join(" and ")}";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = tree;
    final hasRooms = index.total > 0;

    // Fits the open rows, between a few rows and a scrolling box.
    final rows = t == null ? 0 : t.visibleRows().length;
    final height = (rows * SpaceTreeView.rowHeight + 8)
        .clamp(SpaceTreeView.rowHeight * 2, SpaceTreeView.rowHeight * 8 + 8)
        .toDouble();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: tiamat.Text.body(hasRooms
                  ? "Also leave the rooms and subspaces you're in here? Unticked ones stay joined."
                  : "Are you sure you want to leave ${widget.space.displayName}?"),
            ),
            if (hasRooms && t == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            if (t != null) ...[
              Row(children: [
                TextButton(
                    onPressed: () => setAll(true),
                    child: const Text("Select all")),
                TextButton(
                    onPressed: () => setAll(false),
                    child: const Text("Select none")),
              ]),
              Container(
                height: height,
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10)),
                clipBehavior: Clip.antiAlias,
                child: SpaceTreeView(
                  tree: t,
                  joinMode: false,
                  avatarFor: (n) => widget.avatarFor != null
                      ? widget.avatarFor!(n.roomId)
                      : widget.space.client.getSpace(n.roomId)?.avatar,
                  colorFor: MatrixPeer.hashColor,
                  noteFor: (n) {
                    final other = index.alsoIn[n.roomId];
                    return other == null ? null : "also in $other";
                  },
                  onChanged: changed,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: tiamat.Button(
                key: const ValueKey("leave-space-confirm"),
                type: tiamat.ButtonType.danger,
                text: buttonLabel,
                onTap: hasRooms && t == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        t != null
                            ? index.leaveOrder(all: false, tree: t)
                            : index.leaveOrder(all: false)),
              ),
            ),
            const SizedBox(height: 5),
            tiamat.Button.secondary(
              text: "Cancel",
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
