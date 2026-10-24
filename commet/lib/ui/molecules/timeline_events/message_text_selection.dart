import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:intl/intl.dart';

/// Vommet: selecting part of one message's text on a phone (Vommet issue
/// 652). Phones have no timeline-wide [SelectionArea] (a long-press opens
/// the message menu instead), so the menu's "Select text" turns selection on
/// for that one message: its text starts fully selected, with the platform's
/// handles and Copy / Select all toolbar. Tapping outside the message, or
/// copying, ends it.
class MessageTextSelection {
  /// The event whose text is selectable right now, or null.
  static final ValueNotifier<String?> active = ValueNotifier(null);

  /// How many scopes are mounted per event, so disposing one copy of a
  /// message (e.g. a preview) doesn't end the selection in another.
  static final Map<String, int> _scopes = {};

  static void start(String eventId) => active.value = eventId;

  static void end(String eventId) {
    if (active.value == eventId) active.value = null;
  }

  static String get promptSelectText => Intl.message(
        "Select text",
        desc:
            "Label for the message menu option that lets you select part of a message's text (phones)",
        name: "promptSelectText",
      );
}

/// Wraps a message's content; selectable only while [MessageTextSelection]
/// names [eventId].
class MessageTextSelectionScope extends StatefulWidget {
  const MessageTextSelectionScope(
      {required this.eventId, required this.child, super.key});

  final String eventId;
  final Widget child;

  @override
  State<MessageTextSelectionScope> createState() =>
      _MessageTextSelectionScopeState();
}

class _MessageTextSelectionScopeState extends State<MessageTextSelectionScope> {
  final GlobalKey<SelectableRegionState> regionKey = GlobalKey();
  final FocusNode focusNode = FocusNode();
  bool selecting = false;
  bool hadSelection = false;

  @override
  void initState() {
    super.initState();
    MessageTextSelection._scopes
        .update(widget.eventId, (n) => n + 1, ifAbsent: () => 1);
    MessageTextSelection.active.addListener(onActiveChanged);
  }

  @override
  void didUpdateWidget(MessageTextSelectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId == widget.eventId) return;
    release(oldWidget.eventId);
    MessageTextSelection._scopes
        .update(widget.eventId, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    MessageTextSelection.active.removeListener(onActiveChanged);
    release(widget.eventId);
    focusNode.dispose();
    super.dispose();
  }

  /// Ends [eventId]'s selection only when no other scope shows that event.
  void release(String eventId) {
    var left = (MessageTextSelection._scopes[eventId] ?? 1) - 1;
    if (left > 0) {
      MessageTextSelection._scopes[eventId] = left;
    } else {
      MessageTextSelection._scopes.remove(eventId);
      MessageTextSelection.end(eventId);
    }
  }

  void onActiveChanged() {
    var now = MessageTextSelection.active.value == widget.eventId;
    if (now == selecting || !mounted) return;

    setState(() {
      selecting = now;
      hadSelection = false;
    });

    if (now) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !selecting) return;
        focusNode.requestFocus();
        regionKey.currentState?.selectAll(SelectionChangedCause.toolbar);
      });
    }
  }

  void onSelectionChanged(SelectedContent? content) {
    var hasText = content != null && content.plainText.isNotEmpty;
    if (hasText) {
      hadSelection = true;
    } else if (hadSelection) {
      // Copied, or the selection was collapsed: done.
      MessageTextSelection.end(widget.eventId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!selecting) return widget.child;

    return TapRegion(
      // The handles and toolbar share this group, so using them isn't
      // "outside".
      groupId: SelectableRegion,
      onTapOutside: (_) => MessageTextSelection.end(widget.eventId),
      child: SelectableRegion(
        key: regionKey,
        focusNode: focusNode,
        selectionControls: switch (Theme.of(context).platform) {
          TargetPlatform.iOS ||
          TargetPlatform.macOS =>
            cupertinoTextSelectionHandleControls,
          _ => materialTextSelectionHandleControls,
        },
        contextMenuBuilder: (context, state) =>
            AdaptiveTextSelectionToolbar.selectableRegion(
                selectableRegionState: state),
        onSelectionChanged: onSelectionChanged,
        child: widget.child,
      ),
    );
  }
}
