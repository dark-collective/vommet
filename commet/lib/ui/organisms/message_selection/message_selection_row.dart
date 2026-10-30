import 'package:commet/ui/atoms/clickable_gesture_detector.dart';
import 'package:commet/client/client.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/molecules/timeline_events/message_text_selection.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:flutter/gestures.dart';
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

  /// [position]: where the row was tapped. Vommet issue 786: on a picture
  /// of a media mosaic that ticks just the picture; elsewhere (the check
  /// circle, the space beside the bubble) the whole mosaic. [kind]: what
  /// tapped; only a mouse or trackpad Shift+click ticks a range.
  void onTap([Offset? position, PointerDeviceKind? kind]) {
    final selection = this.selection;
    if (selection == null) return;
    if (shiftHeld(kind)) {
      selection.tickRangeTo(widget.eventIds);
      return;
    }
    final tile = position == null || widget.eventIds.length < 2
        ? null
        : selection.tileAt(widget.eventIds, position);
    selection.toggle(tile == null ? widget.eventIds : [tile]);
  }

  /// Shift is held for a press by [kind]. Some Android on-screen keyboards
  /// leave Flutter thinking Shift is held (see TouchSelectionNormalizer), so
  /// a finger or stylus never counts as Shift+click: every tap would tick a
  /// range and a ticked message could never be unticked.
  static bool shiftHeld(PointerDeviceKind? kind) =>
      kind != null &&
      kind != PointerDeviceKind.touch &&
      kind != PointerDeviceKind.stylus &&
      HardwareKeyboard.instance.isShiftPressed;

  /// A tap ticks or unticks; a long press on a ticked message selects its
  /// text instead (phones; a long press on anything else still toggles).
  void onLongPress([Offset? position]) {
    final selection = this.selection;
    if (selection == null) return;
    if (ticked && MediaQuery.of(context).mobile) {
      final event = widget.eventIds.length == 1
          ? widget.timeline.tryGetEvent(widget.eventIds.single)
          : null;
      if (event != null &&
          MessageTextSelection.hasText(event) &&
          selection.selectText(widget.eventIds)) {
        return;
      }
    }
    onTap(position);
  }

  /// Desktop: a mouse drag from this row into another one selects messages
  /// (see [MessageSelection.pressDown]). Touch, any layout: after a long
  /// press, moving the finger on does the same. A [Listener], so the text
  /// selection and taps underneath still get the pointer; translucent, so a
  /// press on the empty space beside a bubble counts too. Its callbacks keep
  /// working if the row scrolls away mid-drag, so they don't touch [context]
  /// afterwards.
  Widget pressListener(MessageSelection selection, Widget child) {
    if (!MessageSelection.enabled) return child;
    final desktop = MediaQuery.of(context).desktop;
    final scrollable = Scrollable.maybeOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final touch = event.kind == PointerDeviceKind.touch ||
            event.kind == PointerDeviceKind.stylus;
        final mouse = desktop &&
            event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryMouseButton;
        if (!(touch || mouse) || shiftHeld(event.kind) || !mounted) {
          return;
        }
        selection.pressDown(widget.eventIds, scrollable,
            context.findAncestorStateOfType<SelectableRegionState>(),
            pointer: event.pointer, afterLongPress: touch);
      },
      onPointerMove: (event) =>
          selection.pressMove(event.position, pointer: event.pointer),
      onPointerUp: (event) => selection.pressEnd(event.pointer),
      onPointerCancel: (event) => selection.pressEnd(event.pointer),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = this.selection;
    if (selection == null) return widget.child;

    if (!tickable) {
      selection.rows.remove(this);
      if (!active) return widget.child;
      return Padding(
        padding:
            const EdgeInsets.only(left: MessageSelectionRow.circleColumnWidth),
        child: SelectionContainer.disabled(
            child: IgnorePointer(child: widget.child)),
      );
    }

    selection.rows[this] = (context, widget.eventIds);
    if (!active) return pressListener(selection, widget.child);

    final scrollable = Scrollable.maybeOf(context);
    final colors = Theme.of(context).colorScheme;

    final circleColumn = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => onTap(null, details.kind),
          // Dragging along the circles ticks (or unticks) every row passed.
          onVerticalDragStart: (_) {
            selection.setDragScrollable(scrollable);
            selection.dragStart(widget.eventIds);
          },
          onVerticalDragUpdate: (details) =>
              selection.dragUpdate(details.globalPosition),
          onVerticalDragEnd: (_) => selection.dragEnd(),
          onVerticalDragCancel: selection.dragEnd,
          child: SizedBox(
            width: MessageSelectionRow.circleColumnWidth,
            child: Center(child: SelectionCheckCircle(ticked: ticked)),
          ),
        ));

    // A Stack, not a Row with IntrinsicHeight: rows may hold widgets that
    // can't report intrinsic sizes.
    return pressListener(
        selection,
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: ticked ? colors.primary.withAlpha(28) : Colors.transparent,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    left: MessageSelectionRow.circleColumnWidth),
                // Out of the timeline's text selection, which may still be
                // dragging when a drag turns into message selection.
                child: SelectionContainer.disabled(
                    child: IgnorePointer(child: widget.child)),
              ),
              Positioned.fill(
                left: MessageSelectionRow.circleColumnWidth,
                child: ClickableGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) =>
                      onTap(details.globalPosition, details.kind),
                  onLongPressStart: (details) =>
                      onLongPress(details.globalPosition),
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
        ));
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
