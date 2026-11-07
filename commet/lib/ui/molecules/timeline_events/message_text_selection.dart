import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
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

  /// Whether [event] has text of its own to select: a message, but not a
  /// picture or file whose text is just its file name (as the menu's Copy).
  static bool hasText(TimelineEvent event) {
    if (event is! TimelineEventMessage) return false;
    final names = event.attachments?.map((a) => a.name).toSet() ?? {};
    return !names.contains(event.body);
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
    // Already chosen while this copy was being built, e.g. a long press on a
    // ticked message rebuilds its row as selection mode ends.
    if (MessageTextSelection.active.value == widget.eventId) {
      selecting = true;
      selectAllWhenReady();
    }
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

    if (now) selectAllWhenReady();
  }

  /// Selects the whole message once the new [SelectableRegion] knows its
  /// text. The text only registers with the region in a post-frame callback
  /// of the frame that builds it, queued after any callback added here, so
  /// selecting in that frame found nothing and showed no handles or toolbar
  /// (Vommet issue 787). Wait for that frame, then one more.
  Future<void> selectAllWhenReady() async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !selecting) return;
    focusNode.requestFocus();
    regionKey.currentState?.selectAll(SelectionChangedCause.toolbar);
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
