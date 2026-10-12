// Vommet: "Leave '<space>'" confirmation. Leaving a Matrix space doesn't
// leave its rooms, so it offers that too: unticked by default, with
// "Choose…" opening a tree of the rooms and subspaces you're in.

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
  /// "Also leave its rooms": off unless the user ticks it.
  bool alsoLeave = false;
  SpaceTree? tree;

  JoinedSpaceIndex get index => widget.index;

  String get summary {
    final rooms = index.roomCount;
    final spaces = index.subspaceCount;
    final r = rooms == 1 ? "1 room" : "$rooms rooms";
    final s = spaces == 1 ? "1 subspace" : "$spaces subspaces";
    if (spaces == 0) return "Also leave its $r you're in";
    if (rooms == 0) return "Also leave its $s you're in";
    return "Also leave its $r and $s you're in";
  }

  /// Ticked, unticked, or (choosing, some ticked) a dash.
  bool? get boxState {
    final t = tree;
    if (t == null) return alsoLeave;
    final count = t.selected.length;
    if (count == 0) return false;
    if (count >= t.loadedCount) return true;
    return null;
  }

  Future<void> choose() async {
    final t = index.tree();
    await JoinedSpaceIndex.loadAll(t);
    if (alsoLeave) await t.selectAll();
    if (mounted) setState(() => tree = t);
  }

  Future<void> setAll(bool value) async {
    final t = tree;
    if (t == null) {
      setState(() => alsoLeave = value);
      return;
    }
    if (value) {
      await t.selectAll();
    } else {
      t.selectNone();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = tree;
    final state = boxState;
    final line = t != null && state == null
        ? "Also leave ${t.selected.length} of its ${t.loadedCount} rooms and spaces"
        : summary;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: tiamat.Text.body(
                  "Are you sure you want to leave ${widget.space.displayName}?"),
            ),
            if (index.total > 0)
              Row(children: [
                Checkbox(
                  key: const ValueKey("leave-space-also-rooms"),
                  tristate: true,
                  value: state,
                  onChanged: (_) => setAll(state != true),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setAll(state != true),
                    child: tiamat.Text.body(line),
                  ),
                ),
                if (t == null)
                  TextButton(onPressed: choose, child: const Text("Choose…")),
              ]),
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
                height: 240,
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
                  onChanged: () => setState(() {}),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: tiamat.Button(
                type: tiamat.ButtonType.danger,
                text: "Leave Space",
                onTap: () => Navigator.pop(
                    context,
                    t != null
                        ? index.leaveOrder(all: false, tree: t)
                        : index.leaveOrder(all: alsoLeave)),
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
