import 'package:commet/ui/atoms/clickable_gesture_detector.dart';
import 'dart:async';

import 'package:collection/collection.dart' show mergeSort;
import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/room_media_history/room_media_history_component.dart';
import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/ui/atoms/media_spoiler_cover.dart';
import 'package:commet/utils/media_spoiler.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/ui/molecules/voice_message/voice_message_player.dart';
import 'package:commet/ui/organisms/forward_message/forward_from_viewer.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/image_clipboard.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum RoomAttachmentKind { media, files, links }

/// Vommet: the chips over the Media (All, Photos, Videos, GIFs) and Files
/// (All, Files, Voice) tabs.
enum RoomAttachmentFilter {
  all,
  photos,
  videos,
  gifs,
  files,
  voice;

  static List<RoomAttachmentFilter> of(RoomAttachmentKind kind) =>
      switch (kind) {
        RoomAttachmentKind.media => const [all, photos, videos, gifs],
        RoomAttachmentKind.files => const [all, files, voice],
        RoomAttachmentKind.links => const [],
      };

  bool matches(FileAttachment attachment) => switch (this) {
        all => true,
        photos => attachment is ImageAttachment && !isGif(attachment),
        videos => attachment is VideoAttachment && !isGif(attachment),
        gifs => isGif(attachment),
        files => !isVoice(attachment),
        voice => isVoice(attachment),
      };

  /// A GIF: a picture of type image/gif (the GIF picker sends these), or a
  /// short silent video bridges mark as a GIF.
  static bool isGif(FileAttachment attachment) =>
      (attachment is ImageAttachment && attachment.mimeType == "image/gif") ||
      (attachment is VideoAttachment && attachment.isGif);

  /// A voice message (MSC3245), not just any audio file.
  static bool isVoice(FileAttachment attachment) =>
      attachment is AudioAttachment && attachment.isVoice;

  static String get roomAttachmentFilterAll => Intl.message("All",
      name: "roomAttachmentFilterAll",
      desc: "Room side panel: chip over the Media or Files tab showing "
          "everything; keep short");

  static String get roomAttachmentFilterPhotos => Intl.message("Photos",
      name: "roomAttachmentFilterPhotos",
      desc: "Room side panel: chip over the Media tab showing only pictures; "
          "keep short");

  static String get roomAttachmentFilterVideos => Intl.message("Videos",
      name: "roomAttachmentFilterVideos",
      desc: "Room side panel: chip over the Media tab showing only videos; "
          "keep short");

  static String get roomAttachmentFilterGifs => Intl.message("GIFs",
      name: "roomAttachmentFilterGifs",
      desc: "Room side panel: chip over the Media tab showing only GIFs; "
          "keep short");

  static String get roomAttachmentFilterFiles => Intl.message("Files",
      name: "roomAttachmentFilterFiles",
      desc: "Room side panel: chip over the Files tab showing files but not "
          "voice messages; keep short");

  static String get roomAttachmentFilterVoice => Intl.message("Voice",
      name: "roomAttachmentFilterVoice",
      desc: "Room side panel: chip over the Files tab showing only voice "
          "messages; keep short");

  String get label => switch (this) {
        all => roomAttachmentFilterAll,
        photos => roomAttachmentFilterPhotos,
        videos => roomAttachmentFilterVideos,
        gifs => roomAttachmentFilterGifs,
        files => roomAttachmentFilterFiles,
        voice => roomAttachmentFilterVoice,
      };
}

typedef RoomAttachment = (TimelineEventMessage, FileAttachment);

/// Vommet: a link shared in a message, for the Links tab.
typedef RoomLink = (TimelineEventMessage, Uri);

/// Vommet: a room's attachments and links for the member panel's Media,
/// Files and Links tabs, newest first. They come from the room's timeline,
/// which is decrypted, so encrypted rooms work too; older history loads on
/// demand. Older Media and Files come from [RoomMediaHistoryComponent]
/// instead where it is available: the server's filtered history in an
/// unencrypted room, the encrypted search index in an encrypted one (only
/// messages with a file, many per page, without paging the timeline).
class RoomAttachmentFeed extends ChangeNotifier {
  RoomAttachmentFeed(this.room);

  final Room room;
  Timeline? _timeline;

  /// The room timeline the attachments come from, once loaded.
  Timeline? get timeline => _timeline;
  StreamSubscription? _added;

  final List<RoomAttachment> media = [];
  final List<RoomAttachment> files = [];
  final List<RoomLink> links = [];
  bool loading = false;
  bool reachedStart = false;
  bool _disposed = false;

  /// Completes when the load under way ends.
  Completer<void>? _loadDone;

  /// Vommet: waits for a load under way, if any, to end.
  Future<void> whenIdle() => _loadDone?.future ?? Future.value();

  void _startLoading() {
    loading = true;
    _loadDone ??= Completer();
    notifyListeners();
  }

  void _endLoading() {
    final done = _loadDone;
    _loadDone = null;
    if (!_disposed) {
      loading = false;
      notifyListeners();
    }
    done?.complete();
  }

  /// When the oldest loaded message was sent, for "older messages" notes.
  DateTime? oldestLoaded;

  List<RoomAttachment> of(RoomAttachmentKind kind) =>
      kind == RoomAttachmentKind.media ? media : files;

  /// The [kind]'s attachments [filter] lets through.
  List<RoomAttachment> filtered(
          RoomAttachmentKind kind, RoomAttachmentFilter filter) =>
      filter == RoomAttachmentFilter.all
          ? of(kind)
          : of(kind).where((a) => filter.matches(a.$2)).toList();

  int _count(RoomAttachmentKind kind, RoomAttachmentFilter filter) =>
      kind == RoomAttachmentKind.links
          ? links.length
          : filtered(kind, filter).length;

  /// Vommet: pages of messages with a file (server-filtered, or from the
  /// encrypted search index), when the room allows it; null otherwise or
  /// after a page failed (the timeline is paged instead).
  RoomMediaHistoryComponent? _pager;
  String? _pagerFrom;
  bool _pagerReachedStart = false;

  /// Messages from the filtered pages, newest first, by id.
  final Map<String, TimelineEventMessage> _paged = {};

  /// Paged messages deleted since they were loaded.
  final Set<String> _redacted = {};
  StreamSubscription? _redactions;

  /// Whether older Media and Files come from the filtered pages.
  bool get usesFilteredPages => _pager != null;

  /// Whether every [kind] entry is loaded: the filtered pages reached the
  /// start for Media and Files when they're used, else the timeline did.
  bool reachedStartOf(RoomAttachmentKind? kind) =>
      _pager != null && kind != null && kind != RoomAttachmentKind.links
          ? _pagerReachedStart || reachedStart
          : reachedStart;

  Future<void> start() async {
    _timeline = room.timeline ?? await room.getTimeline();
    if (_disposed) return;
    final pager = room.getComponent<RoomMediaHistoryComponent>();
    if (pager != null && pager.available) {
      _pager = pager;
      _redactions = pager.onRedacted.listen((id) {
        if (_paged.containsKey(id) && _redacted.add(id)) _scanSoon();
      });
    }
    // Vommet: onEventAdded fires once per event, synchronously, so a page
    // of history rescanned the whole timeline 30 times over; the rescans
    // grew with the timeline and slowed the Media tab to a crawl. Coalesce
    // them, and leave pages to loadOlder (it scans once per page).
    _added = _timeline!.onEventAdded.stream.listen((_) {
      if (!loading) _scanSoon();
    });
    // A decrypted, edited or removed message changes what the tabs show
    // (a changed message is a new event object, so it is worked out again).
    _changed = _timeline!.onChange.stream.listen((_) => _scanSoon());
    _removed = _timeline!.onRemove.stream.listen((_) => _scanSoon());
    _scan();
  }

  StreamSubscription? _changed;
  StreamSubscription? _removed;
  bool _scanQueued = false;

  /// Vommet: each event's attachments and links, worked out once (finding
  /// links parses the message's HTML).
  final Expando<_EventEntries> _entries = Expando();

  void _scanSoon() {
    if (_scanQueued) return;
    _scanQueued = true;
    scheduleMicrotask(() {
      _scanQueued = false;
      _scan();
    });
  }

  void _scan() {
    final timeline = _timeline;
    if (timeline == null || _disposed) return;
    media.clear();
    files.clear();
    links.clear();
    final inTimeline = <String>{};
    for (final event in timeline.events) {
      oldestLoaded = event.originServerTs;
      if (event is! TimelineEventMessage) continue;
      inTimeline.add(event.eventId);
      if (timeline.isEventRedacted(event)) continue;
      final entries = _entries[event] ??= _EventEntries.of(event, timeline);
      media.addAll(entries.media);
      files.addAll(entries.files);
      links.addAll(entries.links);
    }
    mergePaged(
        media: media,
        files: files,
        paged: _paged.values,
        skip: inTimeline.union(_redacted),
        entriesOf: (event) {
          final entries = _entries[event] ??=
              _EventEntries.of(event, timeline, withLinks: false);
          return (entries.media, entries.files);
        });
    notifyListeners();
  }

  /// Vommet: adds the Media and Files of [paged] messages not in [skip]
  /// (already listed from the timeline, or deleted) to [media] and [files],
  /// keeping both newest first. Links stay the timeline's.
  @visibleForTesting
  static void mergePaged(
      {required List<RoomAttachment> media,
      required List<RoomAttachment> files,
      required Iterable<TimelineEventMessage> paged,
      required Set<String> skip,
      required (List<RoomAttachment>, List<RoomAttachment>) Function(
              TimelineEventMessage event)
          entriesOf}) {
    var added = false;
    for (final event in paged) {
      if (skip.contains(event.eventId)) continue;
      final (eventMedia, eventFiles) = entriesOf(event);
      media.addAll(eventMedia);
      files.addAll(eventFiles);
      added = added || eventMedia.isNotEmpty || eventFiles.isNotEmpty;
    }
    if (!added) return;
    // Stable, so a message's attachments keep their order.
    int newestFirst(RoomAttachment a, RoomAttachment b) =>
        b.$1.originServerTs.compareTo(a.$1.originServerTs);
    mergeSort(media, compare: newestFirst);
    mergeSort(files, compare: newestFirst);
  }

  /// Loads older history until [want] more entries of [kind] (through
  /// [filter]) turn up, a few pages at most per call, or the start of the
  /// room is reached. Without a [kind], just loads [maxPages] pages.
  Future<void> loadOlder(RoomAttachmentKind? kind,
      {RoomAttachmentFilter filter = RoomAttachmentFilter.all,
      int want = 24,
      int maxPages = 6}) async {
    final pager = _pager;
    if (pager != null && kind != null && kind != RoomAttachmentKind.links) {
      return _loadOlderFiltered(pager, kind, filter, want, maxPages);
    }
    final timeline = _timeline;
    if (timeline == null || loading || reachedStart || _disposed) return;
    _startLoading();
    final before = kind == null ? 0 : _count(kind, filter);
    try {
      for (var page = 0; page < maxPages; page++) {
        if (!timeline.canLoadHistory) {
          reachedStart = true;
          break;
        }
        await timeline.loadMoreHistory();
        if (_disposed) return;
        _scan();
        if (kind != null && _count(kind, filter) - before >= want) break;
      }
    } finally {
      _endLoading();
    }
  }

  /// Vommet: [loadOlder] for Media and Files from the filtered pages. A
  /// failed request (a server without the filter) switches this feed back
  /// to paging the timeline.
  Future<void> _loadOlderFiltered(
      RoomMediaHistoryComponent pager,
      RoomAttachmentKind kind,
      RoomAttachmentFilter filter,
      int want,
      int maxPages) async {
    if (loading || reachedStartOf(kind) || _disposed) return;
    _startLoading();
    final before = _count(kind, filter);
    var failed = false;
    try {
      for (var page = 0; page < maxPages; page++) {
        final result = await pager.loadPage(_pagerFrom, limit: filteredPage);
        if (_disposed) return;
        for (final event in result.events) {
          if (event is TimelineEventMessage) _paged[event.eventId] = event;
        }
        _pagerFrom = result.next;
        if (result.next == null) _pagerReachedStart = true;
        _scan();
        if (_pagerReachedStart) break;
        if (_count(kind, filter) - before >= want) break;
      }
    } catch (error) {
      Log.w("Media history pages failed, paging the timeline: $error");
      failed = true;
      _pager = null;
      _redactions?.cancel();
    } finally {
      _endLoading();
    }
    if (failed && !_disposed) {
      await loadOlder(kind, filter: filter, want: want, maxPages: maxPages);
    }
  }

  /// Messages per filtered request.
  static const int filteredPage = 50;

  @override
  void dispose() {
    _disposed = true;
    _redactions?.cancel();
    _added?.cancel();
    _changed?.cancel();
    _removed?.cancel();
    super.dispose();
  }
}

/// Vommet: what one message adds to the Media, Files and Links tabs.
class _EventEntries {
  _EventEntries(this.media, this.files, this.links);

  factory _EventEntries.of(TimelineEventMessage event, Timeline timeline,
      {bool withLinks = true}) {
    final media = <RoomAttachment>[];
    final files = <RoomAttachment>[];
    for (final attachment in event.attachments ?? const <Attachment>[]) {
      if (attachment is ImageAttachment || attachment is VideoAttachment) {
        media.add((event, attachment as FileAttachment));
      } else if (attachment is FileAttachment) {
        files.add((event, attachment));
      }
    }
    final links = [
      if (withLinks)
        for (final uri in event.getLinks(timeline: timeline) ?? const <Uri>[])
          (event, uri)
    ];
    return _EventEntries(media, files, links);
  }

  final List<RoomAttachment> media;
  final List<RoomAttachment> files;
  final List<RoomLink> links;
}

/// Vommet: what the DM Profile tab's "Shared in this chat" rows count.
enum SharedCategory { photosAndVideos, gifs, files, voice, links }

/// A count for one [SharedCategory]: [complete] once the whole chat has
/// been looked through, else at least [count] ("37+").
class SharedCount {
  const SharedCount(this.count, {required this.complete});
  final int count;
  final bool complete;

  @override
  String toString() => complete ? "$count" : "$count+";
}

/// Vommet: where the "Shared in this chat" counts come from. For now the
/// in-memory [RoomAttachmentFeed] (what's loaded so far, paging back while
/// the counts are on screen); meant to be swapped for the encrypted-chat
/// search index once that lands, without touching the UI.
abstract class SharedContentCounts implements Listenable {
  SharedCount count(SharedCategory category);

  /// Whether every category's count is final.
  bool get complete;

  /// Still looking: how far back it has got, for "… so far" notes.
  DateTime? get scannedBackTo;

  /// Asks for more of the chat to be counted (the counts are on screen).
  void countMore();

  void dispose();
}

class FeedSharedContentCounts extends ChangeNotifier
    implements SharedContentCounts {
  FeedSharedContentCounts(this.feed) {
    feed.addListener(notifyListeners);
  }

  final RoomAttachmentFeed feed;

  @override
  SharedCount count(SharedCategory category) {
    final n = switch (category) {
      SharedCategory.photosAndVideos =>
        feed.media.where((a) => !RoomAttachmentFilter.isGif(a.$2)).length,
      SharedCategory.gifs => feed
          .filtered(RoomAttachmentKind.media, RoomAttachmentFilter.gifs)
          .length,
      SharedCategory.files => feed
          .filtered(RoomAttachmentKind.files, RoomAttachmentFilter.files)
          .length,
      SharedCategory.voice => feed
          .filtered(RoomAttachmentKind.files, RoomAttachmentFilter.voice)
          .length,
      SharedCategory.links => feed.links.length,
    };
    return SharedCount(n,
        complete: feed.reachedStartOf(category == SharedCategory.links
            ? RoomAttachmentKind.links
            : RoomAttachmentKind.media));
  }

  @override
  bool get complete =>
      feed.reachedStartOf(RoomAttachmentKind.media) && feed.reachedStart;

  @override
  DateTime? get scannedBackTo => feed.oldestLoaded;

  @override
  void countMore() => !feed.reachedStartOf(RoomAttachmentKind.media)
      // Filtered pages first (the timeline when they aren't used), then
      // the timeline for the links.
      ? feed.loadOlder(RoomAttachmentKind.media, want: 1 << 30, maxPages: 3)
      : feed.loadOlder(null, maxPages: 3);

  @override
  void dispose() {
    feed.removeListener(notifyListeners);
    super.dispose();
  }
}

void _jumpTo(TimelineEventMessage event) => _jumpToEvent(event.eventId);

void _jumpToEvent(String eventId) {
  EventBus.jumpToEvent.add(eventId);
  EventBus.focusTimeline.add(null);
}

String get promptJumpToMessage => Intl.message("Jump to message",
    desc: "Menu option on a picture or file in the room's Media or Files tab "
        "that scrolls the chat to the message it was sent in",
    name: "promptJumpToMessage");

/// Vommet: right-click (desktop) / long-press (phone) menu on a Media or
/// Files entry: jump to the message, forward it, save it, copy the picture.
List<tiamat.ContextMenuItem> _attachmentMenu(
    BuildContext context,
    RoomAttachmentFeed feed,
    TimelineEventMessage event,
    Attachment attachment) {
  return [
    tiamat.ContextMenuItem(
        text: promptJumpToMessage,
        icon: Icons.chat_bubble_outline,
        onPressed: () => _jumpTo(event)),
    if (MatrixForwarding.canForward(event))
      tiamat.ContextMenuItem(
          text: ForwardMessageDialog.promptForwardMessage,
          icon: Icons.shortcut,
          onPressed: () async {
            final rooms =
                await ForwardMessageDialog.pickRooms(context, feed.room.client);
            if (rooms != null) {
              PendingForwards.startInAll(rooms,
                  PendingForward(event: event, timeline: feed.room.timeline));
            }
          }),
    tiamat.ContextMenuItem(
        text: CommonStrings.promptSaveAs,
        icon: Icons.save_alt,
        onPressed: () => DownloadUtils.downloadAttachment(attachment)),
    if (attachment is ImageAttachment && ImageClipboard.supported)
      tiamat.ContextMenuItem(
          text: CommonStrings.promptCopyImage,
          icon: Icons.copy,
          onPressed: () => ImageClipboard.copy(attachment.image)),
  ];
}

/// The end of a Media, Files or Links list: loads older history when it
/// comes into view, and says what's happening.
class RoomAttachmentsFooter extends StatelessWidget {
  const RoomAttachmentsFooter(this.feed, this.kind,
      {this.filter = RoomAttachmentFilter.all, super.key});
  final RoomAttachmentFeed feed;
  final RoomAttachmentKind kind;
  final RoomAttachmentFilter filter;

  static String get roomAttachmentsNoLinks =>
      Intl.message("No links in this room yet",
          name: "roomAttachmentsNoLinks",
          desc: "Room side panel: the Links tab when no message has a link");

  static String get roomAttachmentsNoGifs =>
      Intl.message("No GIFs in this room yet",
          name: "roomAttachmentsNoGifs",
          desc: "Room side panel: the Media tab's GIFs chip finds nothing");

  static String get roomAttachmentsNoVoice =>
      Intl.message("No voice messages in this room yet",
          name: "roomAttachmentsNoVoice",
          desc: "Room side panel: the Files tab's Voice chip finds nothing");

  @override
  Widget build(BuildContext context) {
    // Vommet: not while a picture viewer (or any dialog) covers the panel.
    // The footer stays "visible" behind it, so history kept loading page
    // after page, and each batch made an open gallery re-index and flicker.
    final covered = ModalRoute.of(context)?.isCurrent == false;
    final reachedStart = feed.reachedStartOf(kind);
    if (!feed.loading && !reachedStart && !covered) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => feed.loadOlder(kind, filter: filter));
    }
    final empty = kind == RoomAttachmentKind.links
        ? feed.links.isEmpty
        : feed.filtered(kind, filter).isEmpty;
    final text = feed.loading || !reachedStart
        ? "Looking through older messages…"
        : empty
            ? switch ((kind, filter)) {
                (RoomAttachmentKind.links, _) => roomAttachmentsNoLinks,
                (_, RoomAttachmentFilter.gifs) => roomAttachmentsNoGifs,
                (_, RoomAttachmentFilter.voice) => roomAttachmentsNoVoice,
                (RoomAttachmentKind.media, _) =>
                  "No pictures or videos in this room yet",
                _ => "No files in this room yet",
              }
            : "That's everything";
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          if (feed.loading)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
          Flexible(
            child: Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Vommet: the chips over the Media and Files tabs.
class RoomAttachmentChips extends StatelessWidget {
  const RoomAttachmentChips(
      {required this.kind,
      required this.selected,
      required this.onSelected,
      super.key});
  final RoomAttachmentKind kind;
  final RoomAttachmentFilter selected;
  final ValueChanged<RoomAttachmentFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final filter in RoomAttachmentFilter.of(kind))
            ChoiceChip(
              mouseCursor: WidgetStateMouseCursor.clickable,
              key: ValueKey("room-attachment-chip-${filter.name}"),
              label: Text(filter.label),
              selected: filter == selected,
              showCheckmark: false,
              shape: const StadiumBorder(),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              color: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? scheme.primary
                      : scheme.surfaceContainerHigh),
              labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color:
                      filter == selected ? scheme.onPrimary : scheme.onSurface),
              onSelected: (_) => onSelected(filter),
            ),
        ],
      ),
    );
  }
}

/// Media: a grid of thumbnails. Click opens it full size; right-click or a
/// long press opens a menu (jump to the message, forward, save, copy).
class RoomMediaGrid extends StatelessWidget {
  const RoomMediaGrid(this.feed,
      {this.filter = RoomAttachmentFilter.all, super.key});
  final RoomAttachmentFeed feed;
  final RoomAttachmentFilter filter;

  @override
  Widget build(BuildContext context) {
    final items = feed.filtered(RoomAttachmentKind.media, filter);
    Widget tile(BuildContext context, RoomAttachment item) {
      final (event, attachment) = item;
      final video = attachment is VideoAttachment ? attachment : null;
      final preview =
          attachment is ImageAttachment ? attachment.image : video?.thumbnail;
      // Vommet: decoded at the tile's size, not the timeline's.
      final tilePixels =
          (MediaGridZoom.size * MediaQuery.devicePixelRatioOf(context)).ceil();
      final tileImage =
          preview is LODImageProvider ? preview.forTile(tilePixels) : preview;
      // Vommet: a spoiler (MSC4193) shows a small cover; the first tap
      // reveals it, the next opens it.
      final spoiler = attachment.spoiler;
      void open() {
        if (MediaSpoilerReveal.isHidden(spoiler)) {
          MediaSpoilerReveal.reveal(spoiler!.key);
          return;
        }
        if (attachment is ImageAttachment) {
          Lightbox.show(context,
              image: attachment.image,
              onJumpToMessage: () => _jumpTo(event),
              onForward: forwardFromViewer(feed.room, event));
        } else if (video != null) {
          Lightbox.show(context,
              onJumpToMessage: () => _jumpTo(event),
              onForward: forwardFromViewer(feed.room, event),
              video: video.file,
              thumbnail: video.thumbnail,
              aspectRatio: video.aspectRatio,
              fileName: video.name);
        }
      }

      return Tooltip(
        message: attachment.name ?? "",
        waitDuration: const Duration(seconds: 1),
        child: AdaptiveContextMenu(
          items: _attachmentMenu(context, feed, event, attachment),
          child: ClickableGestureDetector(
            onTap: open,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHigh),
                  MediaSpoilerBuilder(
                    spoiler: spoiler,
                    builder: (context, hidden) => hidden
                        ? IgnorePointer(
                            child: MediaSpoilerCover(
                                spoiler: spoiler!,
                                blurhash: spoilerBlurhashOf(preview),
                                compact: true),
                          )
                        : Stack(fit: StackFit.expand, children: [
                            if (tileImage != null)
                              Image(
                                image: tileImage,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            if (video != null)
                              const Center(
                                child: Icon(Icons.play_circle_fill,
                                    size: 32,
                                    color: Colors.white,
                                    shadows: [
                                      BoxShadow(
                                          blurRadius: 6, color: Colors.black54)
                                    ]),
                              ),
                          ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Vommet: a full-width header per month, its pictures in a grid under
    // it. The months keep the list's order, so the gallery below (which
    // walks the list) goes tile by tile.
    final grid = SliverMainAxisGroup(slivers: [
      for (final (month, entries)
          in groupByMonth(items, (item) => item.$1.originServerTs)) ...[
        SliverToBoxAdapter(child: RoomMonthHeader(month)),
        SliverGrid.builder(
          // Vommet issue 622: Ctrl + wheel or a pinch resizes the
          // thumbnails (MediaGridZoom).
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: MediaGridZoom.size,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4),
          itemCount: entries.length,
          itemBuilder: (context, index) => tile(context, entries[index]),
        ),
      ],
    ]);
    // Vommet: with the "Picture gallery" experiment, a picture opened from
    // here can be browsed with the arrow keys (or a swipe), like in the chat.
    // It walks this grid's own list (the chip's filter, newest first), not
    // the timeline: pictures paged from the server's filtered history
    // aren't in the timeline, and opened alone.
    return LightboxGalleryScope.source(
        source: RoomMediaGallerySource(feed, filter),
        newestFirst: true,
        onJumpToEvent: _jumpToEvent,
        child: grid);
  }
}

/// Vommet: the gallery over the Media tab's list, through the chip's
/// [filter]; going past its oldest loads older Media ([RoomAttachmentFeed.loadOlder]).
class RoomMediaGallerySource implements LightboxGallerySource {
  RoomMediaGallerySource(this.feed, this.filter);

  final RoomAttachmentFeed feed;
  final RoomAttachmentFilter filter;

  @override
  Room get room => feed.room;

  @override
  List<LightboxGalleryItem> get items => [
        for (final (event, attachment)
            in feed.filtered(RoomAttachmentKind.media, filter).reversed)
          if (attachment is ImageAttachment || attachment is VideoAttachment)
            LightboxGalleryItem(
                event,
                attachment,
                (event.attachments ?? const <Attachment>[])
                    .indexOf(attachment)),
      ];

  @override
  bool get canLoadOlder => !feed.reachedStartOf(RoomAttachmentKind.media);

  @override
  Future<void> loadOlder() async {
    // A load the grid started finds this one's pictures too; wait for it,
    // so the gallery sees what it brought before asking again.
    await feed.whenIdle();
    if (!canLoadOlder) return;
    await feed.loadOlder(RoomAttachmentKind.media, filter: filter);
  }

  @override
  void Function() listen(void Function() onChange) {
    feed.addListener(onChange);
    return () => feed.removeListener(onChange);
  }

  @override
  bool operator ==(Object other) =>
      other is RoomMediaGallerySource &&
      identical(other.feed, feed) &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(identityHashCode(feed), filter);
}

/// The sender's name for a list entry: "You" for your own messages.
String _senderName(Room room, String senderId) {
  if (senderId == room.client.self?.identifier) return roomAttachmentsSenderYou;
  return room.getMemberOrFallback(senderId).displayName;
}

String get roomAttachmentsSenderYou => Intl.message("You",
    name: "roomAttachmentsSenderYou",
    desc: "Room side panel: sender shown on your own files and links in the "
        "Files and Links tabs");

/// "Sender · Oct 19" under a list entry.
String _byline(Room room, TimelineEventMessage event) =>
    "${_senderName(room, event.senderId)} · ${DateFormat.MMMd().format(event.originServerTs)}";

/// Files: one row per file with its size, sender and date. Click jumps to the
/// message; right-click or a long press opens the same menu as Media. Voice
/// messages play in place.
class RoomFilesList extends StatelessWidget {
  const RoomFilesList(this.feed,
      {this.filter = RoomAttachmentFilter.all, super.key});
  final RoomAttachmentFeed feed;
  final RoomAttachmentFilter filter;

  static String _size(int? bytes) {
    if (bytes == null) return "";
    const units = ["B", "KB", "MB", "GB"];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return "${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}";
  }

  @override
  Widget build(BuildContext context) {
    // Vommet: under a header per month, like Links.
    final rows = monthRows(feed.filtered(RoomAttachmentKind.files, filter),
        (item) => item.$1.originServerTs);
    final scheme = Theme.of(context).colorScheme;
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is DateTime) return RoomMonthHeader(row);
        final (event, attachment) = row as RoomAttachment;
        final Widget content;
        if (attachment is AudioAttachment && attachment.isVoice) {
          content = Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: VoiceMessagePlayer(
              key: ValueKey("room-files-voice-${event.eventId}"),
              file: attachment.file,
              duration: attachment.duration,
              waveform: attachment.waveform,
              footer: Text(_byline(feed.room, event),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          );
        } else {
          final detail = [
            _size(attachment.fileSize),
            _byline(feed.room, event),
          ].where((s) => s.isNotEmpty).join(" · ");
          content = InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(8),
            onTap: () => _jumpTo(event),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                spacing: 10,
                children: [
                  Icon(
                      attachment.mimeType?.startsWith("audio/") == true
                          ? Icons.audio_file
                          : Icons.insert_drive_file,
                      color: scheme.primary),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(attachment.name ?? "File",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: AdaptiveContextMenu(
            items: _attachmentMenu(context, feed, event, attachment),
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

/// Vommet: Links: every link shared in the room, newest first, under a
/// header per month. Each shows the link preview's title when there is one,
/// the address, and who sent it when. Click opens the link; right-click or a
/// long press: Copy link, Jump to message.
class RoomLinksList extends StatelessWidget {
  const RoomLinksList(this.feed, {super.key});
  final RoomAttachmentFeed feed;

  static String get roomLinksCopyLink => Intl.message("Copy link",
      name: "roomLinksCopyLink",
      desc: "Menu option on a link in the room's Links tab");

  @override
  Widget build(BuildContext context) {
    // Rows and month headers, in order.
    final rows = monthRows(feed.links, (link) => link.$1.originServerTs);
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is DateTime) return RoomMonthHeader(row);
        final (event, uri) = row as RoomLink;
        return RoomLinkTile(feed: feed, event: event, uri: uri);
      },
    );
  }
}

/// Vommet: newest-first entries grouped under the month they were sent in,
/// in order. Media, Files and Links put a [RoomMonthHeader] over each group.
List<(DateTime, List<T>)> groupByMonth<T>(
    Iterable<T> items, DateTime Function(T) timeOf) {
  final groups = <(DateTime, List<T>)>[];
  for (final item in items) {
    final ts = timeOf(item);
    final last = groups.lastOrNull?.$1;
    if (last == null || ts.year != last.year || ts.month != last.month) {
      groups.add((DateTime(ts.year, ts.month), <T>[]));
    }
    groups.last.$2.add(item);
  }
  return groups;
}

/// [groupByMonth] as one list: each month (a [DateTime]) followed by its
/// entries.
List<Object?> monthRows<T>(Iterable<T> items, DateTime Function(T) timeOf) => [
      for (final (month, entries) in groupByMonth(items, timeOf)) ...[
        month,
        ...entries,
      ],
    ];

/// "OCTOBER 2026" over a month's entries.
class RoomMonthHeader extends StatelessWidget {
  const RoomMonthHeader(this.month, {super.key});
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(DateFormat.yMMMM().format(month).toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class RoomLinkTile extends StatefulWidget {
  const RoomLinkTile(
      {required this.feed, required this.event, required this.uri, super.key});
  final RoomAttachmentFeed feed;
  final TimelineEventMessage event;
  final Uri uri;

  @override
  State<RoomLinkTile> createState() => _RoomLinkTileState();
}

class _RoomLinkTileState extends State<RoomLinkTile> {
  String? title;

  @override
  void initState() {
    super.initState();
    _preview();
  }

  // The link preview's title, only where the chat would show previews (the
  // room's preview setting; encrypted rooms are off unless turned on).
  Future<void> _preview() async {
    final previews =
        widget.feed.room.client.getComponent<UrlPreviewComponent>();
    if (previews == null ||
        !previews.shouldGetPreviewsInRoom(widget.feed.room)) {
      return;
    }
    final data = await previews.getPreviewForUrl(widget.feed.room, widget.uri);
    final t = data?.title?.trim();
    if (mounted && t != null && t.isNotEmpty) setState(() => title = t);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final address =
        widget.uri.toString().replaceFirst(RegExp("^https?://"), "");
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AdaptiveContextMenu(
        items: [
          tiamat.ContextMenuItem(
              text: RoomLinksList.roomLinksCopyLink,
              icon: Icons.link,
              onPressed: () => Clipboard.setData(
                  ClipboardData(text: widget.uri.toString()))),
          tiamat.ContextMenuItem(
              text: promptJumpToMessage,
              icon: Icons.chat_bubble_outline,
              onPressed: () => _jumpTo(widget.event)),
        ],
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(8),
            onTap: () => LinkUtils.open(widget.uri, context: context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                spacing: 10,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.link, color: scheme.onPrimaryContainer),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (title == null
                                    ? text.bodyMedium
                                    : text.bodySmall)
                                ?.copyWith(color: scheme.primary)),
                        Text(_byline(widget.feed.room, widget.event),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
