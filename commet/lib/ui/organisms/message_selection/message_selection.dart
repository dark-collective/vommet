import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/hidden_messages/hidden_messages.dart';
import 'package:commet/client/components/polls/poll_component.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/timeline_events/message_text_selection.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/message_selection/delete_for_dialog.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:commet/utils/selection_set.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Vommet: several messages ticked at once, Telegram-style (experiment
/// `vommet_experiment_select_messages`). One per room view and one per open
/// thread, each separate, owned by its [MessageSelectionHost]; the timeline
/// rows find it through [MessageSelectionScope] and the room header through
/// [activeIn] (the room's own view only; a thread shows its own bar).
class MessageSelection extends ChangeNotifier {
  MessageSelection(this.room);

  final Room room;
  Timeline? timeline;

  final SelectionSet ticked = SelectionSet();
  bool active = false;

  /// Shown in the selection bar while deleting or forwarding.
  String? progress;
  bool get busy => progress != null;

  bool _disposed = false;

  static bool get enabled => preferences.experimentSelectMessages.value;

  static String get promptSelectMessage => Intl.message(
        "Select",
        desc:
            "Label for the menu option that starts selecting several messages",
        name: "promptSelectMessage",
      );

  static String messageSelectionDeleteTitle(int count) => Intl.plural(count,
      one: "Delete 1 message?",
      other: "Delete $count messages?",
      args: [count],
      name: "messageSelectionDeleteTitle",
      desc:
          "Selecting several messages: title of the dialog confirming deleting the ticked messages");

  static String get messageSelectionDeletePrompt => Intl.message(
      "They're removed for everyone in the room.",
      name: "messageSelectionDeletePrompt",
      desc:
          "Selecting several messages: dialog confirming deleting the ticked messages");

  static String messageSelectionDeleteKept(int count) => Intl.message(
      "You can't delete $count of them; they stay.",
      args: [count],
      name: "messageSelectionDeleteKept",
      desc:
          "Selecting several messages: second line of the delete dialog when some ticked messages can't be deleted");

  static String messageSelectionDeleting(int current, int total) =>
      Intl.message("Deleting $current of $total…",
          args: [current, total],
          name: "messageSelectionDeleting",
          desc: "Selecting several messages: progress while deleting");

  // Room views with a selection, so the room header can find theirs.
  static final Map<String, MessageSelection> _byRoom = {};

  /// Bumped whenever a selection starts or ends.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static String _keyFor(Room room) =>
      "${room.client.identifier}\u0000${room.identifier}";

  /// The selection in progress in [room], if any.
  static MessageSelection? activeIn(Room room) {
    final selection = _byRoom[_keyFor(room)];
    return selection?.active == true ? selection : null;
  }

  void register() {
    _byRoom[_keyFor(room)] = this;
  }

  // Active selections, the one used last at the end: it gets Esc, Ctrl+C,
  // Delete and the back gesture when a room and its thread both select.
  static final List<MessageSelection> _used = [];

  void _markUsed() {
    _used.remove(this);
    if (active) _used.add(this);
  }

  /// Whether keys and the back gesture go to this selection.
  bool get ownsKeys => active && _used.isNotEmpty && _used.last == this;

  @override
  void dispose() {
    _disposed = true;
    _stopAutoScroll();
    _used.remove(this);
    if (_byRoom[_keyFor(room)] == this) _byRoom.remove(_keyFor(room));
    if (active) _bumpChanged();
    rows.clear();
    tiles.clear();
    super.dispose();
  }

  void _bumpChanged() {
    // The header may be mid-build when a room view goes away.
    WidgetsBinding.instance.addPostFrameCallback((_) => changed.value++);
    WidgetsBinding.instance.scheduleFrame();
  }

  void _notify() {
    if (_disposed) return;
    _markUsed();
    notifyListeners();
  }

  /// Whether [timeline] is a thread's, where thread replies can be ticked.
  static bool isThread(Timeline timeline) => timeline is MatrixThreadTimeline;

  /// Whether [event] can be ticked: a sent message, sticker, emote or poll
  /// that is shown in [timeline] (thread replies only in a thread's).
  static bool canTick(TimelineEvent event, Timeline timeline) {
    if (event.status != TimelineEventStatus.synced) return false;
    if (timeline.isEventRedacted(event)) return false;
    final polls = timeline.client.getComponent<PollComponent>();
    if (event is! TimelineEventMessage &&
        event is! TimelineEventSticker &&
        event is! TimelineEventEmote &&
        polls?.isPollEvent(event) != true) {
      return false;
    }
    if (isThread(timeline)) return true;
    final threads = timeline.client.getComponent<ThreadsComponent>();
    return threads?.isEventInResponseToThread(event, timeline) != true;
  }

  /// Ids of the tickable events, newest first like [Timeline.events].
  List<String> orderedIds() {
    final t = timeline;
    if (t == null) return const [];
    return [
      for (final event in t.events)
        if (canTick(event, t)) event.eventId
    ];
  }

  /// Ticked events, oldest first.
  List<TimelineEvent> tickedEvents() {
    final t = timeline;
    if (t == null) return const [];
    return [
      for (final event in t.events.reversed)
        if (ticked.contains(event.eventId)) event
    ];
  }

  bool isTicked(List<String> group) => active && ticked.containsAll(group);

  /// Vommet issue 786: whether any of [group] is ticked (a media mosaic may
  /// be ticked only in part).
  bool isAnyTicked(List<String> group) => active && group.any(ticked.contains);

  /// Unticks all of [group].
  void untick(List<String> group) {
    if (!active || busy) return;
    ticked.setAll(group, false);
    _afterChange();
  }

  bool canDelete(TimelineEvent event) =>
      timeline?.canDeleteEvent(event) == true &&
      event.status == TimelineEventStatus.synced;

  /// How many ticked messages Delete acts on: with "Delete for me", every
  /// one the server has; otherwise those you may delete.
  int get deletableCount => HiddenMessages.supported(room)
      ? hideableEvents().length
      : SelectionSet.deletableCount(tickedEvents(), canDelete);

  /// Ticked messages "Delete for me" can hide: those the server has.
  List<TimelineEvent> hideableEvents() => tickedEvents()
      .where((event) => event.status == TimelineEventStatus.synced)
      .toList();

  List<TimelineEvent> forwardableEvents() =>
      tickedEvents().where(MatrixForwarding.canForward).toList();

  void start(List<String> group) {
    ticked.clear();
    ticked.toggle(group);
    active = ticked.isNotEmpty;
    progress = null;
    _notify();
    _bumpChanged();
  }

  void exit() {
    if (!active) return;
    active = false;
    ticked.clear();
    progress = null;
    _notify();
    _bumpChanged();
  }

  void _afterChange() {
    if (ticked.isEmpty && !busy) {
      exit();
    } else {
      _notify();
    }
  }

  void toggle(List<String> group) {
    if (!active || busy) return;
    ticked.toggle(group);
    _afterChange();
  }

  /// A long press on a ticked message (Vommet issue 789): ends message
  /// selection and makes that message's text selectable instead, as the
  /// menu's "Select text" does. False (nothing done) for anything but a
  /// single ticked message.
  bool selectText(List<String> group) {
    if (!active || busy || group.length != 1 || !isTicked(group)) {
      return false;
    }
    // The finger is still down: moving it on must not start a drag.
    dragEnd();
    exit();
    MessageTextSelection.start(group.single);
    return true;
  }

  /// Shift+click: ticks the rows between the last toggled one and [group].
  void tickRangeTo(List<String> group) {
    if (!active || busy) return;
    ticked.tickRange(orderedIds(), group);
    _afterChange();
  }

  // Drag-to-tick over the check circles, or a mouse drag from one message
  // into another. Tickable rows register here (selecting or not) so the drag
  // can find the row under the pointer.
  final Map<Object, (BuildContext, List<String>)> rows = {};
  List<String>? _dragOrder;
  String? _dragRow;

  void dragStart(List<String> group) {
    if (!active || busy || group.isEmpty || _dragOrder != null) return;
    _dragOrder = orderedIds();
    _dragRow = group.first;
    ticked.dragStart(group);
    _notify();
  }

  // Vommet issue 786: the pictures of a media mosaic register here while
  // selecting, so a tap on one ticks just that picture.
  final Map<Object, (BuildContext, String)> tiles = {};

  /// The id of the registered mosaic picture of [group] under
  /// [globalPosition], if any.
  String? tileAt(List<String> group, Offset globalPosition) {
    for (final (context, id) in tiles.values) {
      if (!context.mounted || !group.contains(id)) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final local = box.globalToLocal(globalPosition);
      if (box.size.contains(local)) return id;
    }
    return null;
  }

  /// The group of the registered row under [globalPosition], if any.
  List<String>? groupAt(Offset globalPosition) {
    for (final (context, group) in rows.values) {
      if (!context.mounted || group.isEmpty) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (globalPosition.dy >= top &&
          globalPosition.dy < top + box.size.height) {
        return group;
      }
    }
    return null;
  }

  void dragUpdate(Offset globalPosition) {
    final order = _dragOrder;
    if (order == null || !ticked.dragging) return;
    _dragPointer = globalPosition;
    _autoScrollIfAtEdge();
    final group = groupAt(globalPosition);
    if (group != null && group.first != _dragRow) {
      _dragRow = group.first;
      ticked.dragOver(order, group);
      _notify();
    }
  }

  void dragEnd() {
    _stopAutoScroll();
    _pressGroup = null;
    _pressPointer = null;
    _pressAfterLongPress = false;
    _textSelection = null;
    if (_dragOrder == null) return;
    _dragOrder = null;
    _dragRow = null;
    ticked.dragEnd();
    _afterChange();
  }

  // Desktop, Telegram-style: a mouse drag that starts on a message is a text
  // selection while it stays inside that message; once it reaches another
  // message it selects messages instead, ticking every one it passes. On
  // touch the same happens once a long press has ticked the message (before
  // that a moving finger scrolls).
  List<String>? _pressGroup;
  int? _pressPointer;
  bool _pressAfterLongPress = false;

  bool _pressWasTicked = false;
  SelectableRegionState? _textSelection;

  /// [textSelection] is the timeline's text selection, cleared when the drag
  /// turns into message selection. With [afterLongPress] (touch) the drag
  /// only selects once a long press has changed the row's tick.
  void pressDown(List<String> group, ScrollableState? scrollable,
      SelectableRegionState? textSelection,
      {int? pointer, bool afterLongPress = false}) {
    if (!enabled || busy || group.isEmpty || _dragOrder != null) return;
    _pressGroup = group;
    _pressPointer = pointer;
    _pressAfterLongPress = afterLongPress;
    _pressWasTicked = isTicked(group);
    _scrollable = scrollable;
    _textSelection = textSelection;
  }

  void pressMove(Offset globalPosition, {int? pointer}) {
    if (_pressPointer != null && pointer != _pressPointer) return;
    if (_dragOrder != null) {
      dragUpdate(globalPosition);
      return;
    }
    final start = _pressGroup;
    if (start == null) return;
    // Touch: no long press yet, so the finger is scrolling.
    if (_pressAfterLongPress && isTicked(start) == _pressWasTicked) return;
    final group = groupAt(globalPosition);
    if (group == null || group.first == start.first) return;
    _pressGroup = null;
    final textSelection = _textSelection;
    _textSelection = null;
    if (textSelection != null && textSelection.mounted) {
      textSelection.clearSelection();
    }
    if (!active) {
      ticked.clear();
      active = true;
      progress = null;
      _bumpChanged();
    } else if (isTicked(start) != _pressWasTicked) {
      // A long press already toggled the row; the drag goes on in that
      // state instead of flipping it back.
      ticked.toggle(start);
    }
    dragStart(start);
    dragUpdate(globalPosition);
  }

  /// The pointer that pressed went up (or was cancelled).
  void pressEnd(int pointer) {
    if (_pressPointer != null && pointer != _pressPointer) return;
    dragEnd();
  }

  // Scrolls the timeline while a drag is held near its top or bottom edge.
  ScrollableState? _scrollable;
  Offset? _dragPointer;
  Timer? _autoScroll;
  static const double _edge = 48;

  /// The timeline [dragStart] scrolls when the drag nears an edge.
  void setDragScrollable(ScrollableState? scrollable) {
    _scrollable = scrollable;
  }

  void _autoScrollIfAtEdge() {
    if (_scrollDelta() == 0) {
      _stopAutoScroll();
    } else {
      _autoScroll ??= Timer.periodic(
          const Duration(milliseconds: 16), (_) => _autoScrollTick());
    }
  }

  /// Pixels to move per tick, signed for the scroll position; 0 when the
  /// pointer is away from the edges.
  double _scrollDelta() {
    final scrollable = _scrollable;
    final pointer = _dragPointer;
    if (scrollable == null || pointer == null || !scrollable.mounted) return 0;
    final box = scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return 0;
    final top = box.localToGlobal(Offset.zero).dy;
    final up =
        SelectionSet.edgeScroll(pointer.dy, top, top + box.size.height, _edge);
    if (up == 0) return 0;
    return scrollable.position.axisDirection == AxisDirection.up ? up : -up;
  }

  void _autoScrollTick() {
    final scrollable = _scrollable;
    final pointer = _dragPointer;
    final delta = _scrollDelta();
    if (scrollable == null || pointer == null || delta == 0) {
      _stopAutoScroll();
      return;
    }
    final position = scrollable.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == position.pixels) return;
    position.jumpTo(target);
    // Rows moved under a still pointer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_dragOrder != null) dragUpdate(pointer);
    });
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragPointer = null;
  }

  void copy() {
    final events = tickedEvents();
    final text = SelectionSet.copyText([
      for (final event in events)
        (
          room.getMemberOrFallback(event.senderId).displayName,
          event.plainTextBody
        )
    ]);
    Clipboard.setData(ClipboardData(text: text));
    exit();
  }

  /// Deletes the ticked messages the user may delete, after one
  /// confirmation, one at a time so the homeserver doesn't rate-limit.
  Future<void> delete(BuildContext context) async {
    final t = timeline;
    if (t == null || busy) return;
    if (HiddenMessages.supported(room)) return deleteOrHide(context);

    final events = tickedEvents();
    final deletable = events.where(canDelete).toList();
    if (deletable.isEmpty) return;
    final kept = events.length - deletable.length;

    // Always ask: this is bulk, whatever "ask before deleting" says.
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: messageSelectionDeleteTitle(deletable.length),
      prompt: [
        messageSelectionDeletePrompt,
        if (kept > 0) messageSelectionDeleteKept(kept),
      ].join("\n"),
      confirmationText: CommonStrings.promptDelete,
      cancelText: CommonStrings.promptCancel,
      dangerous: true,
    );
    if (confirmed != true || _disposed || !active) return;

    for (var i = 0; i < deletable.length; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 300));
      progress = messageSelectionDeleting(i + 1, deletable.length);
      _notify();
      try {
        await t.deleteEvent(deletable[i]);
        ticked.remove(deletable[i].eventId);
      } catch (error, trace) {
        Log.onError(error, trace, content: "Failed to delete messages");
        progress = null;
        _afterChange();
        if (context.mounted) {
          AdaptiveDialog.showError(context, error, trace);
        }
        return;
      }
    }

    progress = null;
    exit();
  }

  /// Puts the ticked messages that can be forwarded, oldest first, in one
  /// room's message box as a pending forward and opens that room, like the
  /// message menu's Forward: they go out when the user presses send, with
  /// the forward options (sender name, caption) on the forward bar.
  Future<void> forward(BuildContext context) async {
    if (busy) return;
    final events = forwardableEvents();
    if (events.isEmpty) return;

    final targets = await ForwardMessageDialog.pickRooms(context, room.client);
    if (targets == null || _disposed || !active) return;

    final t = timeline;
    exit();
    PendingForwards.startInAll(
        targets, PendingForward.many(events: events, timeline: t));
  }

  static String messageSelectionRemoving(int current, int total) => Intl.message(
      "Deleting $current of $total…",
      args: [current, total],
      name: "messageSelectionRemoving",
      desc:
          "Selecting several messages: progress while deleting them for everyone");

  static String messageSelectionHidden(int count) => Intl.plural(count,
      one: "1 message hidden for you",
      other: "$count messages hidden for you",
      args: [count],
      name: "messageSelectionHidden",
      desc:
          "Selecting several messages: bar shown after Delete for me hid the messages");

  static String get messageSelectionUndo => Intl.message("Undo",
      name: "messageSelectionUndo",
      desc:
          "Selecting several messages: button that brings back messages Delete for me just hid");

  /// Vommet issue 533: asks whether to delete the ticked messages for
  /// everyone or only for you, Telegram-style. "For everyone" deletes those
  /// you may delete, one at a time, and hides the rest for you; "for me"
  /// hides them all ([HiddenMessages]), with an Undo bar afterwards.
  Future<void> deleteOrHide(BuildContext context) async {
    final t = timeline;
    if (t == null || busy) return;

    final events = hideableEvents();
    if (events.isEmpty) return;
    final deletable = events.where(canDelete).toList();
    final messenger = ScaffoldMessenger.maybeOf(context);

    final choice = await DeleteForDialog.ask(context,
        count: events.length, deletable: deletable.length);
    if (choice == null || _disposed || !active) return;

    if (choice == DeleteFor.everyone) {
      for (var i = 0; i < deletable.length; i++) {
        if (i > 0) await Future.delayed(const Duration(milliseconds: 300));
        progress = messageSelectionRemoving(i + 1, deletable.length);
        _notify();
        try {
          await t.deleteEvent(deletable[i]);
          ticked.remove(deletable[i].eventId);
        } catch (error, trace) {
          Log.onError(error, trace, content: "Failed to delete messages");
          progress = null;
          _afterChange();
          if (context.mounted) {
            AdaptiveDialog.showError(context, error, trace);
          }
          return;
        }
      }
    }

    final deleted = {
      if (choice == DeleteFor.everyone) ...deletable.map((e) => e.eventId)
    };
    final hide = [
      for (final event in events)
        if (!deleted.contains(event.eventId)) event.eventId
    ];
    if (hide.isNotEmpty) {
      try {
        await HiddenMessages.hide(room, hide);
      } catch (error, trace) {
        Log.onError(error, trace, content: "Failed to hide messages");
        progress = null;
        _afterChange();
        if (context.mounted) {
          AdaptiveDialog.showError(context, error, trace);
        }
        return;
      }
    }

    progress = null;
    exit();
    if (choice == DeleteFor.me) {
      messenger?.showSnackBar(SnackBar(
        content: Text(messageSelectionHidden(hide.length)),
        action: SnackBarAction(
            label: messageSelectionUndo,
            onPressed: () => HiddenMessages.unhide(room, hide)),
      ));
    }
  }
}

/// Hands a room view's [MessageSelection] down to its timeline rows.
class MessageSelectionScope extends InheritedWidget {
  const MessageSelectionScope(
      {required this.selection, required super.child, super.key});

  final MessageSelection selection;

  /// The selection is the same object for the room view's whole life, so
  /// this doesn't make [context] depend on the scope; listen to it instead.
  static MessageSelection? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MessageSelectionScope>()?.selection;

  @override
  bool updateShouldNotify(MessageSelectionScope oldWidget) =>
      selection != oldWidget.selection;
}
