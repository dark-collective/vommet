import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
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
/// offers the timeline's consent card, the settings and the profile.
abstract class BundledUrlPreviewConsent {
  /// "Everyone in this chat" ([allowed] true) or "Never in this chat"
  /// (false) for [room]; null forgets the choice, so the chat asks again.
  Future<void> setBundledConsent(Room room, bool? allowed);

  /// "Not now": skip the card for this one message.
  void dismissBundledPreview(String eventId);

  /// The Always and Never lists of this account.
  BundledPreviewPeople get bundledPreviewPeople;

  /// Puts [userId] on the Always or Never list, or off both (null).
  Future<void> setBundledPreviewTrust(
      String userId, BundledPreviewPersonTrust? trust);

  /// Fires when a chat or a person was allowed or refused, so cards, the
  /// settings and profiles update.
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

  /// A bundled preview shown because the homeserver had none for the link
  /// (unencrypted chats prefer the homeserver's); the consent card says so.
  final bool homeserverFallback;

  /// A bundled preview that names another site than the link goes to: that
  /// site's domain. The card warns and leaves out the picture.
  final String? mismatchedHost;

  /// The homeserver that made this preview (its server name); null for
  /// bundled previews.
  final String? previewedBy;

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
    this.homeserverFallback = false,
    this.mismatchedHost,
    this.previewedBy,
  });
}
