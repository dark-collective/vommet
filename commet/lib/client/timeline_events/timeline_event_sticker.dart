import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/utils/sticker_source_pack.dart';
import 'package:flutter/material.dart';

abstract class TimelineEventSticker extends TimelineEvent {
  String get stickerName;

  ImageProvider get stickerImage;

  /// Vommet issue 450: the sticker image's key (for Matrix, its mxc URL),
  /// matched against pack images to find the pack it came from.
  String get stickerKey;

  /// Vommet issue 450: the pack a Vommet sender named, if any.
  StickerPackTag? get stickerPackTag;
}
