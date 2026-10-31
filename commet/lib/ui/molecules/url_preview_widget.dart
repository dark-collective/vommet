import 'dart:math';

import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/message_attachment.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/shimmer_loading.dart';
import 'package:commet/utils/links/invidious_playback.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UrlPreviewWidget extends StatefulWidget {
  const UrlPreviewWidget(this.data, {super.key, this.onTap, this.senderName});
  final UrlPreviewData? data;
  final void Function()? onTap;

  /// Vommet issue 676: who sent a bundled preview, for its source line.
  final String? senderName;

  @override
  State<UrlPreviewWidget> createState() => _UrlPreviewWidgetState();
}

class _UrlPreviewWidgetState extends State<UrlPreviewWidget> {
  double titleWidth = 0;
  double bodyWidth1 = 0;
  double bodyWidth2 = 0;

  @override
  void initState() {
    var rng = Random();
    titleWidth = (rng.nextDouble() * 50) + 50;
    bodyWidth1 = (rng.nextDouble() * 200) + 100;
    bodyWidth2 = (rng.nextDouble() * 200) + 100;

    super.initState();
  }

  Uri? invidiousFor;
  InvidiousVideo? invidiousVideo;

  /// Vommet issue 175: a YouTube video link played through the picked
  /// Invidious instance, or null. One instance per preview, so the player
  /// keeps its stream across rebuilds.
  InvidiousVideo? get invidious {
    final uri = widget.data?.uri;
    if (uri == null ||
        BuildConfig.WEB ||
        widget.data?.video != null ||
        !InvidiousPlayback.enabled) {
      return null;
    }
    if (uri != invidiousFor) {
      invidiousFor = uri;
      invidiousVideo = InvidiousPlayback.videoFor(uri);
    }
    return invidiousVideo;
  }

  @override
  void didChangeDependencies() {
    setState(() {});
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final invidious = this.invidious;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Tile.surfaceContainer(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: 300,
                          maxHeight: invidious != null ? 300 : 240),
                      child: widget.data == null
                          ? buildLoadingDisplay()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                if (widget.data!.mismatchedHost != null &&
                                    !RedactionScope.of(context).isActive)
                                  mismatchWarning(context),
                                Align(
                                    alignment: Alignment.topLeft,
                                    child: body(context)),
                                if (hasBody)
                                  const SizedBox(
                                    width: 10,
                                    height: 10,
                                  ),
                                if (widget.data!.image != null &&
                                    widget.data?.video == null &&
                                    invidious == null)
                                  Flexible(child: image()),
                                if (invidious != null)
                                  MessageAttachment(
                                    previewMedia: true,
                                    invidious.attachment(
                                        thumbnail: widget.data!.image),
                                    constrainSize: false,
                                    key: ValueKey(invidious.stream),
                                  ),
                                if (widget.data!.video != null)
                                  MessageAttachment(
                                    previewMedia: true,
                                    widget.data!.video!,
                                    constrainSize: false,
                                  )
                              ],
                            ),
                    ),
                    if (invidious != null) invidiousLinks(context),
                    if (!RedactionScope.of(context).isActive)
                      ...[sourceLine(context)].whereType<Widget>(),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Vommet issue 175: the original site and the Invidious page.
  Widget invidiousLinks(BuildContext context) {
    final uri = widget.data!.uri;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(labelOpenOnYoutube),
            onPressed: () =>
                LinkUtils.open(uri, context: context, useAltFrontends: false),
          ),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(labelOpenOnInvidious),
            onPressed: () => LinkUtils.open(uri, context: context),
          ),
        ],
      ),
    );
  }

  static String get labelOpenOnYoutube => Intl.message("Open on YouTube",
      name: "labelOpenOnYoutube",
      desc: "Button under a YouTube video playing inside the app that opens "
          "it on YouTube's own site");

  static String get labelOpenOnInvidious => Intl.message("Open on Invidious",
      name: "labelOpenOnInvidious",
      desc: "Button under a YouTube video playing inside the app that opens "
          "it on the picked Invidious instance's site");

  static String labelBundledPreviewFrom(String sender) =>
      Intl.message("Preview from $sender’s app",
          args: [sender],
          name: "labelBundledPreviewFrom",
          desc: "Under a link preview the sender's app attached, before the "
              "link's real domain; sender is their display name");

  static String get labelBundledPreviewFromSender =>
      Intl.message("Preview from the sender’s app",
          name: "labelBundledPreviewFromSender",
          desc: "Under a link preview the sender's app attached when their "
              "name isn't known, before the link's real domain");

  static String labelHomeserverPreviewBy(String server) =>
      Intl.message("Preview by $server",
          args: [server],
          name: "labelHomeserverPreviewBy",
          desc: "Under a link preview the user's homeserver made, before the "
              "link's domain; server is the homeserver's name");

  static String labelPreviewSiteMismatch(String claimed, String real) =>
      Intl.message("This preview says $claimed, but the link goes to $real.",
          args: [claimed, real],
          name: "labelPreviewSiteMismatch",
          desc: "Warning on a sender-made link preview that names a different "
              "site than the link really goes to");

  /// Vommet issue 676: who made the preview and the link's real domain, so
  /// a made-up title can't hide where the link goes.
  Widget? sourceLine(BuildContext context) {
    final data = widget.data;
    if (data == null) return null;

    final String source;
    final IconData icon;
    if (data.bundled) {
      final name = widget.senderName;
      source = name == null
          ? labelBundledPreviewFromSender
          : labelBundledPreviewFrom(name);
      icon = Icons.person_outline;
    } else if (data.previewedBy != null) {
      source = labelHomeserverPreviewBy(data.previewedBy!);
      icon = Icons.dns_outlined;
    } else {
      return null;
    }

    final color = Theme.of(context).colorScheme.secondary;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: tiamat.Text.labelLow(
                "$source · ${data.uri.host}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vommet issue 676: the preview names another site than the link goes
  /// to. Its picture is already left out.
  Widget mismatchWarning(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final amber = dark ? Colors.amber.shade300 : Colors.amber.shade900;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: amber.withAlpha(dark ? 40 : 28),
          border: Border.all(color: amber.withAlpha(160)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: amber),
            const SizedBox(width: 6),
            Flexible(
              child: tiamat.Text.label(labelPreviewSiteMismatch(
                  widget.data!.mismatchedHost!, widget.data!.uri.host)),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildLoadingDisplay() {
    var color = Theme.of(context).colorScheme.surfaceContainerLowest;
    return Shimmer(
      child: ShimmerLoading(
        isLoading: true,
        child: SizedBox(
          height: 300,
          child: Row(
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: titleWidth,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4), color: color),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Container(
                      height: 10,
                      width: bodyWidth1,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4), color: color),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Container(
                      height: 10,
                      width: bodyWidth2,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4), color: color),
                    ),
                    SizedBox(
                      height: 8,
                    ),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxHeight: 180, maxWidth: 300),
                            child: Container(
                              color: color,
                            ))),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget image() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: widget.data?.type != UrlDestinationType.video
            ? () {
                Lightbox.show(context, image: widget.data!.image);
              }
            : null,
        child: RedactedImage(
          child: Image(
            image: widget.data!.image!,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  bool get hasBody =>
      widget.data?.siteName != null ||
      widget.data?.title != null ||
      widget.data?.description != null;

  Widget body(BuildContext context) {
    if (RedactionScope.of(context).isActive) return redactedBody(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.data!.siteName != null)
          tiamat.Text.labelLow(
            widget.data!.siteName!,
            maxLines: 1,
            overflow: TextOverflow.fade,
          ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.data!.title != null)
              tiamat.Text.labelEmphasised(
                widget.data!.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (widget.data!.description != null)
              tiamat.Text.tiny(
                widget.data!.description!,
                maxLines: 2,
                color: Theme.of(context).colorScheme.secondary,
                overflow: TextOverflow.ellipsis,
              )
          ],
        )
      ],
    );
  }

  /// [body] in redacted mode: the same lines, drawn as message text is.
  Widget redactedBody(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.data!.siteName != null)
          RedactedText(
            widget.data!.siteName!,
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: text.bodyMedium!.copyWith(
                color: scheme.secondary,
                fontWeight: FontWeight.w400,
                fontSize: 12),
          ),
        if (widget.data!.title != null)
          RedactedText(
            widget.data!.title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge!.copyWith(fontWeight: FontWeight.w400),
          ),
        if (widget.data!.description != null)
          RedactedText(
            widget.data!.description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium!.copyWith(
                color: scheme.secondary,
                fontWeight: FontWeight.w300,
                fontSize: 10),
          ),
      ],
    );
  }
}
