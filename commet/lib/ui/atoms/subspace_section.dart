import 'package:commet/client/client.dart';
import 'package:flutter/material.dart';

/// Vommet: a subspace in a space's room list (experiment
/// `experiment_sidebar_subspace_guides`). The name is a small-caps header with
/// the chevron on the left, and a faint line runs down the side of its rooms
/// so you can see where the subspace ends. The space owner's order is kept.
class SubspaceSection extends StatefulWidget {
  const SubspaceSection(this.space,
      {required this.child, this.depth = 0, super.key});

  final Space space;

  /// The subspace's own room list.
  final Widget child;

  /// 0 for a subspace directly in the open space.
  final int depth;

  @override
  State<SubspaceSection> createState() => _SubspaceSectionState();
}

class _SubspaceSectionState extends State<SubspaceSection> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: widget.depth == 0 ? 14 : 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => expanded = !expanded),
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.only(left: 2, right: 8),
                child: Row(
                  children: [
                    Icon(
                        expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 16,
                        color: scheme.secondary),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        widget.space.displayName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                                fontSize: 12,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w800,
                                color: scheme.secondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          Container(
            // 11 px per level, so deep subspaces leave room for names.
            margin: const EdgeInsets.only(left: 6, bottom: 2),
            padding: const EdgeInsets.only(left: 5),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                    width: 1.5),
              ),
            ),
            child: widget.child,
          ),
      ],
    );
  }
}
