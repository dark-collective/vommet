// Vommet: pick which of a space's rooms and subspaces to join, right after
// joining the space (or later, from "Browse rooms" in the space menu).
// Joins run in the background, a few at a time.

import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/client/matrix/matrix_space_hierarchy.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/space_join_picker/space_tree_view.dart';
import 'package:commet/utils/space_hierarchy/room_batch_task.dart';
import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show Intl, NumberFormat;
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceJoinPicker extends StatefulWidget {
  const SpaceJoinPicker({
    required this.client,
    required this.tree,
    required this.load,
    this.avatar,
    this.fallbackName,
    super.key,
  });

  final MatrixClient client;
  final SpaceTree tree;

  /// Loads the first entries; done before showing when offered after a
  /// join, while showing when browsing.
  final Future<void>? load;
  final ImageProvider? avatar;
  final String? fallbackName;

  static SpaceTree treeFor(MatrixClient client, String spaceId,
      {List<String> via = const []}) {
    final mx = client.getMatrixClient();
    return SpaceTree(
      spaceId: spaceId,
      via: via,
      fetch: MatrixSpaceHierarchy.fetcher(mx),
      isJoined: (id) => MatrixSpaceHierarchy.isJoined(mx, id),
    );
  }

  /// After joining space [spaceId]: offers the picker if the space has
  /// rooms you're not in yet. Waits a moment so the screen that joined can
  /// close first.
  static Future<void> offerAfterJoin(Client client, String spaceId,
      {List<String> via = const []}) async {
    if (client is! MatrixClient) return;
    try {
      final tree = treeFor(client, spaceId, via: via);
      await Future.wait([
        tree.loadRoot(),
        Future.delayed(const Duration(milliseconds: 400)),
      ]);
      if (!tree.root.children.any(tree.selectable) && !tree.canLoadMore) {
        return;
      }
      final context = navigator.currentContext;
      if (context == null || !context.mounted) return;
      await show(context, client, tree, load: null);
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't load the space's rooms");
    }
  }

  /// "Browse rooms" for a space you're in.
  static Future<void> browse(BuildContext context, Space space) async {
    final client = space.client;
    if (client is! MatrixClient) return;
    final tree = treeFor(client, space.identifier);
    await show(context, client, tree,
        load: tree.loadRoot(),
        avatar: space.avatar,
        fallbackName: space.displayName);
  }

  static Future<void> show(
      BuildContext context, MatrixClient client, SpaceTree tree,
      {required Future<void>? load,
      ImageProvider? avatar,
      String? fallbackName}) {
    final picker = SpaceJoinPicker(
        client: client,
        tree: tree,
        load: load,
        avatar: avatar,
        fallbackName: fallbackName);
    if (MediaQuery.of(context).mobile) {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        builder: (context) => FractionallySizedBox(
          heightFactor: 1,
          child: picker,
        ),
      );
    }
    return showDialog(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            width: 560,
            height: (size.height * 0.85).clamp(320.0, 720.0),
            child: picker,
          ),
        );
      },
    );
  }

  @override
  State<SpaceJoinPicker> createState() => _SpaceJoinPickerState();
}

class _SpaceJoinPickerState extends State<SpaceJoinPicker> {
  bool loading = false;
  Object? loadError;
  String filter = "";
  bool truncatedBySelectAll = false;

  SpaceTree get tree => widget.tree;

  @override
  void initState() {
    super.initState();
    final load = widget.load;
    if (load != null) {
      loading = true;
      load.then((_) {
        if (mounted) setState(() => loading = false);
      }, onError: (Object e, StackTrace s) {
        Log.onError(e, s, content: "Couldn't load the space's rooms");
        if (mounted) {
          setState(() {
            loading = false;
            loadError = e;
          });
        }
      });
    }
  }

  ImageProvider? avatarFor(Uri? url) => url == null
      ? null
      : MatrixMxcImage(url, widget.client.getMatrixClient(),
          doFullres: false, doThumbnail: true);

  String get spaceName {
    final n = tree.root.info?.name;
    if (n != null && n.trim().isNotEmpty) return n;
    return widget.fallbackName ?? tree.root.roomId;
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.of(context).mobile;
    final scheme = Theme.of(context).colorScheme;
    final count = tree.selected.length;

    final treeBox = Container(
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: tiamat.Text.labelLow(spaceJoinLoadFailed),
                ))
              : SpaceTreeView(
                  tree: tree,
                  filter: filter,
                  avatarFor: (n) => avatarFor(n.info?.avatarUrl),
                  colorFor: MatrixPeer.hashColor,
                  onChanged: () => setState(() {
                    truncatedBySelectAll = false;
                  }),
                ),
    );

    final joinLabel = spaceJoinButton(count);
    final buttons = [
      tiamat.Button.secondary(
          text: spaceJoinJustTheSpace,
          onTap: () => Navigator.of(context).pop()),
      tiamat.Button(
          text: joinLabel, onTap: count == 0 ? null : () => startJoining()),
    ];

    return Padding(
      padding:
          phone ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: phone
                ? const EdgeInsets.symmetric(horizontal: 16)
                : EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildHeader(context, phone),
                const SizedBox(height: 14),
                buildToolbar(context, phone),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: phone
                  ? const EdgeInsets.symmetric(horizontal: 8)
                  : EdgeInsets.zero,
              child: treeBox,
            ),
          ),
          if (tree.truncatedFrom != null)
            Padding(
              padding:
                  EdgeInsets.fromLTRB(phone ? 16 : 0, 8, phone ? 16 : 0, 0),
              child: buildWarning(context),
            ),
          const SizedBox(height: 12),
          if (phone)
            Container(
              color: scheme.surfaceContainerHigh,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Row(children: [
                Expanded(child: Center(child: buttons[0])),
                const SizedBox(width: 8),
                Expanded(child: Center(child: buttons[1])),
              ]),
            )
          else
            Row(children: [
              Expanded(
                child: tiamat.Text.labelLow(spaceJoinSuggestedHint),
              ),
              const SizedBox(width: 10),
              buttons[0],
              const SizedBox(width: 8),
              buttons[1],
            ]),
        ],
      ),
    );
  }

  Widget buildHeader(BuildContext context, bool phone) {
    final info = tree.root.info;
    final parts = <String>[
      if (info != null)
        spaceJoinMemberCount(
            NumberFormat.decimalPattern().format(info.members)),
      if (!loading) ...[
        spaceJoinSubspaceCount(tree.loadedSpaces),
        spaceJoinRoomCount(tree.loadedRooms),
      ],
    ];
    return Row(children: [
      tiamat.Avatar(
        radius: phone ? 22 : 26,
        image: avatarFor(info?.avatarUrl) ?? widget.avatar,
        placeholderText: spaceName,
        placeholderColor: MatrixPeer.hashColor(tree.root.roomId),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spaceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (parts.isNotEmpty) tiamat.Text.labelLow(parts.join(" · ")),
          ],
        ),
      ),
    ]);
  }

  Widget buildToolbar(BuildContext context, bool phone) {
    final count = tree.selected.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (value) => setState(() => filter = value),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: spaceJoinFilterHint,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          pill(spaceJoinSelectAll, () async {
            await tree.selectAll();
            if (mounted) {
              setState(() => truncatedBySelectAll = tree.truncatedFrom != null);
            }
          }),
          const SizedBox(width: 6),
          pill(spaceJoinSelectNone, () => setState(tree.selectNone)),
          if (!phone) ...[
            const SizedBox(width: 6),
            pill(spaceJoinSuggestedOnly, () => setState(tree.selectSuggested)),
          ],
          const Spacer(),
          Text(spaceJoinSelectedCount(count),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ],
    );
  }

  Widget pill(String text, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: loading ? null : onTap,
      style: TextButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      child: Text(text),
    );
  }

  Widget buildWarning(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = NumberFormat.decimalPattern().format(tree.truncatedFrom ?? 0);
    final text = truncatedBySelectAll
        ? spaceJoinSelectAllCapped(n, SpaceTree.actionCap)
        : spaceJoinTickCapped(n, SpaceTree.actionCap);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(child: tiamat.Text.label(text)),
      ]),
    );
  }

  void startJoining() {
    final mx = widget.client.getMatrixClient();
    final items = tree.selectedInOrder
        .map((n) => RoomBatchItem(n.roomId, n.name,
            via: tree.viaFor(n), joinRule: n.info?.joinRule))
        .toList();
    Navigator.of(context).pop();
    if (items.isEmpty) return;
    startJoinTask(spaceName, items,
        join: (item) => mx.joinRoom(item.roomId, via: item.via));
  }
}

/// Joins [items] in the background with a progress card.
void startJoinTask(String spaceName, List<RoomBatchItem> items,
    {required Future<void> Function(RoomBatchItem item) join}) {
  final task = RoomBatchTask(
    verb: "Joining",
    doneVerb: "Joined",
    failVerb: "joined",
    spaceName: spaceName,
    items: items,
    run: join,
    retryAfter: MatrixSpaceHierarchy.retryAfter,
    reasonFor: (item, e) =>
        MatrixSpaceHierarchy.failureReason(e, joinRule: item.joinRule),
  );
  backgroundTaskManager.addTask(task);
  unawaited(task.start());
}

String get spaceJoinLoadFailed => Intl.message(
    "Couldn't load this space's rooms.",
    name: "spaceJoinLoadFailed",
    desc:
        "Shown in the space join picker when the space hierarchy failed to load");

String spaceJoinButton(int count) => Intl.plural(count,
    one: "Join 1 room",
    other: "Join $count rooms",
    args: [count],
    name: "spaceJoinButton",
    desc: "Button in the space join picker that joins the ticked rooms");

String get spaceJoinJustTheSpace => Intl.message("Just the space",
    name: "spaceJoinJustTheSpace",
    desc:
        "Button in the space join picker that joins only the space, no rooms");

String get spaceJoinSuggestedHint => Intl.message(
    "Rooms marked suggested by the space are ticked for you. Joining runs in the background.",
    name: "spaceJoinSuggestedHint",
    desc: "Hint next to the buttons of the space join picker");

String spaceJoinMemberCount(String count) => Intl.message("$count members",
    args: [count],
    name: "spaceJoinMemberCount",
    desc:
        "Member count of a space in the join picker header; count is an already formatted number");

String spaceJoinSubspaceCount(int count) => Intl.plural(count,
    one: "1 subspace",
    other: "$count subspaces",
    args: [count],
    name: "spaceJoinSubspaceCount",
    desc: "Number of subspaces in the space join picker header");

String spaceJoinRoomCount(int count) => Intl.plural(count,
    one: "1 room",
    other: "$count rooms",
    args: [count],
    name: "spaceJoinRoomCount",
    desc: "Number of rooms in the space join picker header");

String get spaceJoinFilterHint => Intl.message("Filter rooms and spaces",
    name: "spaceJoinFilterHint",
    desc: "Hint in the filter field of the space join picker");

String get spaceJoinSelectAll => Intl.message("Select all",
    name: "spaceJoinSelectAll",
    desc: "Pill button in the space join picker that ticks every room");

String get spaceJoinSelectNone => Intl.message("Select none",
    name: "spaceJoinSelectNone",
    desc: "Pill button in the space join picker that unticks every room");

String get spaceJoinSuggestedOnly => Intl.message("Suggested only",
    name: "spaceJoinSuggestedOnly",
    desc:
        "Pill button in the space join picker that ticks only suggested rooms");

String spaceJoinSelectedCount(int count) => Intl.message("$count selected",
    args: [count],
    name: "spaceJoinSelectedCount",
    desc: "Number of ticked rooms in the space join picker");

String spaceJoinSelectAllCapped(String count, int cap) => Intl.message(
    "Select all picked $count rooms. You can join up to $cap at once; the first $cap are ticked.",
    args: [count, cap],
    name: "spaceJoinSelectAllCapped",
    desc:
        "Warning after Select all ticked more rooms than can be joined at once; count is a formatted number, cap the limit");

String spaceJoinTickCapped(String count, int cap) => Intl.message(
    "That would tick $count rooms. You can join up to $cap at once; the first $cap are ticked.",
    args: [count, cap],
    name: "spaceJoinTickCapped",
    desc:
        "Warning when ticking a subspace would tick more rooms than can be joined at once; count is a formatted number, cap the limit");
