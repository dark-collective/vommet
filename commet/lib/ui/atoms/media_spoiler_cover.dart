import 'dart:ui' as ui;

import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/media_spoiler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:intl/intl.dart';

/// Vommet: media spoilers (MSC4193). The cover shown in place of a
/// spoilered picture or video, the "Hide" chip shown once it is revealed,
/// and a builder that rebuilds when the viewer reveals or hides it.
///
/// The cover never loads the media: it shows the event's blurhash (decoded
/// locally) or a plain fill, so nothing is downloaded, decrypted or played
/// until the viewer taps it.

String get labelSpoilerTapToReveal => Intl.message("Spoiler · Tap to reveal",
    name: "labelSpoilerTapToReveal",
    desc: "On a blurred picture or video the sender marked as a spoiler; "
        "tapping it shows the media");

String get promptHideSpoiler => Intl.message("Hide",
    name: "promptHideSpoiler",
    desc: "Small button on a revealed spoiler picture or video that blurs "
        "it again");

String get labelSpoilerVideo => Intl.message("Video",
    name: "labelSpoilerVideo",
    desc: "Badge on a blurred spoiler video, so it reads as a video before "
        "it is revealed");

String get labelSpoilerViewerHint => Intl.message("Tap to reveal",
    name: "labelSpoilerViewerHint",
    desc: "Accessibility label of a blurred spoiler picture or video");

/// The blurhash of an event's picture or video preview, if it has one.
String? spoilerBlurhashOf(ImageProvider? image) =>
    image is LODImageProvider ? image.blurhash : null;

/// Builds [builder] with whether [spoiler] is still covered, and again
/// whenever this viewer reveals or hides it. With no spoiler, hidden is
/// always false.
class MediaSpoilerBuilder extends StatelessWidget {
  const MediaSpoilerBuilder(
      {required this.spoiler, required this.builder, super.key});

  final MediaSpoiler? spoiler;
  final Widget Function(BuildContext context, bool hidden) builder;

  @override
  Widget build(BuildContext context) {
    final spoiler = this.spoiler;
    if (spoiler == null) return builder(context, false);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: MediaSpoilerReveal.revealed,
      builder: (context, revealed, _) =>
          builder(context, !revealed.contains(spoiler.key)),
    );
  }
}

/// "Spoiler · Tap to reveal" with the reason under it, on a dark pill.
class MediaSpoilerPill extends StatelessWidget {
  const MediaSpoilerPill({this.reason, super.key});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.black.withAlpha(150),
          border: Border.all(color: Colors.white.withAlpha(40)),
          borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.visibility_off, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(labelSpoilerTapToReveal,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: base.copyWith(
                    fontSize: 13.5,
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        if (reason != null) ...[
          const SizedBox(height: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(reason!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: base.copyWith(
                    fontSize: 12, color: Colors.white.withAlpha(210))),
          ),
        ],
      ]),
    );
  }
}

/// Fills its space with a covered spoiler: the blurhash (or a plain fill),
/// a dark scrim and the pill. A tap reveals it for this viewer. [compact]
/// (grid thumbnails) shows only an icon.
class MediaSpoilerCover extends StatelessWidget {
  const MediaSpoilerCover({
    required this.spoiler,
    this.blurhash,
    this.isVideo = false,
    this.compact = false,
    this.interactive = true,
    super.key,
  });

  final MediaSpoiler spoiler;
  final String? blurhash;
  final bool isVideo;
  final bool compact;

  /// False for a preview that only shows what others will see (the
  /// attachment dialog).
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final cover = Stack(fit: StackFit.expand, children: [
      SpoilerBlurhashFill(blurhash: blurhash),
      ColoredBox(color: Colors.black.withAlpha(60)),
      Center(
        child: compact
            ? Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: Colors.black.withAlpha(150), shape: BoxShape.circle),
                child: const Icon(Icons.visibility_off,
                    size: 18, color: Colors.white),
              )
            : Padding(
                padding: const EdgeInsets.all(8),
                child: MediaSpoilerPill(reason: spoiler.reason),
              ),
      ),
      if (isVideo && !compact)
        Positioned(left: 8, bottom: 8, child: _badge(context)),
    ]);

    if (!interactive) return cover;

    return Semantics(
      button: true,
      label: "$labelSpoilerTapToReveal"
          "${spoiler.reason == null ? "" : ". ${spoiler.reason}"}",
      hint: labelSpoilerViewerHint,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => MediaSpoilerReveal.reveal(spoiler.key),
          child: cover,
        ),
      ),
    );
  }

  Widget _badge(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: Colors.black.withAlpha(150),
            borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(labelSpoilerVideo,
              style:
                  (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
                      .copyWith(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
        ]),
      );
}

/// "Hide" on a revealed spoiler: covers it again. Place it in a corner of
/// the media (e.g. [Positioned] top right).
class MediaSpoilerHideChip extends StatelessWidget {
  const MediaSpoilerHideChip({required this.spoiler, super.key});

  final MediaSpoiler spoiler;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => MediaSpoilerReveal.hide(spoiler.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.visibility_off, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Text(promptHideSpoiler,
                  style: (Theme.of(context).textTheme.labelSmall ??
                          const TextStyle())
                      .copyWith(
                          fontSize: 11.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The blurhash, decoded locally and stretched over the space, or a plain
/// fill when there is none (or it doesn't decode).
class SpoilerBlurhashFill extends StatefulWidget {
  const SpoilerBlurhashFill({this.blurhash, super.key});

  final String? blurhash;

  @override
  State<SpoilerBlurhashFill> createState() => _SpoilerBlurhashFillState();
}

class _SpoilerBlurhashFillState extends State<SpoilerBlurhashFill> {
  ui.Image? image;

  @override
  void initState() {
    super.initState();
    decode();
  }

  @override
  void didUpdateWidget(SpoilerBlurhashFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blurhash != widget.blurhash) decode();
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  Future<void> decode() async {
    final hash = widget.blurhash;
    if (hash == null || hash.length < 6) return;
    try {
      final decoded =
          await blurHashDecodeImage(blurHash: hash, width: 16, height: 16);
      if (!mounted || widget.blurhash != hash) {
        decoded.dispose();
        return;
      }
      setState(() {
        image?.dispose();
        image = decoded;
      });
    } catch (_) {
      // Not a valid blurhash: keep the plain fill.
    }
  }

  @override
  Widget build(BuildContext context) {
    final fill = ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final image = this.image;
    if (image == null) return fill;
    return Stack(fit: StackFit.expand, children: [
      fill,
      RawImage(
          image: image, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
    ]);
  }
}

/// A covered spoiler as a page of the image viewer (gallery): the cover at
/// the media's shape in the middle, tap to reveal, and a close button.
class MediaSpoilerViewerCover extends StatelessWidget {
  const MediaSpoilerViewerCover({
    required this.spoiler,
    required this.onClose,
    this.blurhash,
    this.aspectRatio,
    this.isVideo = false,
    super.key,
  });

  final MediaSpoiler spoiler;
  final String? blurhash;
  final double? aspectRatio;
  final bool isVideo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ratio = aspectRatio == null || aspectRatio! <= 0 ? 1.0 : aspectRatio!;
    return Material(
      color: Colors.transparent,
      child: Stack(children: [
        Positioned.fill(
          child:
              GestureDetector(behavior: HitTestBehavior.opaque, onTap: onClose),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: AspectRatio(
              aspectRatio: ratio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MediaSpoilerCover(
                    spoiler: spoiler, blurhash: blurhash, isVideo: isVideo),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                onPressed: onClose,
                color: Colors.white,
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
