// Vommet: the tick-box tree of a space's rooms and subspaces, used by the
// space join picker and by "Leave space" (to choose rooms to leave too).
// Lazy (only visible rows are built), and scrolls sideways as well when
// deep nesting makes it wider than its box; scroll bars only show in a
// direction that actually scrolls.

import 'dart:math';

import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceTreeView extends StatefulWidget {
  const SpaceTreeView({
    required this.tree,
    required this.avatarFor,
    required this.colorFor,
    required this.onChanged,
    this.filter = "",
    this.joinMode = true,
    this.noteFor,
    this.statusFor,
    this.statusWidth = 76,
    super.key,
  });

  final SpaceTree tree;
  final String filter;

  /// Joining: greys joined rooms ("Joined") and shows member counts.
  /// Leaving: every row is a room you're in, so neither is shown.
  final bool joinMode;

  /// Vommet (inviting): a status chip for each row, in place of the join or
  /// leave labels. Rows the tree can't select are then shown greyed out
  /// and can't be ticked.
  final Widget? Function(SpaceTreeNode node)? statusFor;

  /// Width kept for the status column, used to size sideways scrolling.
  final double statusWidth;

  final ImageProvider? Function(SpaceTreeNode node) avatarFor;
  final Color Function(String roomId) colorFor;
  final VoidCallback onChanged;

  /// A short note after a row's name (leaving: "also in <space>").
  final String? Function(SpaceTreeNode node)? noteFor;

  static const double rowHeight = 40;
  static const double indentStep = 22;

  @override
  State<SpaceTreeView> createState() => _SpaceTreeViewState();
}

class _SpaceTreeViewState extends State<SpaceTreeView> {
  final ScrollController vertical = ScrollController();
  final ScrollController horizontal = ScrollController();
  final Map<String, double> nameWidths = {};

  SpaceTree get tree => widget.tree;

  @override
  void dispose() {
    vertical.dispose();
    horizontal.dispose();
    super.dispose();
  }

  TextStyle nameStyle(BuildContext context, SpaceTreeNode n) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
          .copyWith(fontWeight: n.isSpace ? FontWeight.w700 : FontWeight.w400);

  double nameWidth(BuildContext context, SpaceTreeNode n) =>
      nameWidths.putIfAbsent(n.roomId, () {
        final painter = TextPainter(
            text: TextSpan(text: n.name, style: nameStyle(context, n)),
            maxLines: 1,
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context))
          ..layout();
        final w = painter.width;
        painter.dispose();
        return w;
      });

  double indentOf(SpaceTreeNode n) =>
      8.0 + (n.depth - 1) * SpaceTreeView.indentStep;

  /// Arrow, box, icon and the gaps between them, plus the right column.
  /// Arrow, box, icon and the gaps between them, without the right column.
  static const double fixedWidth = 22 + 4 + 24 + 8 + 26 + 8 + 16 + 12;

  @override
  Widget build(BuildContext context) {
    final rows = tree.visibleRows(filter: widget.filter);
    final extra = tree.canLoadMore || tree.hitTotalCap ? 1 : 0;

    return LayoutBuilder(builder: (context, constraints) {
      var width = constraints.maxWidth;
      for (final n in rows) {
        width = max(
            width,
            indentOf(n) +
                fixedWidth +
                widget.statusWidth +
                nameWidth(context, n));
      }

      final list = ListView.builder(
        controller: vertical,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: rows.length + extra,
        itemBuilder: (context, index) {
          if (index >= rows.length) return buildCapRow(context);
          return SizedBox(
              height: SpaceTreeView.rowHeight,
              child: buildRow(context, rows[index]));
        },
      );

      // Desktop builds its own scroll bars for every scrollable; these two
      // are placed by hand so the vertical one stays put when scrolling
      // sideways.
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Scrollbar(
          controller: vertical,
          notificationPredicate: (n) =>
              n.depth == 1 && n.metrics.axis == Axis.vertical,
          child: Scrollbar(
            controller: horizontal,
            notificationPredicate: (n) =>
                n.depth == 0 && n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: list,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget buildCapRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = NumberFormat.decimalPattern().format(tree.loadedCount);
    final text = tree.hitTotalCap
        ? "Showing the first $shown rooms and spaces, the most this list loads. Use Filter to find a room."
        : "Showing the first $shown rooms and spaces. This space has more: use Filter, or load the next ${SpaceTree.batchCap}.";
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(Icons.info_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(child: tiamat.Text.labelLow(text)),
            if (tree.canLoadMore)
              TextButton(
                onPressed: () async {
                  await tree.loadMore();
                  if (mounted) setState(() {});
                  widget.onChanged();
                },
                child: const Text("Load more"),
              ),
          ]),
        ),
      ),
    );
  }

  Widget buildRow(BuildContext context, SpaceTreeNode n) {
    final scheme = Theme.of(context).colorScheme;
    final dim = scheme.onSurfaceVariant;
    final joined = (widget.joinMode || widget.statusFor != null) &&
        n != tree.root &&
        !tree.selectable(n);
    final state = tree.stateOf(n);
    final ticked = state != false;
    final canExpand = tree.canExpand(n);

    Widget box = Checkbox(
      tristate: true,
      value: joined ? (widget.statusFor != null ? false : true) : state,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onChanged: joined ? null : (_) => toggle(n),
    );

    final Widget lead = n.isSpace
        ? tiamat.Avatar(
            radius: 13,
            image: widget.avatarFor(n),
            placeholderText: n.name,
            placeholderColor: widget.colorFor(n.roomId))
        : SizedBox(
            width: 26,
            child: Icon(
                n.info?.roomType == "org.matrix.msc3417.call"
                    ? Icons.headphones
                    : Icons.tag,
                size: 19,
                color: dim));

    final note = widget.noteFor?.call(n);
    Widget? trailing;
    if (widget.statusFor != null) {
      trailing = widget.statusFor!(n);
    } else if (note != null) {
      trailing = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(note,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: dim, fontStyle: FontStyle.italic)),
      );
    } else if (joined) {
      trailing = Text("Joined",
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.green.shade600, fontWeight: FontWeight.w600));
    } else if (n.isSpace) {
      final count = n.childCount;
      trailing = Text(count == 1 ? "1 room" : "$count rooms",
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: dim));
    } else if (widget.joinMode) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.person, size: 13, color: dim),
        const SizedBox(width: 2),
        Text("${n.info?.members ?? 0}",
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(color: dim)),
      ]);
    }

    return InkWell(
      key: ValueKey("space-tree-row-${n.roomId}"),
      onTap: joined ? null : () => toggle(n),
      child: Padding(
        padding: EdgeInsets.only(left: indentOf(n), right: 12),
        child: Row(children: [
          SizedBox(
            width: 22,
            child: canExpand
                ? InkResponse(
                    radius: 14,
                    onTap: () => toggleExpanded(n),
                    child: n.loading
                        ? const Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            n.expanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 20,
                            color: dim),
                  )
                : null,
          ),
          const SizedBox(width: 4),
          SizedBox(width: 24, child: box),
          const SizedBox(width: 8),
          lead,
          const SizedBox(width: 8),
          Expanded(
            child: Text(n.name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: nameStyle(context, n).copyWith(
                    color: joined || !ticked ? dim : scheme.onSurface)),
          ),
          const SizedBox(width: 16),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }

  void toggle(SpaceTreeNode n) {
    setState(() => tree.toggle(n));
    widget.onChanged();
  }

  Future<void> toggleExpanded(SpaceTreeNode n) async {
    if (n.expanded) {
      setState(() => n.expanded = false);
      return;
    }
    setState(() => n.expanded = true);
    await tree.expand(n);
    if (mounted) setState(() {});
    widget.onChanged();
  }
}
