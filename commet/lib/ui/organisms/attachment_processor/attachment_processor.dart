import 'dart:io';

import 'package:commet/client/attachment.dart';
import 'package:commet/ui/atoms/media_spoiler_cover.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/ui/molecules/file_preview.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/ui/organisms/attachment_processor/metadata_explainer.dart';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:tiamat/tiamat.dart' as tiamat;

class AttachmentProcessor extends StatefulWidget {
  const AttachmentProcessor({required this.attachment, super.key});
  final PendingFileAttachment attachment;

  @override
  State<AttachmentProcessor> createState() => _AttachmentProcessorState();
}

class _AttachmentProcessorState extends State<AttachmentProcessor> {
  // Vommet: the switch was "Send Original", which read like a compression
  // setting; it only decides whether hidden info (metadata) is removed.
  String get promptRemoveHiddenInfo => Intl.message("Remove hidden info",
      name: "promptRemoveHiddenInfo",
      desc:
          "Switch in the attachment dialog: remove metadata such as location and camera details from a picture before sending");

  String get labelImageContainsLocationInfo => Intl.message(
      "Warning: This image contains location metadata",
      name: "labelImageContainsLocationInfo",
      desc:
          "Shown when a picture with location metadata is about to be sent as is");

  String labelHiddenInfoFound(String found) => Intl.message("Found: $found",
      name: "labelHiddenInfoFound",
      args: [found],
      desc:
          "Lists the kinds of metadata found in a picture, e.g. location, camera");

  String get labelCantRemoveHiddenInfo => Intl.message(
      "Vommet can't remove hidden info from this kind of file. It may include your name, location, or device.",
      name: "labelCantRemoveHiddenInfo",
      desc:
          "Shown in the attachment dialog for files whose metadata Vommet can't strip (videos, PDFs, documents)");

  // Vommet: media spoilers (MSC4193).
  String get promptMarkAsSpoiler => Intl.message("Mark as spoiler",
      name: "promptMarkAsSpoiler",
      desc:
          "Switch in the attachment dialog: send the picture or video blurred, so others tap it to see it");

  String get labelMarkAsSpoilerExplain => Intl.message(
      "Blurred for everyone until they tap it.",
      name: "labelMarkAsSpoilerExplain",
      desc: "Explains the 'Mark as spoiler' switch in the attachment dialog");

  String get labelSpoilerReason => Intl.message("Reason (optional)",
      name: "labelSpoilerReason",
      desc:
          "Text field under 'Mark as spoiler': why it is a spoiler, shown on the blurred picture");

  // Vommet: crop or rotate here, before the picture is added.
  String get promptCropOrRotate => Intl.message("Crop or rotate",
      name: "promptCropOrRotate",
      desc:
          "Row in the attachment dialog that opens the crop editor for the picture");

  String get promptUndoCrop => Intl.message("Undo crop",
      name: "promptUndoCrop",
      desc:
          "Button in the attachment dialog that puts the original picture back after cropping");

  /// The picture as picked, kept while it is cropped so Undo can restore it.
  ({
    String? name,
    String? path,
    Uint8List? data,
    String? mimeType,
    int? size
  })? original;

  bool get cropped => original != null;

  /// Bumped on every crop or undo so the preview reloads the picture.
  int previewVersion = 0;

  bool markSpoiler = false;
  final spoilerReason = TextEditingController();

  bool get canMarkSpoiler =>
      Mime.imageTypes.contains(widget.attachment.mimeType) ||
      Mime.videoTypes.contains(widget.attachment.mimeType);

  Map<String, IfdTag>? exifData;
  late IconData icon;
  VideoPlayerController? videoController;

  bool canProcessData = false;
  bool containsGpsData = false;
  bool stripMetadata = true;

  /// Kinds of hidden info found in a picture's EXIF, for the dialog.
  List<String> foundInfo = [];

  /// Pictures Vommet re-saves without their metadata. GIFs are left alone
  /// (re-saving would lose the animation).
  bool get canStripMetadata =>
      Mime.imageTypes.contains(widget.attachment.mimeType) &&
      widget.attachment.mimeType != "image/gif";

  bool get isVideo => Mime.videoTypes.contains(widget.attachment.mimeType);

  bool processing = false;

  FocusNode focusNode = FocusNode();

  @override
  void initState() {
    icon = Mime.toIcon(widget.attachment.mimeType);
    if (Mime.imageTypes.contains(widget.attachment.mimeType)) {
      loadExif();
      canProcessData = true;

      if (widget.attachment.mimeType == "image/gif") {
        canProcessData = false;
      }
    } else if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      videoController = VideoPlayerController();
      canProcessData = true;
    }
    super.initState();
  }

  @override
  void dispose() {
    videoController?.pause();
    spoilerReason.dispose();
    super.dispose();
  }

  void loadExif() async {
    late Map<String, IfdTag> data;
    if (widget.attachment.data != null) {
      data = await readExifFromBytes(widget.attachment.data!);
    } else {
      data = await readExifFromFile(File(widget.attachment.path!));
    }

    setState(() {
      if (data.keys.any((e) => e.toLowerCase().contains("gps"))) {
        containsGpsData = true;
      }
      bool has(List<String> names) => data.keys.any(
          (k) => names.any((n) => k.toLowerCase().contains(n.toLowerCase())));
      foundInfo = [
        if (containsGpsData) "location",
        if (has(["Image Make", "Image Model", "LensModel"]))
          "camera or phone model",
        if (has(["SerialNumber"])) "serial number",
        if (has(["DateTimeOriginal", "DateTimeDigitized", "Image DateTime"]))
          "date taken",
        if (has(["Artist", "Copyright", "XPAuthor", "OwnerName"])) "a name",
        if (has(["Software"])) "software",
      ];

      exifData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaledSafeArea(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: processing ? 0.5 : 1,
            child: IgnorePointer(
              ignoring: processing,
              child: KeyboardListener(
                focusNode: focusNode,
                autofocus: true,
                onKeyEvent: (value) {
                  if (processing) return;

                  if (value.logicalKey == LogicalKeyboardKey.enter) {
                    submit();
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.attachment.name != null)
                      Row(
                        children: [
                          Icon(icon),
                          Flexible(
                            child: tiamat.Text.labelLow(
                              widget.attachment.name!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints.loose(const Size(500, 500)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(children: [
                              FilePreview(
                                key: ValueKey(previewVersion),
                                mimeType: widget.attachment.mimeType,
                                path: widget.attachment.path,
                                data: widget.attachment.data,
                                videoController: videoController,
                              ),
                              // Vommet: blurred like everyone else will
                              // see it.
                              if (markSpoiler && canMarkSpoiler)
                                Positioned.fill(child: buildSpoilerPreview()),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    if (AttachmentCrop.canCrop(widget.attachment))
                      buildCropRow(),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: canStripMetadata
                          ? buildFileProcessingSwitch()
                          : buildCantStripNotice(),
                    ),
                    if (canStripMetadata && !stripMetadata)
                      buildMetadataDisplay(),
                    if (canMarkSpoiler) buildSpoilerSwitch(),
                    buildConfirmButton(),
                  ],
                ),
              ),
            ),
          ),
          if (processing) const CircularProgressIndicator()
        ],
      ),
    );
  }

  Widget buildCropRow() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: crop,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              spacing: 10,
              children: [
                Icon(Icons.crop_rotate, size: 20, color: colors.primary),
                Expanded(child: tiamat.Text.label(promptCropOrRotate)),
                if (cropped)
                  IconButton(
                    tooltip: promptUndoCrop,
                    icon: const Icon(Icons.undo),
                    onPressed: undoCrop,
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.chevron_right),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> crop() async {
    final file = widget.attachment;
    final before = (
      name: file.name,
      path: file.path,
      data: file.data,
      mimeType: file.mimeType,
      size: file.size
    );
    final changed = await AttachmentCrop.cropAttachment(context, file);
    if (!changed || !mounted) return;
    setState(() {
      original ??= before;
      previewVersion++;
      // Re-encoding the cropped picture already dropped its hidden info.
      foundInfo = [];
      containsGpsData = false;
      exifData = null;
    });
  }

  void undoCrop() {
    final o = original;
    if (o == null) return;
    final file = widget.attachment;
    file.name = o.name;
    file.path = o.path;
    file.data = o.data;
    file.mimeType = o.mimeType;
    file.size = o.size;
    file.dimensions = null;
    setState(() {
      original = null;
      previewVersion++;
    });
    loadExif();
  }

  Widget whatsThis() => InkWell(
        onTap: () => MetadataExplainer.show(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(MetadataExplainer.promptWhatsThis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline)),
        ),
      );

  Widget buildFileProcessingSwitch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: tiamat.Text.label(promptRemoveHiddenInfo)),
            tiamat.Switch(
              state: stripMetadata,
              onChanged: (value) => setState(() {
                stripMetadata = value;
              }),
            ),
          ],
        ),
        if (foundInfo.isNotEmpty)
          tiamat.Text.labelLow(labelHiddenInfoFound(foundInfo.join(", "))),
        whatsThis(),
      ],
    );
  }

  Widget buildCantStripNotice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Icon(Icons.info_outline,
                size: 18, color: Theme.of(context).colorScheme.secondary),
            Flexible(child: tiamat.Text.labelLow(labelCantRemoveHiddenInfo)),
          ],
        ),
        whatsThis(),
      ],
    );
  }

  Widget buildSpoilerPreview() {
    final reason = spoilerReason.text.trim();
    return IgnorePointer(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
              sigmaX: 26, sigmaY: 26, tileMode: TileMode.mirror),
          child: ColoredBox(
            color: Colors.black.withAlpha(60),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: MediaSpoilerPill(reason: reason.isEmpty ? null : reason),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSpoilerSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: tiamat.Text.label(promptMarkAsSpoiler)),
              tiamat.Switch(
                state: markSpoiler,
                onChanged: (value) => setState(() {
                  markSpoiler = value;
                }),
              ),
            ],
          ),
          tiamat.Text.labelLow(labelMarkAsSpoilerExplain),
          if (markSpoiler)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: spoilerReason,
                maxLength: 200,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: labelSpoilerReason,
                  counterText: "",
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Vommet: [file] marked as a spoiler when the switch is on.
  PendingFileAttachment withSpoiler(PendingFileAttachment file) {
    file.spoiler = markSpoiler && canMarkSpoiler;
    final reason = spoilerReason.text.trim();
    file.spoilerReason = file.spoiler && reason.isNotEmpty ? reason : null;
    return file;
  }

  Widget buildMetadataDisplay() {
    return Column(
      children: [
        if (containsGpsData) tiamat.Text.error(labelImageContainsLocationInfo)
      ],
    );
  }

  Widget buildConfirmButton() {
    return tiamat.Button(
      text: "Add File",
      onTap: submit,
    );
  }

  /// Vommet: Enter in the reason field and the dialog's own Enter handler
  /// could both submit; pop once.
  bool submitted = false;

  void submit() async {
    if (submitted) return;
    submitted = true;
    // Vommet: a cropped picture was already re-saved without hidden info.
    final process = canProcessData &&
        (isVideo || (canStripMetadata && stripMetadata && !cropped));
    if (!process) {
      Navigator.of(context).pop(withSpoiler(widget.attachment));
    } else {
      setState(() {
        processing = true;
      });
      var file = await processFile();
      if (mounted) {
        Navigator.of(context).pop(withSpoiler(file));
      }
    }
  }

  Future<PendingFileAttachment> processFile() async {
    late PendingFileAttachment processedFile;

    if (Mime.imageTypes.contains(widget.attachment.mimeType)) {
      processedFile = await processImage();
    } else if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      processedFile = await processVideo();
    }

    return processedFile;
  }

  Future<PendingFileAttachment> processImage() async {
    return await compute((PendingFileAttachment attachment) async {
      var data = attachment.data ?? await File(attachment.path!).readAsBytes();

      var decoder = img.findDecoderForData(data);
      var image = decoder!.decode(data)!;

      image.exif.clear();
      // Vommet: PNG text chunks (author, software, an AI generator's prompt,
      // XMP) were written back on re-save.
      image.textData = null;

      Uint8List? processedData;
      // Vommet: a blank name counts as none (it would become ".png").
      String? name = attachment.name?.trim();
      if (name?.isEmpty == true) name = null;
      String mime = attachment.mimeType!;
      if (name != null) {
        processedData = img.encodeNamedImage(name, image);
      }

      if (processedData == null) {
        processedData = img.encodePng(image);
        mime = "image/png";
        var fileName = name ?? "untitled.png";
        var rawName = path.basenameWithoutExtension(fileName);
        name = "$rawName.png";
      }

      return PendingFileAttachment(
          name: name,
          data: processedData,
          size: processedData.lengthInBytes,
          mimeType: mime);
    }, widget.attachment);
  }

  Future<PendingFileAttachment> processVideo() async {
    var file = widget.attachment;

    if (videoController != null) {
      file.thumbnailFile = await videoController!.screenshot();
      if (file.thumbnailFile != null) {
        file.thumbnailMime = Mime.lookupType("", data: file.thumbnailFile);
      }
    }

    file.length = await videoController!.getLength();
    file.dimensions = await videoController!.getSize();

    return file;
  }
}
