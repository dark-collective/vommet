import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/manage_space_rooms/space_rooms_edit.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: "Manage rooms" for a space (experiment
/// `experiment_manage_space_rooms`), like Discord's "Edit channels": the
/// space as a tree in the owner's order, a drag handle on every row (no
/// long-press guessing), and a ⋯ menu to move a room up or down, into
/// another subspace, or out of the space. Nothing is saved until Save;
/// removed rooms stay crossed out with Undo until then. Removing a room
/// from a space never deletes the room.
class ManageSpaceRoomsPage extends StatefulWidget {
  const ManageSpaceRoomsPage(this.space, {super.key});

  final Space space;

  @override
  State<ManageSpaceRoomsPage> createState() => _ManageSpaceRoomsPageState();
}

class _ManageSpaceRoomsPageState extends State<ManageSpaceRoomsPage> {
  static const maxDepth = 5;

  final Map<String, Space> spaces = {};
  final Map<String, SpaceChild> children = {};
  final Map<String, bool> collapsed = {};
  late SpaceRoomsEdit edit;
  bool saving = false;
  double? progress;

  /// The space changed elsewhere while there were unsaved edits.
  bool changedElsewhere = false;
  final List<StreamSubscription> subs = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  /// Follow changes made elsewhere (another admin, the sidebar menu): reload
  /// when nothing is pending, else say the page may be out of date.
  void listen() {
    for (final sub in subs) {
      sub.cancel();
    }
    subs.clear();
    for (final space in spaces.values) {
      subs.add(space.onUpdate.listen((_) {
        if (!mounted || saving) return;
        setState(() {
          if (edit.hasChanges) {
            changedElsewhere = true;
          } else {
            load();
          }
        });
      }));
    }
  }

  void load() {
    spaces.clear();
    children.clear();
    final original = <String, List<String>>{};
    void visit(Space space, int depth) {
      if (spaces.containsKey(space.identifier)) return; // a cycle
      spaces[space.identifier] = space;
      final ids = <String>[];
      for (final child in space.children) {
        children[child.id] = child;
        ids.add(child.id);
        if (child case SpaceChildSpace s when depth < maxDepth) {
          visit(s.child, depth + 1);
        }
      }
      original[space.identifier] = ids;
    }

    visit(widget.space, 0);
    edit = SpaceRoomsEdit(original);
    changedElsewhere = false;
    listen();
  }

  bool canEdit(String spaceId) =>
      spaces[spaceId]?.permissions.canEditChildren == true;

  Future<bool> confirmLeave() async {
    if (!edit.hasChanges || saving) return !saving;
    return await AdaptiveDialog.confirmation(context,
            title: "Discard changes?",
            prompt: "Your changes to this space's rooms haven't been saved.",
            confirmationText: "Discard",
            cancelText: "Keep editing",
            dangerous: true) ==
        true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !edit.hasChanges && !saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmLeave() && context.mounted) {
          edit = SpaceRoomsEdit({});
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: scheme.surfaceContainerLow,
          title: const Text("Manage rooms"),
          actions: [
            if (canEdit(widget.space.identifier))
              IconButton(
                tooltip: "Create or add a room",
                icon: const Icon(Icons.add),
                onPressed: saving || edit.hasChanges
                    ? null
                    : () => SpaceMenu.addRoom(context, widget.space),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: tiamat.Text.labelLow(
                  "Drag the handle to reorder within a level. Use ⋯ to move a "
                  "room into another subspace or remove it from the space (the "
                  "room itself isn't deleted). Nothing changes until you save. "
                  "Rooms you haven't joined aren't listed and keep their places."),
            ),
            if (changedElsewhere)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: tiamat.Text.label(
                    "This space was changed elsewhere since you opened it. "
                    "Discard to see the latest, then make your changes again."),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: level(widget.space.identifier, 0, {}),
              ),
            ),
            if (edit.hasChanges || saving) bottomBar(scheme),
          ],
        ),
      ),
    );
  }

  /// [ancestors]: the spaces above [parent], so a space that (indirectly)
  /// contains itself, which Matrix allows, is shown once, not forever.
  Widget level(String parent, int depth, Set<String> ancestors) {
    final inside = {...ancestors, parent};
    final ids = edit.childrenOf(parent);
    final editable = canEdit(parent) && !saving;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: ids.length,
      onReorder: (oldIndex, newIndex) =>
          setState(() => edit.reorder(parent, oldIndex, newIndex)),
      itemBuilder: (context, index) {
        final id = ids[index];
        return Column(
          key: ValueKey("$parent/$id"),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(parent, id, index, depth, editable),
            if (children[id] is SpaceChildSpace &&
                spaces.containsKey(id) &&
                !inside.contains(id) &&
                depth < maxDepth &&
                collapsed[id] != true &&
                !edit.isRemoved(parent, id))
              level(id, depth + 1, inside),
          ],
        );
      },
    );
  }

  Widget row(String parent, String id, int index, int depth, bool editable) {
    final scheme = Theme.of(context).colorScheme;
    final child = children[id];
    final removed = edit.isRemoved(parent, id);
    final moved = edit.isMovedIn(parent, id);
    final isSpace = child is SpaceChildSpace;

    final String name;
    Widget leading;
    switch (child) {
      case SpaceChildRoom r:
        name = r.child.displayName;
        leading = tiamat.Avatar(
            radius: 13,
            image: r.child.avatar,
            placeholderText: r.child.displayName,
            placeholderColor: r.child.defaultColor);
      case SpaceChildSpace s:
        name = s.child.displayName;
        leading = IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
              collapsed[id] == true
                  ? Icons.keyboard_arrow_right
                  : Icons.keyboard_arrow_down,
              size: 18,
              color: scheme.secondary),
          onPressed: () =>
              setState(() => collapsed[id] = !(collapsed[id] ?? false)),
        );
      default:
        name = id;
        leading = const SizedBox(width: 26);
    }

    final title = isSpace
        ? Row(children: [
            Flexible(
              child: Text(name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800,
                      color: scheme.secondary,
                      decoration: removed ? TextDecoration.lineThrough : null)),
            ),
            const SizedBox(width: 8),
            tiamat.Text.labelLow("subspace"),
          ])
        : Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 15,
                color: removed
                    ? scheme.secondary.withValues(alpha: 0.5)
                    : scheme.onSurface,
                decoration: removed ? TextDecoration.lineThrough : null));

    return Container(
      height: isSpace ? 42 : 48,
      margin: EdgeInsets.only(left: 8.0 + depth * 18, right: 8, top: 2),
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: isSpace ? null : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: moved
            ? Border.all(color: scheme.primary, width: 1.5)
            : Border.all(color: Colors.transparent, width: 1.5),
      ),
      child: Row(children: [
        Opacity(opacity: removed ? 0.4 : 1, child: leading),
        const SizedBox(width: 10),
        Expanded(child: title),
        if (removed)
          TextButton(
            onPressed: saving
                ? null
                : () => setState(() => edit.undoRemove(parent, id)),
            child: const Text("Undo"),
          )
        else if (editable) ...[
          IconButton(
            tooltip: "More",
            icon: Icon(Icons.more_horiz, color: scheme.secondary),
            onPressed: () => rowMenu(parent, id, name),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.drag_indicator, color: scheme.secondary),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> rowMenu(String parent, String id, String name) async {
    final parentName = spaces[parent]?.displayName ?? "space";
    final targets = moveTargets(parent, id);
    final choice = await AdaptiveDialog.pickOne<String>(context,
        title: name,
        items: [
          "up",
          "down",
          if (targets.isNotEmpty) "move",
          "remove",
        ],
        itemBuilder: (context, item, callback) => tiamat.TextButton(
              switch (item) {
                "up" => "Move up",
                "down" => "Move down",
                "move" => "Move to another subspace…",
                _ => "Remove from $parentName",
              },
              icon: switch (item) {
                "up" => Icons.arrow_upward,
                "down" => Icons.arrow_downward,
                "move" => Icons.drive_file_move_outline,
                _ => Icons.remove_circle_outline,
              },
              onTap: callback,
            ));
    if (!mounted || choice == null) return;
    switch (choice) {
      case "up":
        setState(() => edit.moveUp(parent, id));
      case "down":
        setState(() => edit.moveDown(parent, id));
      case "remove":
        setState(() => edit.remove(parent, id));
      case "move":
        final to = await AdaptiveDialog.pickOne<String>(context,
            title: "Move $name to",
            items: targets,
            itemBuilder: (context, item, callback) => tiamat.TextButton(
                  item == widget.space.identifier
                      ? "${spaces[item]!.displayName} (top level)"
                      : spaces[item]!.displayName,
                  icon: Icons.folder_outlined,
                  onTap: callback,
                ));
        if (mounted && to != null) {
          setState(() => edit.moveTo(id, parent, to));
        }
    }
  }

  /// Spaces [id] can move into from [parent]: ones you can edit, not its
  /// current parent, and for a subspace, not itself or anything inside it.
  List<String> moveTargets(String parent, String id) {
    final inside = <String>{};
    void collect(String s) {
      if (!inside.add(s)) return;
      for (final c in edit.childrenOf(s)) {
        if (spaces.containsKey(c)) collect(c);
      }
    }

    if (spaces.containsKey(id)) collect(id);
    final reachable = edit.reachable(widget.space.identifier);
    return [
      for (final s in spaces.keys)
        if (s != parent &&
            !inside.contains(s) &&
            reachable.contains(s) &&
            canEdit(s))
          s
    ];
  }

  Widget bottomBar(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: saving
                ? LinearProgressIndicator(value: progress)
                : tiamat.Text.labelLow(edit.summary()),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: saving ? null : () => setState(load),
            child: const Text("Discard"),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: const Text("Save"),
          ),
        ]),
      ),
    );
  }

  Future<void> save() async {
    final ops = edit.plan();
    setState(() {
      saving = true;
      progress = 0;
    });
    var done = 0;
    try {
      for (final op in ops) {
        final parent = spaces[op.parent]!;
        switch (op) {
          case AddChildOp(child: final c, from: final from):
            final source = from == null ? null : spaces[from];
            switch (children[c]) {
              case SpaceChildRoom r:
                await parent.setSpaceChildRoom(r.child, copyFrom: source);
              case SpaceChildSpace s:
                await parent.setSpaceChildSpace(s.child, copyFrom: source);
              default:
            }
          case OrderChildrenOp(children: final ids):
            await parent.setChildrenOrder([
              for (final c in ids)
                if (children[c] != null) children[c]!
            ]);
          case RemoveChildOp(child: final c):
            if (children[c] != null) await parent.removeChild(children[c]!);
        }
        done++;
        if (mounted) setState(() => progress = done / ops.length);
      }
      edit.commit();
    } catch (e, s) {
      Log.onError(e, s, content: "Saving space room changes failed");
      if (mounted) {
        await AdaptiveDialog.show(context,
            title: "Couldn't save everything",
            builder: (_) => tiamat.Text.body(
                "Saved $done of ${ops.length} changes, then: $e\n\n"
                "Rooms are always added to their new place before they're "
                "taken out of the old one, so nothing was lost. Reopen this "
                "page to see the space as it is now."));
      }
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
          progress = null;
        });
      }
    }
  }
}
