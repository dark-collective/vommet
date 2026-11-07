import 'package:commet/ui/atoms/clickable_gesture_detector.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' show ImageButton;

class AttachmentIcon extends StatefulWidget {
  const AttachmentIcon(this.attachment,
      {super.key,
      this.room,
      this.removeAttachment,
      this.badgeSize = 18,
      this.dragTarget,
      this.onOpen});
  // Vommet issue 1056: use the sending room’s packs.
  final Room? room;
  final PendingFileAttachment attachment;
  final Function()? removeAttachment;

  /// Vommet issue 1066: what a tap does instead of opening the crop editor
  /// (the desktop tray's big preview, or a video's dialog).
  final void Function()? onOpen;

  /// Vommet issue 838: phones use bigger ✕ and crop badges.
  final double badgeSize;
  final Widget Function(Widget)? dragTarget;

  @override
  State<AttachmentIcon> createState() => _AttachmentIconState();
}

class _AttachmentIconState extends State<AttachmentIcon> {
  String get labelRemoveAttachment => Intl.message("Remove",
      name: "labelRemoveAttachment",
      desc: "Tooltip of the X button on a file attached to a message");

  String get labelCropAttachment => Intl.message("Crop, draw or redact",
      name: "labelCropAttachment",
      desc: "Tooltip of the edit button on a picture attached to a message");

  bool hovered = false;

  ImageProvider? image;

  @override
  void initState() {
    loadImage();
    super.initState();
  }

  void loadImage() {
    image = null;
    if (Mime.imageTypes.contains(widget.attachment.mimeType) &&
        widget.attachment.data != null) {
      image = Image.memory(widget.attachment.data!).image;
    }

    if (widget.attachment.thumbnailFile != null) {
      image = Image.memory(widget.attachment.thumbnailFile!).image;
    }
  }

  // Vommet: tapping a picture opens the crop editor; the X removes it (a tap
  // used to remove the attachment without warning).
  Future<void> crop() async {
    var changed = await AttachmentCrop.cropAttachment(
        context, widget.attachment,
        room: widget.room);
    if (changed && mounted) setState(loadImage);
  }

  Widget badge(IconData icon, String tooltip, void Function() onTap) {
    var colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: ClickableGestureDetector(
        onTap: onTap,
        child: Container(
          width: widget.badgeSize,
          height: widget.badgeSize,
          decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withAlpha(230),
              shape: BoxShape.circle),
          child: Icon(icon,
              size: widget.badgeSize * 2 / 3, color: colors.onSurface),
        ),
      ),
    );
  }

  Widget wrapDrag(Widget child) => widget.dragTarget?.call(child) ?? child;

  @override
  Widget build(BuildContext context) {
    var canCrop = AttachmentCrop.canCrop(widget.attachment);
    return Stack(
      children: [
        Positioned.fill(
          child: wrapDrag(ImageButton(
            size: 20,
            image: image,
            icon: Mime.toIcon(widget.attachment.mimeType),
            onTap: widget.onOpen ?? (canCrop ? crop : null),
            iconSize: 20,
          )),
        ),
        Positioned(
          top: 1,
          right: 1,
          child: badge(Icons.close, labelRemoveAttachment,
              () => widget.removeAttachment?.call()),
        ),
        if (canCrop)
          Positioned(
            bottom: 1,
            right: 1,
            child: badge(Icons.crop, labelCropAttachment, crop),
          ),
      ],
    );
  }
}
