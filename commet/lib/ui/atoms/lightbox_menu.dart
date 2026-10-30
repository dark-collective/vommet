import 'package:commet/cache/file_provider.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart'
    show promptJumpToMessage;
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/image_clipboard.dart';
import 'package:commet/utils/image_save.dart';
import 'package:commet/utils/image_share.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:commet/ui/molecules/video_player/video_pip.dart';

String get lightboxMenuTooltip => Intl.message("More options",
    desc: "Tooltip of the ⋮ button in the media viewer's top-right corner",
    name: "lightboxMenuTooltip");

/// Vommet: the media viewer's menu (Copy / Save as / Share). A picture's
/// long-press or right-click opens it; Vommet issue 766 adds the visible
/// ⋮ button ([LightboxMenuButton]) for pictures and videos.
class LightboxMenu {
  /// Opens the menu at [position] (global) for [image] or [video].
  /// Vommet issue 771: [onJumpToMessage] (viewer opened from the Media tab)
  /// adds Jump to message; the caller closes the viewer. Vommet issue 802:
  /// [onForward] adds Forward (the caller closes the viewer too). Vommet
  /// issue 894: [onReply] adds Reply, first (the caller closes it too).
  static Future<void> show(
    BuildContext context,
    Offset position, {
    ImageProvider? image,
    FileProvider? video,
    String? fileName,
    VoidCallback? onJumpToMessage,
    VoidCallback? onForward,
    VoidCallback? onReply,
    VoidCallback? onPictureInPicture,
  }) async {
    if (image == null && video == null) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        if (onReply != null)
          PopupMenuItem(
            value: "reply",
            child: Row(spacing: 12, children: [
              const Icon(Icons.reply, size: 20),
              Text(CommonStrings.promptReply),
            ]),
          ),
        if (onJumpToMessage != null)
          PopupMenuItem(
            value: "jump",
            child: Row(spacing: 12, children: [
              const Icon(Icons.chat_bubble_outline, size: 20),
              Text(promptJumpToMessage),
            ]),
          ),
        if (onForward != null)
          PopupMenuItem(
            value: "forward",
            child: Row(spacing: 12, children: [
              const Icon(Icons.shortcut, size: 20),
              Text(ForwardMessageDialog.promptForwardMessage),
            ]),
          ),
        if (video != null && onPictureInPicture != null)
          PopupMenuItem(
            value: "pip",
            child: Row(spacing: 12, children: [
              const Icon(Icons.picture_in_picture_alt_rounded, size: 20),
              Text(videoPipOpen),
            ]),
          ),
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
      case "reply" when onReply != null:
        onReply();
      case "jump" when onJumpToMessage != null:
        onJumpToMessage();
      case "forward" when onForward != null:
        onForward();
      case "pip" when onPictureInPicture != null:
        onPictureInPicture();
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
