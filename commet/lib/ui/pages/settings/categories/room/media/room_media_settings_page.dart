import 'dart:async';

import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter/material.dart';

/// Vommet issue 650: Room Settings > Media, the side panel's Media grid as a
/// full page: the All / Photos / Videos / GIFs chips, and the thumbnail size
/// (shared with the side panel) changed by a pinch or Ctrl + mouse wheel.
class RoomMediaSettingsPage extends StatefulWidget {
  const RoomMediaSettingsPage({required this.room, super.key});
  final Room room;

  @override
  State<RoomMediaSettingsPage> createState() => _RoomMediaSettingsPageState();
}

class _RoomMediaSettingsPageState extends State<RoomMediaSettingsPage> {
  late final RoomAttachmentFeed feed;
  final controller = ScrollController();
  RoomAttachmentFilter filter = RoomAttachmentFilter.all;
  StreamSubscription? _thumbnailSizeSub;

  @override
  void initState() {
    super.initState();
    feed = RoomAttachmentFeed(widget.room)..addListener(_onChanged);
    feed.start();
    _thumbnailSizeSub = preferences.mediaGridThumbnailSize.onChanged
        .listen((_) => _onChanged());
  }

  @override
  void dispose() {
    _thumbnailSizeSub?.cancel();
    feed.removeListener(_onChanged);
    feed.dispose();
    controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MediaGridZoomDetector(
      controller: controller,
      child: CustomScrollView(
        key: ValueKey("room-settings-media-${widget.room.localId}"),
        controller: controller,
        physics: const NoWheelWhileCtrlScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            sliver: SliverToBoxAdapter(
              child: RoomAttachmentChips(
                kind: RoomAttachmentKind.media,
                selected: filter,
                onSelected: (value) => setState(() => filter = value),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            sliver: RoomMediaGrid(feed, filter: filter),
          ),
          SliverToBoxAdapter(
            child: RoomAttachmentsFooter(feed, RoomAttachmentKind.media,
                filter: filter),
          ),
        ],
      ),
    );
  }
}
