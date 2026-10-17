// Vommet: crop or rotate a picture in the composer before sending it.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/client/attachment.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/utils/mime.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:tiamat/tiamat.dart' as tiamat;

class AttachmentCrop {
  static String get labelCropPicture => Intl.message("Crop picture",
      name: "labelCropPicture",
      desc: "Title of the dialog for cropping a picture before sending it");

  /// GIFs lose their animation when cropped, so they are left alone.
  static bool canCrop(PendingFileAttachment attachment) =>
      Mime.imageTypes.contains(attachment.mimeType) &&
      attachment.mimeType != "image/gif";

  /// Opens the crop editor and, on Done, replaces the attachment's data in
  /// place. Returns true when the picture changed.
  static Future<bool> cropAttachment(
      BuildContext context, PendingFileAttachment attachment) async {
    if (!canCrop(attachment)) return false;
    await attachment.resolve();
    final bytes = attachment.data;
    if (bytes == null || !context.mounted) return false;

    final ui.Image decoded;
    try {
      decoded = await decodeImageFromList(bytes);
    } catch (_) {
      return false;
    }
    final ratio = decoded.width / decoded.height;
    decoded.dispose();
    if (!context.mounted) return false;

    final controller = CropController();
    final cropped = await tiamat.PopupDialog.show<ui.Image>(context,
        title: labelCropPicture,
        content: AttachmentCropView(
          bytes,
          controller,
          ratio,
          onDone: (image) => Navigator.of(context).pop(image),
        ));
    controller.dispose();
    if (cropped == null) return false;

    final encoded = await encodeCropped(cropped, attachment.name);
    cropped.dispose();

    attachment.data = encoded.data;
    attachment.size = encoded.data.lengthInBytes;
    attachment.mimeType = encoded.mimeType;
    attachment.name = encoded.name;
    attachment.path = null;
    attachment.dimensions = null;
    attachment.thumbnailFile = null;
    attachment.thumbnailMime = null;
    return true;
  }

  /// Keeps the picture's format where the image package can write it (JPEG
  /// stays JPEG, so a cropped photo stays small); anything else becomes PNG.
  /// Re-encoding also drops EXIF, including location.
  static Future<({Uint8List data, String mimeType, String name})> encodeCropped(
      ui.Image image, String? name) async {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return compute(_encode, (
      width: image.width,
      height: image.height,
      rgba: rgba!.buffer.asUint8List(),
      name: name,
    ));
  }

  static ({Uint8List data, String mimeType, String name}) _encode(
      ({int width, int height, Uint8List rgba, String? name}) input) {
    final image = img.Image.fromBytes(
        width: input.width,
        height: input.height,
        bytes: input.rgba.buffer,
        numChannels: 4);

    final name = input.name;
    final ext = name == null ? "" : path.extension(name).toLowerCase();
    if (ext == ".jpg" || ext == ".jpeg") {
      final data = img.encodeJpg(image, quality: 90);
      return (data: data, mimeType: "image/jpeg", name: name!);
    }

    final base = name == null ? "picture" : path.basenameWithoutExtension(name);
    return (
      data: img.encodePng(image),
      mimeType: "image/png",
      name: "$base.png"
    );
  }
}

class AttachmentCropView extends StatefulWidget {
  const AttachmentCropView(this.imageBytes, this.controller, this.imageRatio,
      {required this.onDone, super.key});

  final Uint8List imageBytes;
  final CropController controller;
  final double imageRatio;
  final void Function(ui.Image image) onDone;

  @override
  State<AttachmentCropView> createState() => _AttachmentCropViewState();
}

class _AttachmentCropViewState extends State<AttachmentCropView> {
  String get labelCropFree => Intl.message("Free",
      name: "labelCropFree",
      desc: "Crop editor choice: crop to any shape, no fixed aspect ratio");

  String get labelCropSquare => Intl.message("Square",
      name: "labelCropSquare", desc: "Crop editor choice: crop to a square");

  String get promptCropReset => Intl.message("Reset",
      name: "promptCropReset",
      desc: "Crop editor button: undo the crop and rotation");

  String get promptCropDone => Intl.message("Done",
      name: "promptCropDone",
      desc: "Crop editor button: use the cropped picture");

  String get labelCropRotateLeft => Intl.message("Rotate left",
      name: "labelCropRotateLeft",
      desc: "Tooltip of the crop editor's rotate-left button");

  String get labelCropRotateRight => Intl.message("Rotate right",
      name: "labelCropRotateRight",
      desc: "Tooltip of the crop editor's rotate-right button");

  double? ratio;
  bool busy = false;

  void setRatio(double? value) {
    setState(() => ratio = value);
    widget.controller.aspectRatio = value;
  }

  void reset() {
    setState(() => ratio = null);
    widget.controller.aspectRatio = null;
    widget.controller.rotation = CropRotation.up;
    widget.controller.crop = const Rect.fromLTRB(0, 0, 1, 1);
  }

  Future<void> done() async {
    if (busy) return;
    setState(() => busy = true);
    final image = await widget.controller.croppedBitmap();
    widget.onDone(image);
  }

  Widget ratioChip(String label, double? value) {
    final selected = ratio == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setRatio(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.of(context).desktop;
    final buttons = [
      Expanded(
        flex: desktop ? 1 : 0,
        child: tiamat.Button.secondary(text: promptCropReset, onTap: reset),
      ),
      Expanded(
        flex: desktop ? 1 : 0,
        child: tiamat.Button(
            text: promptCropDone, onTap: busy ? null : () => done()),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SizedBox(
            width: 1000,
            child: AspectRatio(
              aspectRatio: widget.imageRatio,
              child: CropImage(
                image: Image.memory(widget.imageBytes),
                controller: widget.controller,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            IconButton(
              tooltip: labelCropRotateLeft,
              icon: const Icon(Icons.rotate_90_degrees_ccw),
              onPressed: () => widget.controller.rotateLeft(),
            ),
            IconButton(
              tooltip: labelCropRotateRight,
              icon: const Icon(Icons.rotate_90_degrees_cw),
              onPressed: () => widget.controller.rotateRight(),
            ),
            const SizedBox(width: 16),
            ratioChip(labelCropFree, null),
            ratioChip(labelCropSquare, 1),
            ratioChip("16:9", 16 / 9),
          ],
        ),
        const SizedBox(height: 16),
        if (desktop)
          Row(spacing: 8, children: buttons)
        else
          Column(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buttons,
          ),
      ],
    );
  }
}
