import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/diagnostic/benchmark_values.dart';
import 'package:commet/ui/molecules/bundled_url_preview_consent_card.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:commet/ui/molecules/url_preview_widget.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';

class TimelineEventViewUrlPreviews extends StatefulWidget {
  const TimelineEventViewUrlPreviews(
      {required this.initialIndex,
      required this.timeline,
      required this.component,
      super.key});

  final int initialIndex;
  final Timeline timeline;
  final UrlPreviewComponent component;

  @override
  State<TimelineEventViewUrlPreviews> createState() =>
      _TimelineEventViewUrlPreviewsState();
}

class _TimelineEventViewUrlPreviewsState
    extends State<TimelineEventViewUrlPreviews>
    implements TimelineEventViewWidget {
  UrlPreviewData? data;
  bool loading = false;
  int index = 0;

  GlobalKey key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    BenchmarkValues.numTimelineUrlPreviewBuilt += 1;

    if (data == UrlPreviewComponent.invalidPreviewData) return Container();

    // Vommet issue 377: loading finished without a preview. A null preview
    // would draw the loading placeholder, which then never goes away.
    if (data == null && !loading) return Container();

    // Vommet issue 676: a bundled preview from a chat not yet allowed.
    final component = consent;
    if (data?.needsConsent == true) {
      if (component == null) return Container();
      return Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 40, 2),
          child: buildConsentCard(component, data!));
    }

    return Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 40, 2),
        child: UrlPreviewWidget(
          key: key,
          data,
          onTap: () {
            LinkUtils.open(data!.uri, context: context);
          },
        ));
  }

  Widget buildConsentCard(
      BundledUrlPreviewConsent component, UrlPreviewData data) {
    final event = widget.timeline.events[index];
    final room = widget.timeline.room;
    final sender = room.getMemberOrFallback(event.senderId).displayName;

    return BundledUrlPreviewConsentCard(
      senderName: sender,
      uri: data.uri,
      onAllowChat: () => allow(component, room, everywhere: false),
      onAllowEverywhere: () => allow(component, room, everywhere: true),
      onNotNow: () {
        component.dismissBundledPreview(event.eventId);
        setState(() => this.data = UrlPreviewComponent.invalidPreviewData);
      },
    );
  }

  Future<void> allow(BundledUrlPreviewConsent component, Room room,
      {required bool everywhere}) async {
    try {
      await component.allowBundledPreviews(room, everywhere: everywhere);
    } catch (e) {
      Log.w("Couldn't save the bundled preview choice: $e");
    }
    // Allowing notifies bundledConsentChanges, which refreshes this card.
  }

  @override
  void update(int newIndex) {
    setStateFromIndex(newIndex);
  }

  @override
  void initState() {
    setStateFromIndex(widget.initialIndex);
    consent?.bundledConsentChanges.addListener(onConsentChanged);
    super.initState();
  }

  @override
  void dispose() {
    consent?.bundledConsentChanges.removeListener(onConsentChanged);
    super.dispose();
  }

  /// Vommet issue 676: the component, when it shows bundled previews.
  BundledUrlPreviewConsent? get consent {
    final Object component = widget.component;
    return component is BundledUrlPreviewConsent ? component : null;
  }

  void onConsentChanged() {
    if (mounted && data?.needsConsent == true) setStateFromIndex(index);
  }

  void setStateFromIndex(int index) {
    this.index = index;
    var event = widget.timeline.events[index];
    var cachedData = widget.component.getCachedPreview(widget.timeline, event);

    if (cachedData != null) {
      setState(() {
        data = cachedData;
        key = GlobalKey();
      });
    } else {
      setState(() {
        loading = true;
        data = null;
      });

      if (event.status == TimelineEventStatus.synced) {
        widget.component.getPreview(widget.timeline, event).then(
          (value) async {
            if (mounted) {
              final image = value?.image;
              if (image != null) {
                if (context.mounted) {
                  await precacheImage(image, context);
                }
              }

              if (mounted)
                setState(() {
                  loading = false;
                  data = value;
                  key = GlobalKey();
                });
            }
          },
          // Vommet issue 377: a failed lookup ends the loading state too.
          onError: (Object e) {
            Log.w("Url preview lookup failed: $e");
            if (mounted)
              setState(() {
                loading = false;
                data = UrlPreviewComponent.invalidPreviewData;
              });
          },
        );
      }
    }
  }
}
