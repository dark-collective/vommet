import 'package:commet/client/attachment.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' show ImageButton;

class AttachmentIcon extends StatefulWidget {
  const AttachmentIcon(this.attachment, {super.key, this.removeAttachment});
  final PendingFileAttachment attachment;
  final Function()? removeAttachment;

  @override
  State<AttachmentIcon> createState() => _AttachmentIconState();
}

class _AttachmentIconState extends State<AttachmentIcon> {
  String get labelRemoveAttachment => Intl.message("Remove",
      name: "labelRemoveAttachment",
      desc: "Tooltip of the X button on a file attached to a message");

  String get labelCropAttachment => Intl.message("Crop or rotate",
      name: "labelCropAttachment",
      desc: "Tooltip of the crop button on a picture attached to a message");

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
    var changed =
        await AttachmentCrop.cropAttachment(context, widget.attachment);
    if (changed && mounted) setState(loadImage);
  }

  Widget badge(IconData icon, String tooltip, void Function() onTap) {
    var colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withAlpha(230),
              shape: BoxShape.circle),
          child: Icon(icon, size: 12, color: colors.onSurface),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var canCrop = AttachmentCrop.canCrop(widget.attachment);
    return Stack(
      children: [
        Positioned.fill(
          child: ImageButton(
            size: 20,
            image: image,
            icon: Mime.toIcon(widget.attachment.mimeType),
            onTap: canCrop ? crop : null,
            iconSize: 20,
          ),
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
