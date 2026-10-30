import 'dart:io';

import 'package:commet/cache/file_cache.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/media_spoiler_cover.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/ui/molecules/file_preview.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/picture_shrink.dart';
import 'package:commet/ui/organisms/attachment_processor/metadata_explainer.dart';
import 'package:commet/ui/organisms/attachment_processor/video_gif_trim.dart';
import 'package:commet/utils/video_gif.dart';
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

  // Vommet issue 128: sending pictures smaller.
  String get promptSendSmaller => Intl.message("Send smaller",
      name: "promptSendSmaller",
      desc:
          "Switch in the attachment dialog that re-saves a picture smaller before sending it");

  String get labelWorkingOutSmallerSize =>
      Intl.message("Working out the smaller size…",
          name: "labelWorkingOutSmallerSize",
          desc: "Shown under 'Send smaller' while the smaller picture is made");

  String labelSmallerSize(String before, String after) => Intl.message(
      "$before → $after",
      name: "labelSmallerSize",
      args: [before, after],
      desc:
          "File size before and after sending a picture smaller, e.g. 4.8 MB → 610 KB");

  String labelSmallerDimensions(String before, String after, int percent) =>
      Intl.message("$before → $after · $percent% smaller",
          name: "labelSmallerDimensions",
          args: [before, after, percent],
          desc:
              "Picture size in pixels before and after sending it smaller, and the saving");

  String get labelSmallerOnMobileData => Intl.message(
      "On because you're on mobile data",
      name: "labelSmallerOnMobileData",
      desc: "Says 'Send smaller' was switched on by the mobile data default");

  String get labelHiddenInfoAlwaysRemoved =>
      Intl.message("Always removed from smaller pictures",
          name: "labelHiddenInfoAlwaysRemoved",
          desc: "Under 'Remove hidden info' while 'Send smaller' is on");

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

  // Vommet: crop, rotate, draw on or redact here, before the picture is added.
  String get promptEditPicture => Intl.message("Edit picture",
      name: "promptEditPicture",
      desc:
          "Row in the attachment dialog that opens the picture editor (crop, rotate, draw, redact)");

  String get promptUndoEdits => Intl.message("Undo edits",
      name: "promptUndoEdits",
      desc:
          "Button in the attachment dialog that puts the original picture back after editing it");

  // Vommet issue 880: send part of a video as a GIF.
  String get promptConvertToGif => Intl.message("Convert to GIF",
      name: "promptConvertToGif",
      desc:
          "Row in the attachment dialog that opens the Trim for GIF screen for a video");

  String get labelConvertToGifExplain =>
      Intl.message("Sends a short looping GIF instead of the video.",
          name: "labelConvertToGifExplain",
          desc: "Under 'Convert to GIF' in the attachment dialog");

  String labelGifSummary(String length, String size) => Intl.message(
      "GIF · $length s · $size · no sound",
      name: "labelGifSummary",
      args: [length, size],
      desc:
          "Shown once a video was made into a GIF: its length and file size, e.g. GIF · 4.6 s · 2.1 MB · no sound");

  String get promptUseVideoInstead => Intl.message("Send the video instead",
      name: "promptUseVideoInstead",
      desc:
          "Button that undoes 'Convert to GIF' and puts the original video back");

  String get labelGifNoHiddenInfo => Intl.message(
      "No hidden info: the GIF is a new file.",
      name: "labelGifNoHiddenInfo",
      desc:
          "Shown in the attachment dialog for a GIF made from a video, which carries none of the video's metadata");

  /// The video as picked, kept while it is sent as a GIF so Undo can
  /// restore it.
  ({
    String? name,
    String? path,
    Uint8List? data,
    String? mimeType,
    int? size
  })? videoOriginal;

  /// The GIF made from the video, while it is to be sent instead.
  ConvertedGif? gif;

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

  /// Vommet issue 128: send the picture smaller ([shrunk]).
  bool sendSmaller = false;

  /// [sendSmaller] was switched on by the mobile data default.
  bool sendSmallerForMobileData = false;

  /// The switch was changed by hand, so the default no longer applies.
  bool sendSmallerTouched = false;

  /// The smaller picture, once made; null while working or when it can't
  /// be made smaller (see [shrinkDone]).
  ShrunkPicture? shrunk;
  bool shrinkDone = false;
  Future<ShrunkPicture?>? shrinking;
  int shrinkVersion = 0;

  /// Whether the "Send smaller" row shows: a still picture that is being
  /// made smaller, or was.
  bool get showSendSmaller =>
      PictureShrink.canShrink(widget.attachment.mimeType) &&
      (!shrinkDone || shrunk != null);

  bool get sendingSmaller => sendSmaller && showSendSmaller;

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

      if (PictureShrink.canShrink(widget.attachment.mimeType)) {
        initSendSmaller();
        startShrink();
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

  /// Vommet issue 128: the "Send smaller" default from Settings › Data and
  /// storage.
  Future<void> initSendSmaller() async {
    final mode = SendSmallerMode.fromKey(preferences.sendSmallerPictures.value);
    var mobile = false;
    if (mode == SendSmallerMode.mobileData) {
      mobile = await MediaAutoDownload.currentNetwork() != MediaNetwork.wifi;
    }
    if (!mounted || sendSmallerTouched) return;
    setState(() {
      sendSmaller = mode == SendSmallerMode.always || mobile;
      sendSmallerForMobileData = mobile;
    });
  }

  static ShrunkPicture? _shrink((Uint8List, int, String?) args) {
    try {
      return PictureShrink.shrink(args.$1, longestEdge: args.$2, name: args.$3);
    } catch (_) {
      return null;
    }
  }

  /// Makes the smaller picture in the background (again after an edit), so
  /// the saving shows before sending.
  void startShrink() {
    final version = ++shrinkVersion;
    final file = widget.attachment;
    final longestEdge =
        SendSmallerSize.fromKey(preferences.sendSmallerPicturesSize.value)
            .longestEdge;
    shrunk = null;
    shrinkDone = false;
    final future = () async {
      final data = file.data ?? await File(file.path!).readAsBytes();
      return compute(_shrink, (data, longestEdge, file.name));
    }();
    shrinking = future;
    future.then((result) {
      if (!mounted || version != shrinkVersion) return;
      setState(() {
        shrunk = result;
        shrinkDone = true;
      });
    }, onError: (Object _) {
      if (!mounted || version != shrinkVersion) return;
      setState(() => shrinkDone = true);
    });
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
                    if (showSendSmaller) buildSendSmallerRow(),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: canStripMetadata
                          ? buildFileProcessingSwitch()
                          : buildCantStripNotice(),
                    ),
                    if (canStripMetadata && !stripMetadata && !sendingSmaller)
                      buildMetadataDisplay(),
                    if (canMarkSpoiler) buildSpoilerSwitch(),
                    if (isVideo || gif != null) buildGifRow(),
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
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: crop,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              spacing: 10,
              children: [
                Icon(Icons.crop_rotate, size: 20, color: colors.primary),
                Expanded(child: tiamat.Text.label(promptEditPicture)),
                if (cropped)
                  IconButton(
                    tooltip: promptUndoEdits,
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
      if (PictureShrink.canShrink(file.mimeType)) startShrink();
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
      if (PictureShrink.canShrink(file.mimeType)) startShrink();
    });
    loadExif();
  }

  Widget buildGifRow() {
    final colors = Theme.of(context).colorScheme;
    final made = gif;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: made == null ? convertToGif : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              spacing: 10,
              children: [
                Icon(Icons.gif_box_outlined, size: 20, color: colors.primary),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.label(promptConvertToGif),
                      tiamat.Text.labelLow(made == null
                          ? labelConvertToGifExplain
                          : labelGifSummary(
                              (made.length.inMilliseconds / 1000)
                                  .toStringAsFixed(1),
                              FileCache.formatSize(made.data.lengthInBytes))),
                    ],
                  ),
                ),
                if (made != null)
                  IconButton(
                    tooltip: promptUseVideoInstead,
                    icon: const Icon(Icons.undo),
                    onPressed: undoGif,
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

  Future<void> convertToGif() async {
    final file = widget.attachment;
    videoController?.pause();
    final made = await VideoGifTrim.show(context, file);
    if (made == null || !mounted) return;
    setState(() {
      videoOriginal = (
        name: file.name,
        path: file.path,
        data: file.data,
        mimeType: file.mimeType,
        size: file.size
      );
      gif = made;
      file.name = VideoGif.gifName(file.name);
      file.path = null;
      file.data = made.data;
      file.mimeType = "image/gif";
      file.size = made.data.lengthInBytes;
      file.dimensions = Size(made.width.toDouble(), made.height.toDouble());
      file.length = null;
      file.thumbnailFile = null;
      file.thumbnailMime = null;
      previewVersion++;
    });
  }

  void undoGif() {
    final o = videoOriginal;
    if (o == null) return;
    final file = widget.attachment;
    file.name = o.name;
    file.path = o.path;
    file.data = o.data;
    file.mimeType = o.mimeType;
    file.size = o.size;
    file.dimensions = null;
    setState(() {
      videoOriginal = null;
      gif = null;
      // A fresh player for the video preview.
      videoController = VideoPlayerController();
      previewVersion++;
    });
  }

  Widget whatsThis() => InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => MetadataExplainer.show(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(MetadataExplainer.promptWhatsThis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline)),
        ),
      );

  Widget buildSendSmallerRow() {
    final theme = Theme.of(context);
    final small = shrunk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: tiamat.Text.label(promptSendSmaller)),
              tiamat.Switch(
                state: sendSmaller,
                onChanged: (value) => setState(() {
                  sendSmaller = value;
                  sendSmallerTouched = true;
                  sendSmallerForMobileData = false;
                }),
              ),
            ],
          ),
          if (small == null)
            tiamat.Text.labelLow(labelWorkingOutSmallerSize)
          else ...[
            Text(
                labelSmallerSize(FileCache.formatSize(small.originalSize),
                    FileCache.formatSize(small.data.length)),
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: sendSmaller
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant)),
            tiamat.Text.labelLow(labelSmallerDimensions(
                "${small.originalWidth}×${small.originalHeight}",
                "${small.width}×${small.height}",
                small.percentSmaller)),
          ],
          if (sendSmaller && sendSmallerForMobileData)
            tiamat.Text.labelLow(labelSmallerOnMobileData),
        ],
      ),
    );
  }

  Widget buildFileProcessingSwitch() {
    // Vommet issue 128: a smaller picture is re-saved, so it never keeps
    // hidden info.
    final locked = sendingSmaller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: tiamat.Text.label(promptRemoveHiddenInfo)),
            tiamat.Switch(
              state: stripMetadata || locked,
              onChanged: locked
                  ? null
                  : (value) => setState(() {
                        stripMetadata = value;
                      }),
            ),
          ],
        ),
        if (locked)
          tiamat.Text.labelLow(labelHiddenInfoAlwaysRemoved)
        else if (foundInfo.isNotEmpty)
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
            Flexible(
                child: tiamat.Text.labelLow(gif != null
                    ? labelGifNoHiddenInfo
                    : labelCantRemoveHiddenInfo)),
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
    // always try to get metadata when sending a video, regardless of process checkbox
    if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      setState(() {
        processing = true;
      });

      var videoWithThumbnail = await getVideoMetadata();

      Navigator.of(context).pop(withSpoiler(videoWithThumbnail));
      return;
    }

    // Vommet issue 128: the smaller picture was already re-saved without
    // hidden info; if it couldn't be made, the picture goes as it would
    // have.
    if (sendingSmaller) {
      setState(() {
        processing = true;
      });
      ShrunkPicture? small;
      try {
        small = await shrinking;
      } catch (_) {}
      if (!mounted) return;
      if (small != null) {
        final file = PendingFileAttachment(
            name: small.name,
            data: small.data,
            size: small.data.lengthInBytes,
            mimeType: small.mimeType);
        file.dimensions = Size(small.width.toDouble(), small.height.toDouble());
        Navigator.of(context).pop(withSpoiler(file));
        return;
      }
      setState(() {
        processing = false;
      });
    }

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

  Future<PendingFileAttachment> getVideoMetadata() async {
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
