import 'package:commet/client/client.dart';
import 'package:commet/client/components/hidden_messages/hidden_messages.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/message_selection/delete_for_dialog.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_bar.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/selection_set.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 882: several pictures and videos ticked at once on the room
/// info page's Media view. Right-click › Select (desktop) or a long press
/// (phone) starts it; a tap or click then ticks, Shift+click ticks a range.
/// Ids are event ids; [ordered] gives the grid's order for ranges.
class RoomMediaSelection extends ChangeNotifier {
  RoomMediaSelection(this.feed, {required this.ordered});

  final RoomAttachmentFeed feed;

  /// The ids of the grid's entries, in the grid's order.
  final List<String> Function() ordered;

  final SelectionSet ticked = SelectionSet();
  bool active = false;

  /// "Deleting 2 of 5…" while Delete runs; null otherwise.
  String? progress;

  bool get busy => progress != null;
  bool _disposed = false;

  Room get room => feed.room;

  /// Follows the chat's "Select several messages" experiment.
  static bool get enabled => MessageSelection.enabled;

  bool isTicked(String id) => active && ticked.contains(id);

  void start(String id) {
    if (busy) return;
    ticked.clear();
    ticked.toggle([id]);
    active = true;
    _notify();
  }

  void toggle(String id) {
    if (!active || busy) return;
    ticked.toggle([id]);
    _afterChange();
  }

  void tickRange(String id) {
    if (!active || busy) return;
    ticked.tickRange(ordered(), [id]);
    _afterChange();
  }

  void exit() {
    if (!active) return;
    ticked.clear();
    active = false;
    progress = null;
    _notify();
  }

  void _afterChange() {
    if (ticked.isEmpty) return exit();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The ticked entries, in the grid's order (newest first).
  List<RoomAttachment> tickedItems() {
    final seen = <String>{};
    return [
      for (final item in feed.media)
        if (ticked.contains(item.$1.eventId) && seen.add(item.$1.eventId)) item
    ];
  }

  List<TimelineEventMessage> tickedEvents() =>
      [for (final item in tickedItems()) item.$1];

  List<TimelineEventMessage> forwardableEvents() =>
      tickedEvents().where(MatrixForwarding.canForward).toList();

  bool canDelete(TimelineEvent event) =>
      room.timeline?.canDeleteEvent(event) == true &&
      event.status == TimelineEventStatus.synced;

  /// How many ticked entries Delete acts on: with "Delete for me", all of
  /// them; otherwise those you may delete.
  int get deletableCount => HiddenMessages.supported(room)
      ? tickedEvents().length
      : tickedEvents().where(canDelete).length;

  /// Saves the ticked files: on a phone into the gallery, elsewhere into one
  /// picked folder (as a mosaic's "Save all" does).
  Future<void> save(BuildContext context) async {
    if (busy) return;
    final files = [for (final item in tickedItems()) item.$2];
    if (files.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (DownloadUtils.canSaveToGallery) {
      try {
        final saved = await DownloadUtils.saveToGallery(files);
        if (saved == null) {
          messenger?.showSnackBar(
              SnackBar(content: Text(roomMediaGalleryAccessDenied)));
          return;
        }
        exit();
        messenger?.showSnackBar(
            SnackBar(content: Text(roomMediaSavedToGallery(saved))));
      } catch (error, trace) {
        Log.onError(error, trace, content: "Failed to save media to gallery");
        if (context.mounted) AdaptiveDialog.showError(context, error, trace);
      }
      return;
    }
    await DownloadUtils.downloadAttachments(files);
    exit();
  }

  /// Puts the ticked entries, oldest first, in the picked rooms' message
  /// boxes as a pending forward, like the chat's Select › Forward.
  Future<void> forward(BuildContext context) async {
    if (busy) return;
    final events = forwardableEvents().reversed.toList();
    if (events.isEmpty) return;
    final root = navigator.currentContext ?? context;
    final targets = await ForwardMessageDialog.pickRooms(root, room.client);
    if (targets == null || _disposed || !active) return;
    final timeline = room.timeline;
    exit();
    PendingForwards.startInAll(
        targets, PendingForward.many(events: events, timeline: timeline));
  }

  /// Delete for everyone (those you may delete; moderators may delete
  /// anyone's) or Delete for me, as the chat's selection asks; without
  /// hidden messages support, one confirmation and delete for everyone.
  Future<void> delete(BuildContext context) async {
    final timeline = room.timeline;
    if (timeline == null || busy) return;
    final events = tickedEvents();
    if (events.isEmpty) return;
    final deletable = events.where(canDelete).toList();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final canHide = HiddenMessages.supported(room);

    DeleteFor? choice;
    if (canHide) {
      choice = await DeleteForDialog.ask(context,
          count: events.length, deletable: deletable.length);
    } else {
      if (deletable.isEmpty) return;
      final kept = events.length - deletable.length;
      final confirmed = await AdaptiveDialog.confirmation(
        context,
        title: MessageSelection.messageSelectionDeleteTitle(deletable.length),
        prompt: [
          MessageSelection.messageSelectionDeletePrompt,
          if (kept > 0) MessageSelection.messageSelectionDeleteKept(kept),
        ].join("\n"),
        confirmationText: CommonStrings.promptDelete,
        cancelText: CommonStrings.promptCancel,
        dangerous: true,
      );
      if (confirmed == true) choice = DeleteFor.everyone;
    }
    if (choice == null || _disposed || !active) return;

    final deleted = <String>{};
    if (choice == DeleteFor.everyone) {
      for (var i = 0; i < deletable.length; i++) {
        if (i > 0) await Future.delayed(const Duration(milliseconds: 300));
        progress =
            MessageSelection.messageSelectionRemoving(i + 1, deletable.length);
        _notify();
        try {
          await timeline.deleteEvent(deletable[i]);
          deleted.add(deletable[i].eventId);
          ticked.remove(deletable[i].eventId);
        } catch (error, trace) {
          Log.onError(error, trace, content: "Failed to delete media");
          progress = null;
          _afterChange();
          if (context.mounted) AdaptiveDialog.showError(context, error, trace);
          return;
        }
      }
    }

    final hide = canHide
        ? [
            for (final event in events)
              if (!deleted.contains(event.eventId)) event.eventId
          ]
        : const <String>[];
    if (hide.isNotEmpty) {
      try {
        await HiddenMessages.hide(room, hide);
      } catch (error, trace) {
        Log.onError(error, trace, content: "Failed to hide media");
        progress = null;
        _afterChange();
        if (context.mounted) AdaptiveDialog.showError(context, error, trace);
        return;
      }
    }

    progress = null;
    exit();
    if (choice == DeleteFor.me) {
      messenger?.showSnackBar(SnackBar(
        content: Text(MessageSelection.messageSelectionHidden(hide.length)),
        action: SnackBarAction(
            label: MessageSelection.messageSelectionUndo,
            onPressed: () => HiddenMessages.unhide(room, hide)),
      ));
    }
  }

  static String roomMediaSavedToGallery(int count) => Intl.plural(count,
      one: "Saved 1 item to your gallery",
      other: "Saved $count items to your gallery",
      args: [count],
      name: "roomMediaSavedToGallery",
      desc:
          "Room info Media page, selecting several pictures and videos: note after Save put them in the phone's gallery");

  static String get roomMediaGalleryAccessDenied => Intl.message(
      "Vommet needs permission to add to your gallery",
      name: "roomMediaGalleryAccessDenied",
      desc:
          "Room info Media page, selecting several pictures and videos: note when Save was refused access to the phone's gallery");
}

/// Vommet issue 882: stands in for the Media page's title bar while
/// pictures and videos are ticked. Wide: count, Forward N, Save N,
/// Delete N, Cancel; narrow or a phone: ✕, count and icons.
class RoomMediaSelectionBar extends StatelessWidget
    implements PreferredSizeWidget {
  const RoomMediaSelectionBar(this.selection, {super.key});

  final RoomMediaSelection selection;

  static String roomMediaSaveCount(int count) => Intl.message("Save $count",
      args: [count],
      name: "roomMediaSaveCount",
      desc:
          "Room info Media page, selecting several pictures and videos: button that saves the ticked ones; count is how many");

  static String get roomMediaSave => Intl.message("Save",
      name: "roomMediaSave",
      desc:
          "Room info Media page, selecting several pictures and videos: tooltip of the button that saves the ticked ones");

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: ListenableBuilder(
            listenable: selection,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) =>
                  MediaQuery.of(context).mobile || constraints.maxWidth < 520
                      ? _compact(context)
                      : _wide(context),
            ),
          ),
        ),
      ),
    );
  }

  String get _label =>
      selection.progress ??
      MessageSelectionBar.messageSelectionSelected(selection.ticked.length);

  Widget _wide(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = selection.busy;
    final count = selection.tickedItems().length;
    final deletable = selection.deletableCount;
    final forwardable = selection.forwardableEvents().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: CommonStrings.promptCancel,
          onPressed: busy ? null : selection.exit,
        ),
        Expanded(
          child: tiamat.Text.label(_label,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (MatrixForwarding.enabled)
          TextButton.icon(
            icon: const Icon(Icons.shortcut, size: 18),
            label: Text(forwardable > 0
                ? MessageSelectionBar.messageSelectionForwardCount(forwardable)
                : MessageSelectionBar.messageSelectionForward),
            onPressed: busy || forwardable == 0
                ? null
                : () => selection.forward(context),
          ),
        TextButton.icon(
          icon: const Icon(Icons.save_alt, size: 18),
          label: Text(roomMediaSaveCount(count)),
          onPressed: busy || count == 0 ? null : () => selection.save(context),
        ),
        TextButton.icon(
          icon: const Icon(Icons.delete, size: 18),
          label: Text(deletable > 0
              ? MessageSelectionBar.messageSelectionDeleteCount(deletable)
              : CommonStrings.promptDelete),
          style: TextButton.styleFrom(foregroundColor: colors.error),
          onPressed:
              busy || deletable == 0 ? null : () => selection.delete(context),
        ),
      ]),
    );
  }

  Widget _compact(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = selection.busy;
    final items = selection.tickedItems();
    final deletable = selection.deletableCount;
    final forwardable = selection.forwardableEvents().length;
    final one = items.length == 1 ? items.first : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: CommonStrings.promptCancel,
          onPressed: busy ? null : selection.exit,
        ),
        Expanded(
          child: tiamat.Text.label(_label,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (MatrixForwarding.enabled)
          IconButton(
            icon: const Icon(Icons.shortcut),
            tooltip: MessageSelectionBar.messageSelectionForward,
            onPressed: busy || forwardable == 0
                ? null
                : () => selection.forward(context),
          ),
        IconButton(
          icon: const Icon(Icons.save_alt),
          tooltip: roomMediaSave,
          onPressed:
              busy || items.isEmpty ? null : () => selection.save(context),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          tooltip: CommonStrings.promptDelete,
          color: colors.error,
          onPressed:
              busy || deletable == 0 ? null : () => selection.delete(context),
        ),
        // One ticked: what its long-press menu had (jump, copy).
        if (one != null)
          PopupMenuButton<Function>(
            enabled: !busy,
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              for (final item in roomMediaOneItemMenu(selection.feed, one,
                  then: selection.exit))
                PopupMenuItem<Function>(
                    value: item.onPressed,
                    child: Row(children: [
                      Icon(item.icon, size: 20),
                      const SizedBox(width: 12),
                      Text(item.text),
                    ])),
            ],
          ),
      ]),
    );
  }
}
