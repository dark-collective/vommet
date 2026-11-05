import 'package:commet/client/attachment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show Intl;

/// The visible order is the send order, physically left to right in every locale.
/// Only the thumbnail supplied to the drag wrapper starts a drag; remove/edit/menu
/// controls remain independent. Flutter's reorder list supplies the moving gap
/// and edge auto-scroll. Touch scrolling wins until a long press is recognized.
class AttachmentOrderStrip extends StatefulWidget {
  const AttachmentOrderStrip(
      {super.key,
      required this.files,
      required this.itemBuilder,
      required this.onMove,
      required this.itemWidth,
      required this.height,
      this.enabled = true,
      this.badgeOnThumbnail = false,
      this.onDraggingChanged,
      this.trailing});

  final List<PendingFileAttachment> files;
  final Widget Function(int index, Widget Function(Widget) dragTarget)
      itemBuilder;

  /// [position] is the final index after removing [file].
  final void Function(PendingFileAttachment file, int position) onMove;
  final double itemWidth;
  final double height;
  final bool enabled;
  final bool badgeOnThumbnail;
  final ValueChanged<bool>? onDraggingChanged;
  final Widget? trailing;

  static String get orderHint => Intl.message("Send left to right · 1 is first",
      name: "attachmentOrderHint",
      desc:
          "The attachment strip's physical send direction, also in RTL locales");
  static String get moveEarlier => Intl.message("Move earlier",
      name: "attachmentMoveEarlier",
      desc: "Move a pending attachment one place toward the first file");
  static String get moveLater => Intl.message("Move later",
      name: "attachmentMoveLater",
      desc: "Move a pending attachment one place toward the last file");
  static String position(String name, int position, int count) =>
      Intl.message("$name · $position of $count",
          name: "attachmentOrderPosition",
          args: [name, position, count],
          desc: "File name and position in the send order");
  static String get dragHint =>
      Intl.message("Drag to reorder · Alt + Left/Right moves a focused file",
          name: "attachmentDragHint",
          desc: "Desktop attachment reorder instructions");

  @override
  State<AttachmentOrderStrip> createState() => AttachmentOrderStripState();
}

class AttachmentOrderStripState extends State<AttachmentOrderStrip> {
  final list = GlobalKey<ReorderableListState>();
  final scroll = ScrollController();
  final Map<PendingFileAttachment, FocusNode> nodes = {};
  List<PendingFileAttachment>? dragFiles;
  PendingFileAttachment? dragging;
  int generation = 0;

  bool get canMove => widget.enabled && widget.files.length > 1;

  @override
  void didUpdateWidget(covariant AttachmentOrderStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (dragFiles != null &&
        (!canMove || !listEquals(dragFiles, widget.files))) {
      cancelDrag(notifyLater: true);
    }
    for (final file in nodes.keys.toList()) {
      if (!widget.files.contains(file)) nodes.remove(file)?.dispose();
    }
  }

  void notify(bool value, {bool later = false}) {
    if (later) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDraggingChanged?.call(value);
      });
    } else {
      widget.onDraggingChanged?.call(value);
    }
  }

  void finish({bool notifyLater = false}) {
    if (dragFiles == null) return;
    generation++;
    FocusManager.instance.removeEarlyKeyEventHandler(escape);
    dragging = null;
    dragFiles = null;
    if (mounted) setState(() {});
    notify(false, later: notifyLater);
  }

  void cancelDrag({bool notifyLater = false}) {
    list.currentState?.cancelReorder();
    finish(notifyLater: notifyLater);
  }

  KeyEventResult escape(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      cancelDrag();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void move(PendingFileAttachment file, int position) {
    if (!canMove || position < 0 || position >= widget.files.length) return;
    final hadFocus = nodes[file]?.hasFocus ?? false;
    widget.onMove(file, position);
    if (hadFocus) nodes[file]?.requestFocus();
    final label = AttachmentOrderStrip.position(
        file.name ?? "File", position + 1, widget.files.length);
    SemanticsService.sendAnnouncement(
        View.of(context), label, Directionality.of(context));
  }

  Widget dragTarget(int index, Widget child) => MouseRegion(
      cursor: canMove ? SystemMouseCursors.grab : MouseCursor.defer,
      child: Listener(
          onPointerDown: (event) {
            if (!canMove ||
                dragFiles != null ||
                event.buttons != kPrimaryButton) return;
            if (event.kind == PointerDeviceKind.mouse)
              nodes[widget.files[index]]?.requestFocus();
            list.currentState?.startItemDragReorder(
                index: index,
                event: event,
                recognizer: event.kind == PointerDeviceKind.mouse
                    ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
                    : DelayedMultiDragGestureRecognizer(debugOwner: this));
          },
          child: child));

  @override
  void dispose() {
    if (dragFiles != null) {
      final callback = widget.onDraggingChanged;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => callback?.call(false));
    }
    FocusManager.instance.removeEarlyKeyEventHandler(escape);
    for (final node in nodes.values) {
      node.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          height: widget.height,
          child: Listener(
              onPointerCancel: (_) {
                if (dragFiles != null) cancelDrag();
              },
              child: ReorderableList(
                  key: list,
                  controller: scroll,
                  scrollDirection: Axis.horizontal,
                  itemExtent: widget.itemWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount:
                      widget.files.length + (widget.trailing == null ? 0 : 1),
                  onReorderStart: (index) {
                    setState(() {
                      dragging = widget.files[index];
                      dragFiles = List.of(widget.files);
                      generation++;
                    });
                    FocusManager.instance.addEarlyKeyEventHandler(escape);
                    notify(true);
                  },
                  onReorderEnd: (position) {
                    // No onReorder callback is made for a drop in the same slot.
                    // Cancel its return animation before enabling mutations.
                    if (dragFiles != null &&
                        position == dragFiles!.indexOf(dragging!)) {
                      final current = generation;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && generation == current) cancelDrag();
                      });
                    }
                  },
                  onReorder: (oldIndex, newIndex) {
                    if (dragFiles != null &&
                        listEquals(dragFiles, widget.files) &&
                        canMove) {
                      final file = dragFiles![oldIndex];
                      move(
                          file,
                          (newIndex > oldIndex ? newIndex - 1 : newIndex)
                              .clamp(0, widget.files.length - 1));
                    }
                    finish();
                  },
                  proxyDecorator: (child, index, animation) {
                    return Material(
                        elevation: 6,
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    width: 2),
                                borderRadius: BorderRadius.circular(8)),
                            child: ExcludeSemantics(
                                child: IgnorePointer(child: child))));
                  },
                  itemBuilder: (context, index) {
                    if (index == widget.files.length) {
                      return SizedBox(
                          key: const ValueKey('attachment-order-add'),
                          width: widget.itemWidth,
                          child: widget.trailing);
                    }
                    final file = widget.files[index];
                    final node = nodes.putIfAbsent(file, () => FocusNode());
                    final label = AttachmentOrderStrip.position(
                        file.name ?? "File", index + 1, widget.files.length);
                    return Focus(
                        key: ObjectKey(file),
                        focusNode: node,
                        onKeyEvent: (_, event) {
                          if (event is! KeyDownEvent ||
                              !HardwareKeyboard.instance.isAltPressed ||
                              !canMove ||
                              dragFiles != null) return KeyEventResult.ignored;
                          final delta =
                              event.logicalKey == LogicalKeyboardKey.arrowLeft
                                  ? -1
                                  : event.logicalKey ==
                                          LogicalKeyboardKey.arrowRight
                                      ? 1
                                      : 0;
                          if (delta == 0) return KeyEventResult.ignored;
                          move(file, index + delta);
                          return KeyEventResult.handled;
                        },
                        child: Semantics(
                            label: label,
                            customSemanticsActions: {
                              if (canMove && dragFiles == null && index > 0)
                                CustomSemanticsAction(
                                    label:
                                        AttachmentOrderStrip.moveEarlier): () =>
                                    move(file, index - 1),
                              if (canMove &&
                                  dragFiles == null &&
                                  index + 1 < widget.files.length)
                                CustomSemanticsAction(
                                        label: AttachmentOrderStrip.moveLater):
                                    () => move(file, index + 1),
                            },
                            child: AnimatedBuilder(
                                animation: node,
                                builder: (context, _) => DecoratedBox(
                                    decoration: BoxDecoration(
                                        border: node.hasFocus
                                            ? Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary)
                                            : null,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Stack(children: [
                                      IgnorePointer(
                                          ignoring: dragFiles != null,
                                          child: widget.itemBuilder(
                                              index,
                                              (child) =>
                                                  dragTarget(index, child))),
                                      if (widget.files.length > 1)
                                        Positioned(
                                            left:
                                                widget.badgeOnThumbnail ? 6 : 8,
                                            bottom: 4,
                                            child: PopupMenuButton<int>(
                                                enabled: canMove &&
                                                    dragFiles == null,
                                                tooltip: label,
                                                padding: EdgeInsets.zero,
                                                onSelected: (delta) =>
                                                    move(file, index + delta),
                                                itemBuilder: (_) => [
                                                      if (index > 0)
                                                        PopupMenuItem(
                                                            value: -1,
                                                            child: Text(
                                                                AttachmentOrderStrip
                                                                    .moveEarlier)),
                                                      if (index + 1 <
                                                          widget.files.length)
                                                        PopupMenuItem(
                                                            value: 1,
                                                            child: Text(
                                                                AttachmentOrderStrip
                                                                    .moveLater)),
                                                    ],
                                                child: Container(
                                                    constraints:
                                                        const BoxConstraints(
                                                            minWidth: 32,
                                                            minHeight: 32),
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                        color: Colors.black87,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6)),
                                                    child: Text('${index + 1}',
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold))))),
                                    ])))));
                  })),
        ),
      );
}
