import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/personal_space_order.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A personal sibling editor, one parent at a time. No shared editing operations
/// are reachable here. Persistence is the parent's self account-data interface.
class ArrangeSpacePage extends StatefulWidget {
  const ArrangeSpacePage(this.space, {super.key});
  final Space space;

  @override
  State<ArrangeSpacePage> createState() => _ArrangeSpacePageState();
}

class _ArrangeSpacePageState extends State<ArrangeSpacePage> {
  static const equality = ListEquality<String>();
  final List<StreamSubscription> subscriptions = [];
  final scroll = ScrollController();
  PersonalSpaceOrdering? get store => PersonalSpaceOrdering.of(widget.space);
  List<String>? saved;
  List<String> defaults = [];
  List<String> original = [];
  List<String> edited = [];
  bool reset = false;
  bool dragging = false;
  bool saving = false;
  bool changedElsewhere = false;
  bool loaded = false;
  String? loadError;
  String? saveError;

  bool get dirty => reset ? saved != null : !equality.equals(original, edited);
  List<SpaceChild> get children => widget.space.allChildren;

  @override
  void initState() {
    super.initState();
    reload();
    subscriptions.addAll([
      widget.space.onUpdate.listen((_) => updated()),
      widget.space.onChildRoomsUpdated.listen((_) => updated()),
      widget.space.onChildRoomPreviewsUpdated.listen((_) => updated()),
      widget.space.onChildSpaceAdded.listen((_) => updated()),
      widget.space.onChildSpaceRemoved.listen((_) => updated()),
    ]);
    load();
  }

  void reload() {
    saved = store?.personalChildOrder?.toList();
    defaults = children.map((c) => c.id).toList();
    original = PersonalChildOrder.project(defaults, saved, (id) => id);
    edited = original.toList();
    reset = false;
    changedElsewhere = false;
    saveError = null;
  }

  Future<void> load() async {
    try {
      if (!widget.space.fullyLoaded) await widget.space.loadExtra();
      if (mounted)
        setState(() {
          loaded = true;
          loadError = null;
          updated();
        });
    } catch (_) {
      if (mounted)
        setState(() {
          loaded = true;
          loadError = arrangeLoadError;
        });
    }
  }

  void updated() {
    if (!mounted || saving) return;
    setState(() {
      final now = children.map((c) => c.id).toList();
      final changed = !equality.equals(defaults, now) ||
          !equality.equals(saved, store?.personalChildOrder);
      if (!dirty && !dragging) {
        reload();
      } else if (changed) {
        if (!changedElsewhere) showHeader();
        changedElsewhere = true;
      }
    });
  }

  void showHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<bool> discard() async {
    if (saving) return false;
    if (!dirty) return true;
    return await AdaptiveDialog.confirmation(context,
            title: arrangeDiscardTitle,
            prompt: arrangeDiscardPrompt,
            confirmationText: arrangeDiscard,
            cancelText: arrangeKeepEditing) ==
        true;
  }

  void move(String id, int direction) {
    final index = edited.indexOf(id);
    if (index >= 0) reorder(index, index + direction);
  }

  void reorder(int from, int to) {
    if (saving ||
        changedElsewhere ||
        from < 0 ||
        from >= edited.length ||
        to < 0 ||
        to > edited.length) return;
    if (to > from) to--;
    if (from == to) return;
    setState(() {
      // Dragging a reset preview starts a new personal arrangement.
      reset = false;
      edited.insert(to, edited.removeAt(from));
      saveError = null;
    });
  }

  Future<void> save() async {
    if (!dirty || saving || dragging || changedElsewhere || store == null)
      return;
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await store!.savePersonalChildOrder(
          reset ? null : PersonalChildOrder.preserveMissing(saved, edited));
      if (mounted) {
        setState(reload);
        showHeader();
      }
    } catch (_) {
      if (mounted) setState(() => saveError = arrangeSaveError);
      showHeader();
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> openSubspace(Space space) async {
    if (space == widget.space || !await discard() || !mounted) return;
    setState(reload);
    await NavigationUtils.navigateTo(context, ArrangeSpacePage(space));
    if (mounted) updated();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final redaction = RedactionScope.of(context);
    final byId = {for (final child in children) child.id: child};
    final accountId =
        store?.personalOrderAccountId ?? widget.space.client.identifier;
    final editable = !saving && !changedElsewhere && store != null;
    return PopScope(
      canPop: !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await discard() && context.mounted) {
          setState(reload);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        appBar: AppBar(
            backgroundColor: scheme.surfaceContainerLow,
            title: Text(arrangeForMeLabel)),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: ReorderableListView.builder(
            scrollController: scroll,
            header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            tiamat.Text.labelEmphasised(redaction.roomName(
                                widget.space.displayName,
                                widget.space.identifier)),
                            const SizedBox(height: 12),
                            Text(arrangeHelp),
                            const SizedBox(height: 8),
                            tiamat.Text.labelLow(
                                redaction.name(accountId, accountId)),
                            const SizedBox(height: 12),
                            Semantics(
                                liveRegion: true,
                                child: Text(reset
                                    ? arrangeDefaultPreview
                                    : dirty
                                        ? arrangeUnsaved
                                        : saved == null
                                            ? arrangeDefault
                                            : arrangeSaved)),
                          ])),
                  if (!loaded) const LinearProgressIndicator(),
                  if (loadError != null)
                    message(loadError!, arrangeRetry, load),
                  if (changedElsewhere)
                    message(arrangeRemoteChange, arrangeReload, () async {
                      if (await discard() && mounted) setState(reload);
                    }),
                  if (saveError != null)
                    message(saveError!, arrangeRetry, save),
                ]),
            padding: const EdgeInsets.only(bottom: 16),
            buildDefaultDragHandles: false,
            footer: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  if (edited.isEmpty)
                    Text(loaded ? arrangeEmpty : arrangeLoading),
                  Text(arrangeNewChildren),
                ])),
            itemCount: edited.length,
            onReorderStart: (_) => dragging = true,
            onReorderEnd: (_) => dragging = false,
            onReorder: editable ? reorder : (_, __) {},
            itemBuilder: (context, index) {
              final id = edited[index];
              final child = byId[id];
              final subspace = child is SpaceChildSpace ? child.child : null;
              final rawName = switch (child) {
                SpaceChildRoom c => c.child.displayName,
                SpaceChildSpace c => c.child.displayName,
                SpaceChildUnjoined c => c.child?.displayName ?? id,
                _ => id,
              };
              final name = redaction.roomName(rawName, id);
              final voice = child is SpaceChildRoom &&
                  child.child.getComponent<VoipRoomComponent>() != null;
              return Semantics(
                key: ValueKey(id),
                label: arrangePosition(name, index + 1, edited.length),
                customSemanticsActions: {
                  if (editable && index > 0)
                    CustomSemanticsAction(label: arrangeMoveUp): () =>
                        move(id, -1),
                  if (editable && index < edited.length - 1)
                    CustomSemanticsAction(label: arrangeMoveDown): () =>
                        move(id, 2),
                },
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    minVerticalPadding: 12,
                    leading: subspace != null
                        ? tiamat.Avatar.small(
                            placeholderText: name,
                            placeholderColor: subspace.color)
                        : Icon(voice ? Icons.volume_up_outlined : Icons.tag),
                    title: Text(name),
                    subtitle: subspace != null
                        ? Text(arrangeSubspace)
                        : child is SpaceChildUnjoined
                            ? Text(child.child == null
                                ? arrangeMissingDetails
                                : arrangeNotJoined)
                            : null,
                    onTap: editable &&
                            subspace != null &&
                            subspace != widget.space &&
                            PersonalSpaceOrdering.of(subspace) != null
                        ? () => openSubspace(subspace)
                        : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      PopupMenuButton<int>(
                        tooltip: arrangeMoveTooltip(name),
                        enabled: editable,
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (direction) => move(id, direction),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: -1,
                              enabled: index > 0,
                              child: Text(arrangeMoveUp)),
                          PopupMenuItem(
                              value: 2,
                              enabled: index < edited.length - 1,
                              child: Text(arrangeMoveDown)),
                        ],
                      ),
                      ReorderableDragStartListener(
                          index: index,
                          enabled: editable,
                          child: Semantics(
                              label: arrangeDragTooltip(name),
                              child: const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Icon(Icons.drag_indicator)))),
                    ]),
                  ),
                ),
              );
            },
          )),
          const Divider(height: 1),
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton.icon(
                        onPressed: editable && saved != null && !reset
                            ? () => setState(() {
                                  edited = defaults.toList();
                                  reset = true;
                                  saveError = null;
                                })
                            : null,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(arrangeReset)),
                    if (reset)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(arrangeResetHelp)),
                    Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          TextButton(
                              onPressed: dirty && !saving
                                  ? () => setState(reload)
                                  : null,
                              child: Text(arrangeCancel)),
                          FilledButton(
                              onPressed: editable && dirty ? save : null,
                              child: saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Text(
                                      reset ? arrangeSaveReset : arrangeSave)),
                        ]),
                  ])),
        ]),
      ),
    );
  }

  Widget message(String text, String action, VoidCallback callback) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(liveRegion: true, child: Text(text)),
        TextButton(onPressed: saving ? null : callback, child: Text(action)),
      ]));
}

String get arrangeForMeLabel => Intl.message("Arrange for me",
    name: "arrangeForMeLabel", desc: "Personal space arrangement");
String get changeSpaceDefaultLabel =>
    Intl.message("Change default for everyone",
        name: "changeSpaceDefaultLabel", desc: "Personal space arrangement");
String get arrangeLoadError => Intl.message(
    "Some room details could not be loaded. Your saved positions are kept.",
    name: "arrangeLoadError",
    desc: "Personal space arrangement");
String get arrangeDiscardTitle => Intl.message("Discard personal arrangement?",
    name: "arrangeDiscardTitle", desc: "Personal space arrangement");
String get arrangeDiscardPrompt =>
    Intl.message("Your unsaved changes will be lost.",
        name: "arrangeDiscardPrompt", desc: "Personal space arrangement");
String get arrangeDiscard => Intl.message("Discard",
    name: "arrangeDiscard", desc: "Personal space arrangement");
String get arrangeKeepEditing => Intl.message("Keep editing",
    name: "arrangeKeepEditing", desc: "Personal space arrangement");
String get arrangeSaveError => Intl.message(
    "Could not save your personal order. Your changes are still here. Try again.",
    name: "arrangeSaveError",
    desc: "Personal space arrangement");
String get arrangeHelp => Intl.message(
    "Only your view changes. Syncs with this account on your devices.",
    name: "arrangeHelp",
    desc: "Personal space arrangement");
String get arrangeDefaultPreview => Intl.message("Space default · preview",
    name: "arrangeDefaultPreview", desc: "Personal space arrangement");
String get arrangeUnsaved => Intl.message("Personal order · unsaved",
    name: "arrangeUnsaved", desc: "Personal space arrangement");
String get arrangeDefault => Intl.message("Space default",
    name: "arrangeDefault", desc: "Personal space arrangement");
String get arrangeSaved => Intl.message("Personal order saved",
    name: "arrangeSaved", desc: "Personal space arrangement");
String get arrangeRetry => Intl.message("Retry",
    name: "arrangeRetry", desc: "Personal space arrangement");
String get arrangeReload => Intl.message("Reload",
    name: "arrangeReload", desc: "Personal space arrangement");
String get arrangeRemoteChange => Intl.message(
    "The space or your personal order changed elsewhere. Reload before saving.",
    name: "arrangeRemoteChange",
    desc: "Personal space arrangement");
String get arrangeEmpty => Intl.message("No rooms or subspaces yet.",
    name: "arrangeEmpty", desc: "Personal space arrangement");
String get arrangeLoading => Intl.message("Loading rooms…",
    name: "arrangeLoading", desc: "Personal space arrangement");
String get arrangeNewChildren => Intl.message(
    "New rooms and subspaces appear after your arranged items, in the space’s default order.",
    name: "arrangeNewChildren",
    desc: "Personal space arrangement");
String get arrangeMoveUp => Intl.message("Move up",
    name: "arrangeMoveUp", desc: "Personal space arrangement");
String get arrangeMoveDown => Intl.message("Move down",
    name: "arrangeMoveDown", desc: "Personal space arrangement");
String get arrangeSubspace =>
    Intl.message("Subspace · open to arrange its rooms",
        name: "arrangeSubspace", desc: "Personal space arrangement");
String get arrangeMissingDetails => Intl.message("Details not loaded",
    name: "arrangeMissingDetails", desc: "Personal space arrangement");
String get arrangeNotJoined => Intl.message("Not joined",
    name: "arrangeNotJoined", desc: "Personal space arrangement");
String get arrangeReset => Intl.message("Reset to space default",
    name: "arrangeReset", desc: "Personal space arrangement");
String get arrangeResetHelp =>
    Intl.message("Save to remove your personal order for this space.",
        name: "arrangeResetHelp", desc: "Personal space arrangement");
String get arrangeCancel => Intl.message("Cancel",
    name: "arrangeCancel", desc: "Personal space arrangement");
String get arrangeSaveReset => Intl.message("Save reset",
    name: "arrangeSaveReset", desc: "Personal space arrangement");
String get arrangeSave => Intl.message("Save",
    name: "arrangeSave", desc: "Personal space arrangement");
String get arrangePersonalScope => Intl.message("Personal · this account",
    name: "arrangePersonalScope", desc: "Personal space arrangement");
String get arrangeSharedScope => Intl.message("Shared · edits the space",
    name: "arrangeSharedScope", desc: "Personal space arrangement");
String get arrangeCancelShared =>
    Intl.message("Cancel changing default for everyone",
        name: "arrangeCancelShared", desc: "Personal space arrangement");
String get arrangeEditingShared =>
    Intl.message("Changing the default for everyone · edits the space",
        name: "arrangeEditingShared", desc: "Personal space arrangement");
String arrangePosition(String name, int position, int total) =>
    Intl.message('$name, position $position of $total',
        name: 'arrangePosition',
        args: [name, position, total],
        desc: 'Accessible position of a room or subspace');
String arrangeMoveTooltip(String name) => Intl.message('Move $name up or down',
    name: 'arrangeMoveTooltip',
    args: [name],
    desc: 'Accessible reorder menu for a room or subspace');
String arrangeDragTooltip(String name) => Intl.message('Drag to reorder $name',
    name: 'arrangeDragTooltip',
    args: [name],
    desc: 'Drag handle for a room or subspace');
