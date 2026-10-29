import 'package:commet/main.dart';
import 'package:commet/ui/molecules/video_player/video_pip_geometry.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String get videoPipOpen => Intl.message(
      "Picture in picture",
      name: "videoPipOpen",
      desc:
          "Tooltip and menu item: keep playing the video in a small floating window",
    );

String get videoPipBackToMessage => Intl.message(
      "Back to message",
      name: "videoPipBackToMessage",
      desc:
          "Tooltip of the floating video window's button that opens the message the video came from",
    );

String get videoPipExpand => Intl.message(
      "Full screen",
      name: "videoPipExpand",
      desc:
          "Tooltip of the floating video window's button that opens the video in the full media viewer",
    );

String get videoPipClose => Intl.message(
      "Close",
      name: "videoPipClose",
      desc: "Tooltip of the floating video window's close button",
    );

String get videoPipBringBack => Intl.message(
      "Playing in picture in picture. Tap to bring it back",
      name: "videoPipBringBack",
      desc:
          "Tooltip on a video in a message while it plays in the floating window",
    );

/// What to show in the picture-in-picture window.
class VideoPipRequest {
  const VideoPipRequest({
    required this.player,
    this.aspectRatio,
    this.onBackToMessage,
    this.onExpand,
    this.onClosed,
  });

  /// Builds the player. Give it the same key as the player it came from so
  /// it carries on playing where it was instead of starting again.
  final WidgetBuilder player;
  final double? aspectRatio;

  /// Opens the room at the video's message. Hidden when null.
  final VoidCallback? onBackToMessage;

  /// Opens the video in the media viewer (also a double-click on it).
  final VoidCallback? onExpand;

  /// Called when the window goes away for any reason (closed, expanded,
  /// replaced by another video), so the player can go back in its message.
  final VoidCallback? onClosed;
}

/// Vommet: picture-in-picture. A small floating video window that stays on
/// screen while you move around the app (switching rooms included): drag it
/// to a corner, drag its grip to resize it, double-click it for the full
/// viewer. One video at a time; opening another replaces it.
class VideoPip {
  static OverlayEntry? _entry;
  static VideoPipRequest? _current;

  /// Whether a video is in the floating window.
  static final ValueNotifier<bool> isOpen = ValueNotifier(false);

  static bool show(VideoPipRequest request) {
    final overlay = navigator.currentState?.overlay;
    if (overlay == null) return false;
    close();
    _current = request;
    _entry = OverlayEntry(
        builder: (context) => _VideoPipWindow(
            key: ObjectKey(request), request: request, onClose: close));
    overlay.insert(_entry!);
    isOpen.value = true;
    return true;
  }

  /// Takes the window away; the player goes back in its message.
  static void close() {
    final request = _current;
    _entry?.remove();
    _entry = null;
    _current = null;
    isOpen.value = false;
    request?.onClosed?.call();
  }

  static void expand() {
    final onExpand = _current?.onExpand;
    close();
    onExpand?.call();
  }
}

class _VideoPipWindow extends StatefulWidget {
  const _VideoPipWindow(
      {required this.request, required this.onClose, super.key});
  final VideoPipRequest request;
  final VoidCallback onClose;

  @override
  State<_VideoPipWindow> createState() => _VideoPipWindowState();
}

class _VideoPipWindowState extends State<_VideoPipWindow> {
  Alignment corner = Alignment.bottomRight;
  double width = VideoPipGeometry.defaultWidth;

  /// While dragging, where the window is (top-left); null when docked.
  Offset? dragOffset;

  DateTime? lastDown;
  Offset? lastDownPosition;

  double get aspectRatio =>
      VideoPipGeometry.safeAspectRatio(widget.request.aspectRatio);

  /// A double-click (or double tap) on the video, spotted without joining
  /// the gesture arena so the player's own buttons stay instant.
  void onPointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    final previous = lastDown;
    final previousPosition = lastDownPosition;
    lastDown = now;
    lastDownPosition = event.position;
    if (previous == null || previousPosition == null) return;
    if (now.difference(previous) < const Duration(milliseconds: 350) &&
        (event.position - previousPosition).distance < 20) {
      lastDown = null;
      if (widget.request.onExpand != null) VideoPip.expand();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final w = VideoPipGeometry.clampWidth(width, screen, aspectRatio);
    final size = VideoPipGeometry.windowSize(w, aspectRatio);
    final offset = dragOffset ??
        VideoPipGeometry.dockedOffset(corner, size, screen,
            padding: media.padding);
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: size.width,
      height: size.height,
      child: Material(
        elevation: 8,
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        child: Column(children: [
          GestureDetector(
            onPanStart: (_) => setState(() => dragOffset = offset),
            onPanUpdate: (details) =>
                setState(() => dragOffset = dragOffset! + details.delta),
            onPanEnd: (_) => setState(() {
              corner = VideoPipGeometry.nearestCorner(
                  dragOffset! + size.center(Offset.zero), screen);
              dragOffset = null;
            }),
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Container(
                height: VideoPipGeometry.barHeight,
                color: scheme.surfaceContainer,
                child: Row(children: [
                  const SizedBox(width: 8),
                  Icon(Icons.drag_indicator,
                      size: 18, color: scheme.onSurfaceVariant),
                  const Spacer(),
                  if (widget.request.onBackToMessage != null)
                    button(Icons.chat_bubble_outline, videoPipBackToMessage,
                        () => widget.request.onBackToMessage?.call()),
                  if (widget.request.onExpand != null)
                    button(Icons.fullscreen, videoPipExpand, VideoPip.expand),
                  button(Icons.close, videoPipClose, widget.onClose),
                ]),
              ),
            ),
          ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: Listener(
                  onPointerDown: onPointerDown,
                  child: widget.request.player(context),
                ),
              ),
              resizeGrip(scheme),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget button(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: onPressed,
    );
  }

  /// The grip sits in the corner that faces the middle of the screen; the
  /// docked corner stays put while it is dragged.
  Widget resizeGrip(ColorScheme scheme) {
    final growsLeft = corner.x > 0;
    final atTop = corner.y > 0;
    return Positioned(
      left: growsLeft ? 0 : null,
      right: growsLeft ? null : 0,
      top: atTop ? 0 : null,
      bottom: atTop ? null : 0,
      child: GestureDetector(
        onPanUpdate: (details) => setState(() => width =
            VideoPipGeometry.clampWidth(width - corner.x * details.delta.dx,
                MediaQuery.sizeOf(context), aspectRatio)),
        child: MouseRegion(
          cursor: growsLeft == atTop
              ? SystemMouseCursors.resizeUpLeftDownRight
              : SystemMouseCursors.resizeUpRightDownLeft,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(Icons.open_in_full,
                size: 12, color: scheme.onSurface.withAlpha(160)),
          ),
        ),
      ),
    );
  }
}
