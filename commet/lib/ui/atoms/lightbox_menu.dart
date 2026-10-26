import 'package:commet/cache/file_provider.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/image_clipboard.dart';
import 'package:commet/utils/image_save.dart';
import 'package:commet/utils/image_share.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String get lightboxMenuTooltip => Intl.message("More options",
    desc: "Tooltip of the ⋮ button in the media viewer's top-right corner",
    name: "lightboxMenuTooltip");

/// Vommet: the media viewer's menu (Copy / Save as / Share). A picture's
/// long-press or right-click opens it; Vommet issue 766 adds the visible
/// ⋮ button ([LightboxMenuButton]) for pictures and videos.
class LightboxMenu {
  /// Opens the menu at [position] (global) for [image] or [video].
  static Future<void> show(
    BuildContext context,
    Offset position, {
    ImageProvider? image,
    FileProvider? video,
    String? fileName,
  }) async {
    if (image == null && video == null) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        if (image != null && ImageClipboard.supported)
          PopupMenuItem(
            value: "copy",
            child: Row(spacing: 12, children: [
              const Icon(Icons.copy, size: 20),
              Text(CommonStrings.promptCopyImage),
            ]),
          ),
        PopupMenuItem(
          value: "save",
          child: Row(spacing: 12, children: [
            const Icon(Icons.save_alt, size: 20),
            Text(CommonStrings.promptSaveAs),
          ]),
        ),
        if (ImageShare.supported)
          PopupMenuItem(
            value: "share",
            child: Row(spacing: 12, children: [
              const Icon(Icons.share, size: 20),
              Text(CommonStrings.promptShare),
            ]),
          ),
      ],
    );
    final origin = position & const Size(1, 1);
    switch (choice) {
      case "copy" when image != null:
        await ImageClipboard.copy(image);
      case "save" when image != null:
        await ImageSave.saveAs(image, fileName: fileName);
      case "save" when video != null:
        await DownloadUtils.downloadFile(video, videoFileName(fileName));
      case "share" when image != null:
        await ImageShare.share(image, fileName: fileName, origin: origin);
      case "share" when video != null:
        await ImageShare.shareFile(video, fileName: fileName, origin: origin);
    }
  }

  /// The suggested name when saving a video: its own, or "video.mp4".
  static String videoFileName(String? fileName) {
    final name = fileName?.trim() ?? "";
    return name.isEmpty ? "video.mp4" : name;
  }
}

/// Vommet issue 766: the ⋮ in the viewer's top-right corner. It fades out
/// while the picture or video is [hidden] (zoomed in) and back in at its
/// original size.
class LightboxMenuButton extends StatelessWidget {
  const LightboxMenuButton({
    required this.onOpen,
    this.hidden = false,
    super.key,
  });

  /// Opens the menu at the given global position (under the button).
  final void Function(Offset position) onOpen;
  final bool hidden;

  static const Duration fade = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: hidden ? 0 : 1,
      duration: fade,
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: hidden,
        // The viewer is a bare overlay; the button brings its own Material.
        child: Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Builder(
            builder: (context) => IconButton(
              key: const ValueKey("lightbox_menu_button"),
              tooltip: lightboxMenuTooltip,
              icon: const Icon(Icons.more_vert),
              color: Colors.white,
              onPressed: () {
                final box = context.findRenderObject();
                if (box is! RenderBox || !box.hasSize) return;
                onOpen(box.localToGlobal(box.size.bottomRight(Offset.zero)));
              },
            ),
          ),
        ),
      ),
    );
  }
}
