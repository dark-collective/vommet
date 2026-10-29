import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/hidden_messages/hidden_messages.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/ui/organisms/room_members_list/room_media_selection.dart';
import 'package:commet/ui/organisms/room_pinned_messages/room_pinned_messages_widget.dart';
import 'package:commet/ui/organisms/room_threads_list/room_threads_list_widget.dart';
import 'package:commet/ui/organisms/room_widgets/room_widgets_view.dart';
import 'package:commet/ui/pages/room_info/room_info_rows.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet (New room info page): the side panel's Media, Files, Links,
/// Pinned, Threads, Widgets and Members views, full screen with a title bar.
/// The same widgets as the panel, so neither door is a dead end.

/// Back to the chat (closing Room info, its dialog and anything over it).
void closeRoomInfoToChat(BuildContext context) =>
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);

class RoomAttachmentsPage extends StatefulWidget {
  const RoomAttachmentsPage(
      {required this.room, required this.kind, required this.title, super.key});
  final Room room;
  final RoomAttachmentKind kind;
  final String title;

  @override
  State<RoomAttachmentsPage> createState() => _RoomAttachmentsPageState();
}

class _RoomAttachmentsPageState extends State<RoomAttachmentsPage> {
  late final RoomAttachmentFeed feed;
  final controller = ScrollController();
  RoomAttachmentFilter filter = RoomAttachmentFilter.all;
  StreamSubscription? _thumbnailSizeSub;
  StreamSubscription? _jumpSub;
  StreamSubscription? _openRoomSub;

  /// Vommet issue 882: ticking several pictures and videos (Media only).
  RoomMediaSelection? selection;
  final _selectionFocus = FocusNode();
  bool _wasSelecting = false;

  @override
  void initState() {
    super.initState();
    feed = RoomAttachmentFeed(widget.room)..addListener(_onChanged);
    feed.start();
    if (widget.kind == RoomAttachmentKind.media) {
      selection = RoomMediaSelection(feed,
          ordered: () => feed
              .filtered(RoomAttachmentKind.media, filter)
              .map((e) => e.$1.eventId)
              .toList())
        ..addListener(_onChanged);
    }
    // "Delete for me" hides entries: drop them from the lists.
    if (HiddenMessages.supported(widget.room)) {
      HiddenMessages.changed.addListener(_onChanged);
    }
    _thumbnailSizeSub = preferences.mediaGridThumbnailSize.onChanged
        .listen((_) => _onChanged());
    // A file or link jumps to its message: show the chat.
    _jumpSub = EventBus.jumpToEvent.stream.listen((_) {
      if (mounted) closeRoomInfoToChat(context);
    });
    // Vommet issue 800: Forward opens the target room: show it.
    _openRoomSub = EventBus.openRoom.stream.listen((_) {
      if (mounted) closeRoomInfoToChat(context);
    });
  }

  @override
  void dispose() {
    _thumbnailSizeSub?.cancel();
    _jumpSub?.cancel();
    _openRoomSub?.cancel();
    HiddenMessages.changed.removeListener(_onChanged);
    selection?.removeListener(_onChanged);
    selection?.dispose();
    _selectionFocus.dispose();
    feed.removeListener(_onChanged);
    feed.dispose();
    controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final selecting = selection?.active ?? false;
    // Esc leaves the selection: take the keyboard focus when it starts.
    if (selecting && !_wasSelecting) _selectionFocus.requestFocus();
    _wasSelecting = selecting;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final selection = this.selection;
    final Widget list = switch (kind) {
      RoomAttachmentKind.media =>
        RoomMediaGrid(feed, filter: filter, selection: selection),
      RoomAttachmentKind.files => RoomFilesList(feed, filter: filter),
      RoomAttachmentKind.links => RoomLinksList(feed),
    };
    Widget body = CustomScrollView(
      key: ValueKey("room-info-${kind.name}-${widget.room.localId}"),
      controller: controller,
      physics: kind == RoomAttachmentKind.media
          ? const NoWheelWhileCtrlScrollPhysics()
          : null,
      slivers: [
        if (kind != RoomAttachmentKind.links)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            sliver: SliverToBoxAdapter(
              child: RoomAttachmentChips(
                kind: kind,
                selected: filter,
                onSelected: (value) => setState(() {
                  filter = value;
                  selection?.exit();
                }),
              ),
            ),
          ),
        SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0), sliver: list),
        SliverToBoxAdapter(
          child: RoomAttachmentsFooter(feed, kind, filter: filter),
        ),
      ],
    );
    if (kind == RoomAttachmentKind.media) {
      body = MediaGridZoomDetector(controller: controller, child: body);
    }
    final selecting = selection != null && selection.active;
    if (selection != null) {
      body = PopScope(
        canPop: !selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) selection.exit();
        },
        child: CallbackShortcuts(
          bindings: {
            if (selecting)
              const SingleActivator(LogicalKeyboardKey.escape): selection.exit,
          },
          child: Focus(focusNode: _selectionFocus, child: body),
        ),
      );
    }
    return InfoSubPage(
      title: widget.title,
      subtitle: widget.room.displayName,
      scrollable: false,
      appBar: selecting ? RoomMediaSelectionBar(selection) : null,
      child: body,
    );
  }
}

class RoomPinnedPage extends StatelessWidget {
  const RoomPinnedPage(this.room, {super.key});
  final Room room;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Pinned messages",
        subtitle: room.displayName,
        scrollable: false,
        child: RoomPinnedMessagesWidget(
          room: room,
          onEventClicked: (id) {
            closeRoomInfoToChat(context);
            EventBus.jumpToEvent.add(id);
            EventBus.focusTimeline.add(null);
          },
        ),
      );
}

class RoomThreadsPage extends StatelessWidget {
  const RoomThreadsPage(this.room, {super.key});
  final Room room;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Threads",
        subtitle: room.displayName,
        scrollable: false,
        child: RoomThreadsListWidget(
          room: room,
          onThreadOpened: (_) => closeRoomInfoToChat(context),
        ),
      );
}

class RoomWidgetsPage extends StatelessWidget {
  const RoomWidgetsPage(this.room, {super.key});
  final Room room;

  static bool availableIn(Room room) =>
      room.client.getComponent<WidgetComponent>() != null;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Widgets",
        subtitle: room.displayName,
        scrollable: false,
        child: RoomWidgetsView(room),
      );
}

class RoomMembersPage extends StatelessWidget {
  const RoomMembersPage(this.room, {super.key});
  final Room room;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Members",
        subtitle: room.displayName,
        scrollable: false,
        child: RoomMemberList(room,
            listPadding: const EdgeInsets.symmetric(horizontal: 8)),
      );
}
