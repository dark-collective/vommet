import 'package:commet/client/client.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_view_single.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: your saved messages from every room on this account, newest
/// first, filtered by room and tag. Tapping one opens its room at the message.
class SavedMessages extends StatefulWidget {
  const SavedMessages({required this.client, super.key});
  final Client client;

  static String get savedMessagesTitle => Intl.message("Saved messages",
      name: "savedMessagesTitle",
      desc: "Title of the list of messages you bookmarked");

  static String get labelNoSavedMessages => Intl.message(
      "Nothing saved yet. Choose Save message in a message's menu to keep it here.",
      name: "labelNoSavedMessages",
      desc: "Shown in the saved messages list when you haven't saved any");

  static String get labelAllSaved => Intl.message("All",
      name: "labelAllSaved",
      desc: "Filter chip in the saved messages list that shows every tag");

  static String get savedRoomsFilter => Intl.message("Rooms",
      name: "savedRoomsFilter",
      desc: "Button that filters saved messages by the room they came from");

  static String get clearSavedRoomFilter => Intl.message("Clear room filter",
      name: "clearSavedRoomFilter",
      desc: "Tooltip of the X that clears the saved messages room filter");

  static String get labelNoMatchingSaved => Intl.message(
      "No saved messages match these filters.",
      name: "labelNoMatchingSaved",
      desc: "Empty saved messages list when room and tag filters match none");

  static String get labelSavedUnavailable =>
      Intl.message("This message can't be loaded (you may have left the room)",
          name: "labelSavedUnavailable",
          desc: "Shown in the saved messages list for a message that can't be "
              "loaded");

  static String get labelSavedPrivacy => Intl.message(
      "Only you see your saved messages. They sync to your other devices "
      "through your homeserver, which can read the tags and notes.",
      name: "labelSavedPrivacy",
      desc: "Note under the saved messages list about who can see them");

  static Future<void> show(BuildContext context, Client client) =>
      AdaptiveDialog.show(context,
          title: savedMessagesTitle,
          scrollable: false,
          initialHeightMobile: 0.8,
          builder: (context) => SavedMessages(client: client));

  @override
  State<SavedMessages> createState() => _SavedMessagesState();
}

class _SavedMessagesState extends State<SavedMessages> {
  String? tag;
  String? roomId;
  List<Bookmark> items = const [];
  final Map<String, Future<TimelineEvent?>> events = {};

  @override
  void initState() {
    super.initState();
    load();
    Bookmarks.changed.addListener(load);
  }

  @override
  void dispose() {
    Bookmarks.changed.removeListener(load);
    super.dispose();
  }

  void load() {
    if (!mounted) return;
    setState(() {
      items = Bookmarks.of(widget.client);
      if (tag != null && !items.any((b) => b.tags.contains(tag))) tag = null;
      if (roomId != null && !items.any((b) => b.roomId == roomId)) {
        roomId = null;
      }
    });
  }

  String roomLabel(String id) {
    final name = widget.client.getRoom(id)?.displayName;
    return name == null || name.trim().isEmpty ? id : name;
  }

  Future<TimelineEvent?> eventOf(Bookmark b) =>
      events.putIfAbsent("${b.roomId}\n${b.eventId}", () async {
        final room = widget.client.getRoom(b.roomId);
        if (room == null) return null;
        try {
          return await room.getEvent(b.eventId);
        } catch (_) {
          return null;
        }
      });

  @override
  Widget build(BuildContext context) {
    final tags = Bookmarks.tagsOf(items);
    final rooms = items.map((b) => b.roomId).toSet().toList()
      ..sort((a, b) {
        final order =
            roomLabel(a).toLowerCase().compareTo(roomLabel(b).toLowerCase());
        return order == 0 ? a.compareTo(b) : order;
      });
    final shown = items
        .where((b) =>
            (tag == null || b.tags.contains(tag)) &&
            (roomId == null || b.roomId == roomId))
        .toList();
    final height = MediaQuery.of(context).size.height;

    return SizedBox(
      width: 520,
      height: height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rooms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Row(spacing: 6, children: [
                PopupMenuButton<String>(
                  key: const ValueKey("saved-room-filter"),
                  tooltip: SavedMessages.savedRoomsFilter,
                  initialValue: roomId,
                  onSelected: (id) => setState(() =>
                      roomId = items.any((b) => b.roomId == id) ? id : null),
                  itemBuilder: (_) => [
                    for (final id in rooms)
                      CheckedPopupMenuItem(
                        key: ValueKey("saved-room-option-$id"),
                        value: id,
                        checked: roomId == id,
                        child: Tooltip(
                          message: roomLabel(id) == id
                              ? id
                              : "${roomLabel(id)}\n$id",
                          child: Text(roomLabel(id),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ],
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.forum_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text(SavedMessages.savedRoomsFilter),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ]),
                    ),
                  ),
                ),
                if (roomId != null)
                  Flexible(
                    child: InputChip(
                      key: const ValueKey("saved-room-active"),
                      selected: true,
                      showCheckmark: false,
                      label: Text(roomLabel(roomId!),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      deleteButtonTooltipMessage:
                          SavedMessages.clearSavedRoomFilter,
                      deleteIcon: const Icon(Icons.close,
                          key: ValueKey("saved-room-clear"), size: 18),
                      onDeleted: () => setState(() => roomId = null),
                    ),
                  ),
              ]),
            ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                ChoiceChip(
                  key: const ValueKey("saved-tag-all"),
                  label: Text(SavedMessages.labelAllSaved),
                  selected: tag == null,
                  onSelected: (_) => setState(() => tag = null),
                ),
                for (final t in tags)
                  ChoiceChip(
                    key: ValueKey("saved-tag-$t"),
                    label: Text("#$t"),
                    selected: tag == t,
                    onSelected: (_) =>
                        setState(() => tag = tag == t ? null : t),
                  ),
              ]),
            ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: tiamat.Text.labelLow(items.isEmpty
                        ? SavedMessages.labelNoSavedMessages
                        : SavedMessages.labelNoMatchingSaved),
                  ))
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [for (final b in shown) entry(b)],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(children: [
              Icon(Icons.lock_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                  child: tiamat.Text.labelLow(SavedMessages.labelSavedPrivacy)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget entry(Bookmark b) {
    final room = widget.client.getRoom(b.roomId);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey("saved-${b.eventId}"),
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: room == null
              ? null
              : () {
                  Navigator.of(context).maybePop();
                  EventBus.doOpenRoom(b.roomId,
                      clientId: widget.client.identifier, eventId: b.eventId);
                },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.tag, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                      child: tiamat.Text.labelEmphasised(roomLabel(b.roomId))),
                  IconButton(
                    key: ValueKey("saved-edit-${b.eventId}"),
                    tooltip: BookmarkTagEditor.savedMessageTagsTitle,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.sell_outlined),
                    onPressed: () => BookmarkTagEditor.show(
                        context, widget.client, b.roomId, b.eventId),
                  ),
                  IconButton(
                    key: ValueKey("saved-remove-${b.eventId}"),
                    tooltip: BookmarkTagEditor.promptRemoveFromSavedList,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Bookmarks.remove(widget.client, b.roomId, b.eventId),
                  ),
                ]),
                if (room != null)
                  FutureBuilder<TimelineEvent?>(
                    future: eventOf(b),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: LinearProgressIndicator(),
                        );
                      }
                      final event = snap.data;
                      if (event == null) return unavailable();
                      return IgnorePointer(
                          child: TimelineEventViewSingle(
                              room: room, event: event));
                    },
                  )
                else
                  unavailable(),
                if (b.note != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: tiamat.Text.label(b.note!),
                  ),
                if (b.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Wrap(spacing: 6, children: [
                      for (final t in b.tags) tiamat.Text.labelLow("#$t"),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget unavailable() => Padding(
        padding: const EdgeInsets.all(8),
        child: tiamat.Text.labelLow(SavedMessages.labelSavedUnavailable),
      );
}

/// Vommet: pick tags (and a note) for a saved message. With [saveNow] the
/// message is saved straight away, so closing this keeps it untagged.
class BookmarkTagEditor extends StatefulWidget {
  const BookmarkTagEditor(
      {required this.client,
      required this.roomId,
      required this.eventId,
      super.key});
  final Client client;
  final String roomId;
  final String eventId;

  static String get savedMessageTagsTitle => Intl.message("Saved message tags",
      name: "savedMessageTagsTitle",
      desc: "Title of the dialog to tag a saved message");

  static String get labelSavedToast => Intl.message(
      "Saved. Add tags if you like.",
      name: "labelSavedToast",
      desc: "Shown at the top of the tag dialog right after saving a message");

  static String get placeholderNewTag => Intl.message("New tag",
      name: "placeholderNewTag",
      desc: "Placeholder of the field to add a tag to a saved message");

  static String get placeholderSavedNote => Intl.message("Note (optional)",
      name: "placeholderSavedNote",
      desc: "Placeholder of the field to add a note to a saved message");

  static String get promptSavedTagsDone => Intl.message("Done",
      name: "promptSavedTagsDone",
      desc: "Button that closes the saved message tag dialog");

  static String get promptRemoveFromSavedList =>
      Intl.message("Remove from saved",
          name: "promptRemoveFromSavedList",
          desc: "Button to remove a message from your saved messages");

  static Future<void> show(
      BuildContext context, Client client, String roomId, String eventId,
      {bool saveNow = false}) async {
    if (saveNow && !Bookmarks.isSaved(client, roomId, eventId)) {
      await Bookmarks.save(client, roomId, eventId);
    }
    if (!context.mounted) return;
    await AdaptiveDialog.show(context,
        title: savedMessageTagsTitle,
        builder: (context) => BookmarkTagEditor(
            client: client, roomId: roomId, eventId: eventId));
  }

  @override
  State<BookmarkTagEditor> createState() => _BookmarkTagEditorState();
}

class _BookmarkTagEditorState extends State<BookmarkTagEditor> {
  late List<String> tags;
  late List<String> known;
  final newTag = TextEditingController();
  late final TextEditingController note;
  bool justSaved = false;

  @override
  void initState() {
    super.initState();
    final b = Bookmarks.find(widget.client, widget.roomId, widget.eventId);
    tags = [...?b?.tags];
    note = TextEditingController(text: b?.note ?? "");
    known = Bookmarks.allTags(widget.client);
    justSaved = b != null &&
        b.tags.isEmpty &&
        DateTime.now().millisecondsSinceEpoch - b.savedTs < 5000;
  }

  @override
  void dispose() {
    newTag.dispose();
    note.dispose();
    super.dispose();
  }

  void addTag(String value) {
    final cleaned = Bookmarks.cleanTags([value]);
    if (cleaned.isEmpty) return;
    setState(() {
      if (!tags.contains(cleaned.first)) tags.add(cleaned.first);
      if (!known.contains(cleaned.first)) known.add(cleaned.first);
      newTag.clear();
    });
  }

  Future<void> commit() async {
    if (newTag.text.trim().isNotEmpty) addTag(newTag.text);
    await Bookmarks.save(widget.client, widget.roomId, widget.eventId,
        tags: tags, note: note.text);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (justSaved)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(children: [
                Icon(Icons.bookmark_added,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                    child:
                        tiamat.Text.label(BookmarkTagEditor.labelSavedToast)),
              ]),
            ),
          if (known.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in known)
                  FilterChip(
                    key: ValueKey("bookmark-tag-$t"),
                    label: Text("#$t"),
                    selected: tags.contains(t),
                    onSelected: (on) => setState(() {
                      if (on) {
                        tags.add(t);
                      } else {
                        tags.remove(t);
                      }
                    }),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: TextField(
              key: const ValueKey("bookmark-new-tag"),
              controller: newTag,
              maxLength: Bookmarks.maxTagLength,
              decoration: InputDecoration(
                hintText: BookmarkTagEditor.placeholderNewTag,
                prefixText: "#",
                counterText: "",
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => addTag(newTag.text),
                ),
              ),
              onSubmitted: addTag,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: TextField(
              key: const ValueKey("bookmark-note"),
              controller: note,
              maxLines: 3,
              minLines: 1,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: BookmarkTagEditor.placeholderSavedNote,
                counterText: "",
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: tiamat.Text.labelLow(SavedMessages.labelSavedPrivacy),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            tiamat.Button.secondary(
              text: BookmarkTagEditor.promptRemoveFromSavedList,
              onTap: () async {
                await Bookmarks.remove(
                    widget.client, widget.roomId, widget.eventId);
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(width: 8),
            tiamat.Button(
                text: BookmarkTagEditor.promptSavedTagsDone, onTap: commit),
          ]),
        ],
      ),
    );
  }
}
