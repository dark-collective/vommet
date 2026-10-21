import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';

/// Vommet: the auto-download key of an event image, if it has one.
String? autoDownloadKey(ImageProvider? image) =>
    image is MatrixMxcImage ? image.identifier.toString() : null;

/// Vommet: lets [image] download even if automatic download held it back
/// (opening it in the viewer is an explicit request).
void revealAutoDownload(ImageProvider? image) {
  final key = autoDownloadKey(image);
  if (key != null) MediaAutoDownload.reveal(key);
}

/// Vommet: covers held-back media (shown as its blurhash meanwhile) with a
/// download button and its size; a tap loads it in place. Shows nothing once
/// the media may load. Put it over the media, e.g. with [Positioned.fill].
class AutoDownloadOverlay extends StatelessWidget {
  const AutoDownloadOverlay(
      {required this.image, this.fileSize, this.duration, super.key});

  final ImageProvider? image;
  final int? fileSize;

  /// For videos: shown before the size.
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final key = autoDownloadKey(image);
    if (key == null) return const SizedBox.shrink();

    return ValueListenableBuilder<Set<String>>(
      valueListenable: MediaAutoDownload.held,
      builder: (context, held, _) {
        if (!held.contains(key)) return const SizedBox.shrink();

        final label = [
          if (duration != null) TextUtils.formatDuration(duration!),
          if (fileSize != null) TextUtils.readableFileSize(fileSize!),
        ].join(" · ");

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => MediaAutoDownload.reveal(key),
          child: Stack(children: [
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: Colors.black.withAlpha(120), shape: BoxShape.circle),
                child: const Icon(Icons.download_rounded,
                    color: Colors.white, size: 28),
              ),
            ),
            if (label.isNotEmpty)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.black.withAlpha(130),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(label,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
          ]),
        );
      },
    );
  }
}
