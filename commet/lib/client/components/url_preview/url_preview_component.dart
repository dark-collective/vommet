import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:flutter/widgets.dart';

abstract class UrlPreviewComponent<T extends Client> implements Component<T> {
  bool shouldGetPreviewDataForTimelineEvent(
      Timeline timeline, TimelineEvent event);

  bool shouldGetPreviewsInRoom(Room room);

  Future<UrlPreviewData?> getPreview(Timeline timeline, TimelineEvent event);

  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri url);

  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event);

  // This is a dummy value that we can store in the cache when we fail to get the url preview.
  // Instead of storing null, which is a bit confusing as if the cache returns null, does that mean we have
  // nothing cached, or the result was invalid? maybe this is dumb but it was the simplest way
  // to prevent weird ui glitches when failed fetches kept getting retried.
  static UrlPreviewData invalidPreviewData =
      UrlPreviewData(Uri.new(), title: "Unable to get url preview ");
}

enum UrlDestinationType {
  page,
  video,
  image,
}

/// Vommet issue 676: what a component that shows bundled (MSC4095) previews
/// offers the timeline's consent card.
abstract class BundledUrlPreviewConsent {
  /// Allow bundled previews in [room], or in every chat ([everywhere]).
  Future<void> allowBundledPreviews(Room room, {required bool everywhere});

  /// "Not now": skip the card for this one message.
  void dismissBundledPreview(String eventId);

  /// Fires when a chat (or every chat) was allowed, so other cards update.
  Listenable get bundledConsentChanges;
}

class UrlPreviewData {
  final Uri uri;
  final String? siteName;
  final String? title;
  final String? description;
  final ImageProvider? image;
  final VideoAttachment? video;
  final UrlDestinationType? type;

  /// Vommet issue 676: the sender's app wrote this preview (MSC4095).
  final bool bundled;

  /// A bundled preview from someone else in a chat not yet allowed: the
  /// timeline asks before showing it. Carries no preview data.
  final bool needsConsent;

  const UrlPreviewData(
    this.uri, {
    this.siteName,
    this.title,
    this.description,
    this.type,
    this.image,
    this.video,
    this.bundled = false,
    this.needsConsent = false,
  });
}
