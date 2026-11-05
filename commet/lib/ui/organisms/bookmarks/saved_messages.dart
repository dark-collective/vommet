import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_view_single.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/bookmarks/saved_message_events.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages_account.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: your saved messages from every room on this account, newest
/// first, filtered by room, tag and media type. Tapping one opens its room
/// at the message.
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

  static String get savedChecking => Intl.message(
        'Checking saved messages…',
        name: 'savedChecking',
        desc: 'Saved media filter is checking event types',
      );
  static String savedCheckMore(int count) => Intl.message(
        'Check $count more',
        args: [count],
        name: 'savedCheckMore',
        desc: 'Check the next bounded batch of saved event types',
      );
  static String get savedRetryUnavailable => Intl.message(
        'Retry unavailable',
        name: 'savedRetryUnavailable',
        desc: 'Retry up to 24 unavailable saved events',
      );
  static String get savedClearMedia => Intl.message(
        'Clear media filter',
        name: 'savedClearMedia',
        desc: 'Clear only the saved media filter',
      );
  static String get savedAllMedia => Intl.message(
        'Show all media types',
        name: 'savedAllMedia',
        desc: 'Clear saved media filter to inspect unavailable entries',
      );
  static String get savedMoreUnchecked => Intl.message(
        'More saved messages haven’t been checked.',
        name: 'savedMoreUnchecked',
        desc: 'Saved media results are incomplete because more events remain',
      );
  static String get savedSlow => Intl.message(
        'Checking is taking longer than usual. You can clear the media filter while waiting.',
        name: 'savedSlow',
        desc:
            'Saved event requests are slow; do not start additional unbounded requests',
      );
  static String savedProgress(int found, int checked, int total) =>
      Intl.message(
        'Matches: $found · $checked of $total saves checked',
        name: 'savedProgress',
        args: [found, checked, total],
        desc: 'Progress and result count for the current saved filters',
      );
  static String savedUnavailableCount(int count) => Intl.plural(
        count,
        one:
            '1 saved message couldn’t be checked. It may include matching media.',
        other:
            '$count saved messages couldn’t be checked. They may include matching media.',
        name: 'savedUnavailableCount',
        args: [count],
        desc: 'Unavailable saved messages have an unknown media type',
      );
  static String get savedNoPhotos => Intl.message(
        'No saved photos match these filters.',
        name: 'savedNoPhotos',
        desc: 'Confirmed empty Photos filter',
      );
  static String get savedNoVideos => Intl.message(
        'No saved videos match these filters.',
        name: 'savedNoVideos',
        desc: 'Confirmed empty Videos filter',
      );

  static Future<void> show(BuildContext context, Client client) =>
      AdaptiveDialog.show(context,
          title: savedMessagesTitle,
          // Keep long account identities and large text accessible without
          // squeezing the saved list's filters and privacy footer.
          initialHeightMobile: 0.8,
          builder: (context) => SizedBox(
                width: 520,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SavedMessagesAccount(client: client),
                  SavedMessages(client: client),
                ]),
              ));

  @override
  State<SavedMessages> createState() => _SavedMessagesState();
}

class _SavedMessagesState extends State<SavedMessages> {
  String? tag;
  String? roomId;
  List<Bookmark> items = const [];
  RoomAttachmentFilter? media;
  late final SavedMessageEvents events;
  StreamSubscription<matrix.SyncUpdate>? sync;

  List<Bookmark> get candidates => items
      .where(
        (b) =>
            (tag == null || b.tags.contains(tag)) &&
            (roomId == null || b.roomId == roomId),
      )
      .toList();

  void filtersChanged() => events.configure(candidates, media: media != null);
  void refresh() {
    if (mounted) setState(() {});
  }

  void onSync(matrix.SyncUpdate update) {
    for (final id in update.rooms?.leave?.keys ?? const <String>[]) {
      events.roomUnavailable(items.where((b) => b.roomId == id));
    }

    for (final room
        in (update.rooms?.join ?? <String, matrix.JoinedRoomUpdate>{})
            .entries) {
      for (final event
          in room.value.timeline?.events ?? <matrix.MatrixEvent>[]) {
        if (event.type != matrix.EventTypes.Redaction) continue;
        final json = event.toJson();
        final target = json['redacts'] ?? event.content['redacts'];
        if (target is String &&
            items.any((b) => b.roomId == room.key && b.eventId == target)) {
          events.redacted(room.key, target);
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    events = SavedMessageEvents(
      (b) async => widget.client.getRoom(b.roomId)?.getEvent(b.eventId),
    );
    events.addListener(refresh);
    load();
    Bookmarks.changed.addListener(load);
    final client = widget.client;
    if (client is MatrixClient)
      sync = client.matrixClient.onSync.stream.listen(onSync);
  }

  @override
  void dispose() {
    Bookmarks.changed.removeListener(load);
    sync?.cancel();
    events.removeListener(refresh);
    events.dispose();
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
      events.retain(items);
      filtersChanged();
    });
  }

  String roomLabel(String id) {
    final name = widget.client.getRoom(id)?.displayName;
    return name == null || name.trim().isEmpty ? id : name;
  }

  @override
  Widget build(BuildContext context) {
    final tags = Bookmarks.tagsOf(items);
    final rooms = items.map((b) => b.roomId).toSet().toList()
      ..sort((a, b) {
        final order = roomLabel(
          a,
        ).toLowerCase().compareTo(roomLabel(b).toLowerCase());
        return order == 0 ? a.compareTo(b) : order;
      });
    final scoped = candidates;
    final shown = media == null
        ? scoped
        : scoped
            .where((b) => savedMediaMatches(events.event(b), media!))
            .toList();
    final height = MediaQuery.of(context).size.height;

    return SizedBox(
      width: 520,
      height: height * 0.7,
      child: CustomScrollView(
        key: const ValueKey('saved-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rooms.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                    child: Row(
                      spacing: 6,
                      children: [
                        PopupMenuButton<String>(
                          key: const ValueKey("saved-room-filter"),
                          tooltip: SavedMessages.savedRoomsFilter,
                          initialValue: roomId,
                          onSelected: (id) => setState(() {
                            roomId =
                                items.any((b) => b.roomId == id) ? id : null;
                            filtersChanged();
                          }),
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
                                  child: Text(
                                    roomLabel(id),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                          child: SizedBox(
                            height: 48,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.forum_outlined, size: 18),
                                  const SizedBox(width: 6),
                                  Text(SavedMessages.savedRoomsFilter),
                                  const Icon(Icons.arrow_drop_down, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (roomId != null)
                          Flexible(
                            child: InputChip(
                              key: const ValueKey("saved-room-active"),
                              selected: true,
                              showCheckmark: false,
                              label: Text(
                                roomLabel(roomId!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              deleteButtonTooltipMessage:
                                  SavedMessages.clearSavedRoomFilter,
                              deleteIcon: const Icon(
                                Icons.close,
                                key: ValueKey("saved-room-clear"),
                                size: 18,
                              ),
                              onDeleted: () => setState(() {
                                roomId = null;
                                filtersChanged();
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final filter in [
                        RoomAttachmentFilter.photos,
                        RoomAttachmentFilter.videos,
                      ])
                        ChoiceChip(
                          key: ValueKey('saved-media-${filter.name}'),
                          mouseCursor: WidgetStateMouseCursor.clickable,
                          label: Text(filter.label),
                          selected: media == filter,
                          showCheckmark: false,
                          shape: const StadiumBorder(),
                          side: BorderSide.none,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          color: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHigh,
                          ),
                          labelStyle: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: media == filter
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                          onSelected: (_) => setState(() {
                            media = media == filter ? null : filter;
                            filtersChanged();
                          }),
                        ),
                    ],
                  ),
                ),
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          key: const ValueKey("saved-tag-all"),
                          label: Text(SavedMessages.labelAllSaved),
                          selected: tag == null,
                          onSelected: (_) => setState(() {
                            tag = null;
                            filtersChanged();
                          }),
                        ),
                        for (final t in tags)
                          ChoiceChip(
                            key: ValueKey("saved-tag-$t"),
                            label: Text("#$t"),
                            selected: tag == t,
                            onSelected: (_) => setState(() {
                              tag = tag == t ? null : t;
                              filtersChanged();
                            }),
                          ),
                      ],
                    ),
                  ),
                if (media != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Semantics(
                      liveRegion: !events.busy,
                      child: Text(
                        SavedMessages.savedProgress(
                          shown.length,
                          events.checkedCount,
                          scoped.length,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (media == null && shown.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: tiamat.Text.labelLow(
                  items.isEmpty
                      ? SavedMessages.labelNoSavedMessages
                      : SavedMessages.labelNoMatchingSaved,
                ),
              ),
            ),
          SliverList.builder(
            itemCount: shown.length,
            itemBuilder: (context, index) => entry(shown[index]),
          ),
          if (media != null)
            SliverToBoxAdapter(child: mediaStatus(shown.length)),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: tiamat.Text.labelLow(
                          SavedMessages.labelSavedPrivacy,
                        ),
                      ),
                    ],
                  ),
                )),
          ),
        ],
      ),
    );
  }

  void clearMedia() => setState(() {
        media = null;
        filtersChanged();
      });

  Widget mediaStatus(int found) => Padding(
        key: const ValueKey('saved-media-status'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (events.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                events.slow
                    ? SavedMessages.savedSlow
                    : SavedMessages.savedChecking,
              ),
            ],
            if (events.remaining > 0) ...[
              const SizedBox(height: 8),
              Text(SavedMessages.savedMoreUnchecked),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('saved-media-more'),
                  onPressed: events.busy ? null : () => setState(events.more),
                  child: Text(SavedMessages.savedCheckMore(
                      events.remaining < SavedMessageEvents.batchSize
                          ? events.remaining
                          : SavedMessageEvents.batchSize)),
                ),
              ),
            ],
            if (events.unavailableCount > 0) ...[
              const SizedBox(height: 8),
              if (found == 0)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Icon(Icons.cloud_off_outlined, size: 32)),
              Text(SavedMessages.savedUnavailableCount(events.unavailableCount),
                  textAlign: found == 0 ? TextAlign.center : TextAlign.start),
              Wrap(
                spacing: 8,
                alignment:
                    found == 0 ? WrapAlignment.center : WrapAlignment.start,
                children: [
                  TextButton(
                    key: const ValueKey('saved-media-retry'),
                    onPressed:
                        events.busy ? null : () => setState(events.retry),
                    child: Text(SavedMessages.savedRetryUnavailable),
                  ),
                  TextButton(
                    onPressed: clearMedia,
                    child: Text(SavedMessages.savedAllMedia),
                  ),
                ],
              ),
            ],
            if (found == 0 &&
                !events.busy &&
                events.remaining == 0 &&
                events.unavailableCount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(children: [
                  Icon(
                      media == RoomAttachmentFilter.photos
                          ? Icons.photo_outlined
                          : Icons.videocam_outlined,
                      size: 32),
                  const SizedBox(height: 12),
                  Text(
                    items.isEmpty
                        ? SavedMessages.labelNoSavedMessages
                        : (media == RoomAttachmentFilter.photos
                            ? SavedMessages.savedNoPhotos
                            : SavedMessages.savedNoVideos),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            if (media != null && events.unavailableCount == 0)
              Align(
                alignment: found == 0 ? Alignment.center : Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('saved-media-clear'),
                  onPressed: clearMedia,
                  child: Text(SavedMessages.savedClearMedia),
                ),
              ),
          ],
        ),
      );

  Widget entry(Bookmark b) {
    if (media == null) events.request(b);
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
                if (!events.checked(b))
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator())
                else if (room != null && events.event(b) != null)
                  IgnorePointer(
                      child: TimelineEventViewSingle(
                          key: ObjectKey(events.event(b)),
                          room: room,
                          event: events.event(b)!))
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
