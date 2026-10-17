import 'package:commet/client/client.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet: one timeline row while messages are being selected: a check
/// circle on the left, a tint when ticked, and taps that tick instead of
/// opening anything. Draws just [child] when not selecting.
class MessageSelectionRow extends StatefulWidget {
  const MessageSelectionRow(
      {required this.timeline,
      required this.eventIds,
      required this.child,
      super.key});

  final Timeline timeline;

  /// The events this row stands for (several for a media mosaic).
  final List<String> eventIds;
  final Widget child;

  static const double circleColumnWidth = 40;

  @override
  State<MessageSelectionRow> createState() => _MessageSelectionRowState();
}

class _MessageSelectionRowState extends State<MessageSelectionRow> {
  MessageSelection? selection;
  bool active = false;
  bool ticked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final found = MessageSelectionScope.maybeOf(context);
    if (found != selection) {
      selection?.removeListener(onSelectionChanged);
      selection?.rows.remove(this);
      selection = found;
      selection?.addListener(onSelectionChanged);
      readState();
    }
  }

  @override
  void dispose() {
    selection?.removeListener(onSelectionChanged);
    selection?.rows.remove(this);
    super.dispose();
  }

  void readState() {
    active = selection?.active == true;
    ticked = selection?.isTicked(widget.eventIds) == true;
  }

  void onSelectionChanged() {
    final wasActive = active;
    final wasTicked = ticked;
    readState();
    if (mounted && (wasActive != active || wasTicked != ticked)) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant MessageSelectionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    readState();
  }

  bool get tickable {
    if (widget.eventIds.isEmpty) return false;
    final event = widget.timeline.tryGetEvent(widget.eventIds.first);
    return event != null && MessageSelection.canTick(event, widget.timeline);
  }

  void onTap() {
    final selection = this.selection;
    if (selection == null) return;
    if (HardwareKeyboard.instance.isShiftPressed) {
      selection.tickRangeTo(widget.eventIds);
    } else {
      selection.toggle(widget.eventIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = this.selection;
    if (selection == null || !active) {
      selection?.rows.remove(this);
      return widget.child;
    }

    if (!tickable) {
      selection.rows.remove(this);
      return Padding(
        padding:
            const EdgeInsets.only(left: MessageSelectionRow.circleColumnWidth),
        child: IgnorePointer(child: widget.child),
      );
    }

    selection.rows[this] = (context, widget.eventIds);
    final colors = Theme.of(context).colorScheme;

    final circleColumn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Dragging along the circles ticks (or unticks) every row passed.
      onVerticalDragStart: (_) => selection.dragStart(widget.eventIds),
      onVerticalDragUpdate: (details) =>
          selection.dragUpdate(details.globalPosition),
      onVerticalDragEnd: (_) => selection.dragEnd(),
      onVerticalDragCancel: selection.dragEnd,
      child: SizedBox(
        width: MessageSelectionRow.circleColumnWidth,
        child: Center(child: SelectionCheckCircle(ticked: ticked)),
      ),
    );

    // A Stack, not a Row with IntrinsicHeight: rows may hold widgets that
    // can't report intrinsic sizes.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      color: ticked ? colors.primary.withAlpha(28) : Colors.transparent,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(
                left: MessageSelectionRow.circleColumnWidth),
            child: IgnorePointer(child: widget.child),
          ),
          Positioned.fill(
            left: MessageSelectionRow.circleColumnWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onLongPress: onTap,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MessageSelectionRow.circleColumnWidth,
            child: circleColumn,
          ),
        ],
      ),
    );
  }
}

/// A round check: an outline when unticked, filled with the accent and a
/// check mark when ticked.
class SelectionCheckCircle extends StatelessWidget {
  const SelectionCheckCircle({required this.ticked, super.key});

  final bool ticked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ticked ? colors.primary : Colors.transparent,
        border: Border.all(
            color: ticked ? colors.primary : colors.onSurfaceVariant, width: 2),
      ),
      child:
          ticked ? Icon(Icons.check, size: 14, color: colors.onPrimary) : null,
    );
  }
}
