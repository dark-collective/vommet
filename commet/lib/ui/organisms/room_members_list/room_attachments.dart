import 'dart:async';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/image_clipboard.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum RoomAttachmentKind { media, files }

typedef RoomAttachment = (TimelineEventMessage, FileAttachment);

/// Vommet: a room's attachments for the member panel's Media and Files tabs,
/// newest first. They come from the room's timeline, which is decrypted, so
/// encrypted rooms work too; older history loads on demand.
class RoomAttachmentFeed extends ChangeNotifier {
  RoomAttachmentFeed(this.room);

  final Room room;
  Timeline? _timeline;
  StreamSubscription? _added;

  final List<RoomAttachment> media = [];
  final List<RoomAttachment> files = [];
  bool loading = false;
  bool reachedStart = false;
  bool _disposed = false;

  List<RoomAttachment> of(RoomAttachmentKind kind) =>
      kind == RoomAttachmentKind.media ? media : files;

  Future<void> start() async {
    _timeline = room.timeline ?? await room.getTimeline();
    if (_disposed) return;
    _added = _timeline!.onEventAdded.stream.listen((_) => _scan());
    _scan();
  }

  void _scan() {
    final timeline = _timeline;
    if (timeline == null || _disposed) return;
    media.clear();
    files.clear();
    for (final event in timeline.events) {
      if (event is! TimelineEventMessage) continue;
      if (timeline.isEventRedacted(event)) continue;
      for (final attachment in event.attachments ?? const <Attachment>[]) {
        if (attachment is ImageAttachment || attachment is VideoAttachment) {
          media.add((event, attachment as FileAttachment));
        } else if (attachment is FileAttachment) {
          files.add((event, attachment));
        }
      }
    }
    notifyListeners();
  }

  /// Loads older history until [want] more attachments of [kind] turn up, a
  /// few pages at most per call, or the start of the room is reached.
  Future<void> loadOlder(RoomAttachmentKind kind,
      {int want = 24, int maxPages = 6}) async {
    final timeline = _timeline;
    if (timeline == null || loading || reachedStart || _disposed) return;
    loading = true;
    notifyListeners();
    final before = of(kind).length;
    try {
      for (var page = 0; page < maxPages; page++) {
        if (!timeline.canLoadHistory) {
          reachedStart = true;
          break;
        }
        await timeline.loadMoreHistory();
        if (_disposed) return;
        _scan();
        if (of(kind).length - before >= want) break;
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _added?.cancel();
    super.dispose();
  }
}

void _jumpTo(TimelineEventMessage event) {
  EventBus.jumpToEvent.add(event.eventId);
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
            final room =
                await ForwardMessageDialog.pick(context, feed.room.client);
            if (room != null) {
              PendingForwards.startIn(room,
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

/// The end of a Media or Files list: loads older history when it comes into
/// view, and says what's happening.
class RoomAttachmentsFooter extends StatelessWidget {
  const RoomAttachmentsFooter(this.feed, this.kind, {super.key});
  final RoomAttachmentFeed feed;
  final RoomAttachmentKind kind;

  @override
  Widget build(BuildContext context) {
    if (!feed.loading && !feed.reachedStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => feed.loadOlder(kind));
    }
    final empty = feed.of(kind).isEmpty;
    final text = feed.loading || !feed.reachedStart
        ? "Looking through older messages…"
        : empty
            ? (kind == RoomAttachmentKind.media
                ? "No pictures or videos in this room yet"
                : "No files in this room yet")
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

/// Media: a grid of thumbnails. Click opens it full size; right-click or a
/// long press opens a menu (jump to the message, forward, save, copy).
class RoomMediaGrid extends StatelessWidget {
  const RoomMediaGrid(this.feed, {super.key});
  final RoomAttachmentFeed feed;

  @override
  Widget build(BuildContext context) {
    final items = feed.media;
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 110, mainAxisSpacing: 4, crossAxisSpacing: 4),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (event, attachment) = items[index];
        final video = attachment is VideoAttachment ? attachment : null;
        final preview =
            attachment is ImageAttachment ? attachment.image : video?.thumbnail;
        void open() {
          if (attachment is ImageAttachment) {
            Lightbox.show(context, image: attachment.image);
          } else if (video != null) {
            Lightbox.show(context,
                video: video.file,
                thumbnail: video.thumbnail,
                aspectRatio: video.aspectRatio);
          }
        }

        return Tooltip(
          message: attachment.name ?? "",
          waitDuration: const Duration(seconds: 1),
          child: AdaptiveContextMenu(
            items: _attachmentMenu(context, feed, event, attachment),
            child: GestureDetector(
              onTap: open,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh),
                    if (preview != null)
                      Image(
                        image: preview,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    if (video != null)
                      const Center(
                        child: Icon(Icons.play_circle_fill,
                            size: 32,
                            color: Colors.white,
                            shadows: [
                              BoxShadow(blurRadius: 6, color: Colors.black54)
                            ]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Files: one row per file with its size and date. Click jumps to the
/// message; right-click or a long press opens the same menu as Media.
class RoomFilesList extends StatelessWidget {
  const RoomFilesList(this.feed, {super.key});
  final RoomAttachmentFeed feed;

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
    final items = feed.files;
    final scheme = Theme.of(context).colorScheme;
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (event, attachment) = items[index];
        final detail = [
          _size(attachment.fileSize),
          DateFormat.yMMMd().format(event.originServerTs),
        ].where((s) => s.isNotEmpty).join(" · ");
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: AdaptiveContextMenu(
            items: _attachmentMenu(context, feed, event, attachment),
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
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
              ),
            ),
          ),
        );
      },
    );
  }
}
