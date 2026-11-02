import 'dart:io';
import 'package:commet/ui/molecules/attachment_order_strip.dart';
import 'dart:ui' as ui;

import 'package:commet/client/attachment.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/media_spoiler_cover.dart';
import 'package:commet/ui/molecules/file_preview.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/utils/attachment_prepare.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/picture_shrink.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What the send screen hands back: the files to send with [caption], or
/// ([send] false) just the caption typed before it was closed.
class MediaSendResult {
  const MediaSendResult(this.files, this.caption, {required this.send});
  final List<PendingFileAttachment> files;
  final String caption;
  final bool send;
}

/// Vommet issue 838: one screen for sending photos and videos on a phone.
/// Everything picked shows at once, with a big preview, a strip with large
/// remove buttons, the caption and Send (kept above the keyboard). Removing
/// hidden info and sending smaller apply to all of them and happen after
/// Send (AttachmentPrepare), so nothing here waits for a picture to be
/// processed.
class MediaSendSheet extends StatefulWidget {
  const MediaSendSheet(
      {required this.files, this.caption = "", this.pickMore, super.key});

  final List<PendingFileAttachment> files;
  final String caption;

  /// Picks more files to add; null hides "Add".
  final Future<List<PendingFileAttachment>> Function()? pickMore;

  static Future<MediaSendResult?> show(BuildContext context,
      {required List<PendingFileAttachment> files,
      String caption = "",
      Future<List<PendingFileAttachment>> Function()? pickMore}) {
    return Navigator.of(context).push<MediaSendResult>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MediaSendSheet(
            files: files, caption: caption, pickMore: pickMore)));
  }

  static String labelSelected(int count) => Intl.message("$count selected",
      name: "mediaSendSheetSelected",
      args: [count],
      desc:
          "Title of the screen for sending photos and videos: how many are picked");

  static String get promptAdd => Intl.message("Add",
      name: "mediaSendSheetAdd",
      desc: "Button on the photo send screen that picks more photos or videos");

  static String get labelCaptionHint => Intl.message("Add a caption…",
      name: "mediaSendSheetCaptionHint",
      desc: "Placeholder of the text box on the photo send screen");

  static String get labelHint =>
      Intl.message("Hold and drag to reorder · tap to preview · ✕ removes it",
          name: "mediaSendSheetHint",
          desc: "Under the row of picked photos on the photo send screen");

  static String get promptRemoveHiddenInfo => Intl.message("Remove hidden info",
      name: "mediaSendSheetRemoveHiddenInfo",
      desc:
          "Switch on the photo send screen: remove location and camera details from every picture when sending");

  static String get promptSendSmaller => Intl.message("Send smaller",
      name: "mediaSendSheetSendSmaller",
      desc:
          "Switch on the photo send screen: re-save every picture smaller when sending");

  static String get labelSmallerOnMobileData => Intl.message(
      "On because you're on mobile data",
      name: "mediaSendSheetSmallerOnMobileData",
      desc: "Says 'Send smaller' was switched on by the mobile data default");

  static String get labelSpoilerOn => Intl.message("Spoiler: on",
      name: "mediaSendSheetSpoilerOn",
      desc:
          "Button on the big preview of the photo send screen; the photo will be sent blurred");

  static String get labelSpoilerOff => Intl.message("Spoiler: off",
      name: "mediaSendSheetSpoilerOff",
      desc:
          "Button on the big preview of the photo send screen; tap to send this photo blurred");

  static String get labelSpoilerReason => Intl.message(
      "Spoiler reason (optional)",
      name: "mediaSendSheetSpoilerReason",
      desc: "Text box under the preview when the photo is marked as a spoiler");

  static String get promptEdit => Intl.message("Crop, draw or redact",
      name: "mediaSendSheetEdit",
      desc:
          "Tooltip of the edit button on the big preview of the photo send screen");

  static String get promptRemove => Intl.message("Remove",
      name: "mediaSendSheetRemove",
      desc: "Tooltip of the X on a picked photo on the photo send screen");

  static String get promptSend => Intl.message("Send",
      name: "mediaSendSheetSend",
      desc: "Tooltip of the send button on the photo send screen");

  @override
  State<MediaSendSheet> createState() => MediaSendSheetState();
}

class MediaSendSheetState extends State<MediaSendSheet> {
  late final List<PendingFileAttachment> files = [...widget.files];
  late final TextEditingController caption =
      TextEditingController(text: widget.caption);
  final Map<PendingFileAttachment, TextEditingController> spoilerReasons = {};
  final Map<PendingFileAttachment, VideoPlayerController> videoControllers = {};
  final Map<PendingFileAttachment, int> previewVersions = {};

  int selected = 0;
  bool removeHiddenInfo = true;
  bool sendSmaller = false;
  bool sendSmallerForMobileData = false;
  bool sendSmallerTouched = false;
  bool sending = false;
  bool dragging = false;
  final orderStrip = GlobalKey<AttachmentOrderStripState>();

  PendingFileAttachment? get current =>
      files.isEmpty ? null : files[selected.clamp(0, files.length - 1)];

  static bool isVideo(PendingFileAttachment f) =>
      Mime.videoTypes.contains(f.mimeType);

  static bool canSpoiler(PendingFileAttachment f) =>
      Mime.imageTypes.contains(f.mimeType) || isVideo(f);

  bool get showHiddenInfoRow =>
      files.any((f) => AttachmentPrepare.canRemoveHiddenInfo(f.mimeType));

  bool get showSendSmallerRow =>
      files.any((f) => PictureShrink.canShrink(f.mimeType));

  @override
  void initState() {
    super.initState();
    for (final f in files) {
      if (isVideo(f)) videoControllers[f] = VideoPlayerController();
    }
    initSendSmaller();
  }

  @override
  void dispose() {
    caption.dispose();
    for (final c in spoilerReasons.values) {
      c.dispose();
    }
    for (final c in videoControllers.values) {
      if (c.attached) c.pause();
    }
    super.dispose();
  }

  /// The "Send smaller" default from Settings › Data and storage (Vommet
  /// issue 128), as the attachment dialog had it.
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

  void close() {
    Navigator.of(context)
        .pop(MediaSendResult(const [], caption.text, send: false));
  }

  void remove(PendingFileAttachment file) {
    if (sending || dragging) return;
    final index = files.indexOf(file);
    if (index < 0) return;
    setState(() {
      files.removeAt(index);
      spoilerReasons.remove(file)?.dispose();
      videoControllers.remove(file);
      if (selected >= index && selected > 0) selected--;
    });
    if (files.isEmpty) close();
  }

  Future<void> addMore() async {
    final more = await widget.pickMore?.call();
    if (more == null || more.isEmpty || !mounted || sending) return;
    // An earlier picker can finish during a drag. Cancel before appending.
    orderStrip.currentState?.cancelDrag();
    setState(() {
      for (final f in more) {
        if (isVideo(f)) videoControllers[f] = VideoPlayerController();
      }
      files.addAll(more);
      selected = files.length - more.length;
    });
  }

  Future<void> edit(PendingFileAttachment file) async {
    if (sending || dragging) return;
    final changed = await AttachmentCrop.cropAttachment(context, file);
    if (!changed || !mounted) return;
    setState(() {
      previewVersions[file] = (previewVersions[file] ?? 0) + 1;
    });
  }

  void toggleSpoiler(PendingFileAttachment file) {
    if (sending || dragging) return;
    setState(() {
      file.spoiler = !file.spoiler;
      if (file.spoiler) spoilerReasons[file] ??= TextEditingController();
    });
  }

  /// A video's preview frame, length and size, read from its player (as
  /// the attachment dialog did). A video never shown is shown briefly so
  /// its player loads.
  Future<void> readVideo(PendingFileAttachment file) async {
    final controller = videoControllers[file];
    if (controller == null) return;
    if (!controller.attached) {
      setState(() => selected = files.indexOf(file));
      for (var i = 0; i < 30 && !controller.attached; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!controller.attached) return;
    }
    const wait = Duration(seconds: 3);
    try {
      file.length = await controller.getLength().timeout(wait);
      file.dimensions = await controller.getSize().timeout(wait);
      final frame = await controller.screenshot().timeout(wait);
      if (frame != null) {
        file.thumbnailFile = frame;
        file.thumbnailMime = Mime.lookupType("", data: frame);
      }
    } catch (_) {
      // Sent without a preview frame, like a video from a share.
    }
  }

  Future<void> send() async {
    if (sending || dragging || files.isEmpty) return;
    final batch = List<PendingFileAttachment>.of(files);
    setState(() => sending = true);

    for (final f in batch) {
      if (isVideo(f) && f.thumbnailFile == null) await readVideo(f);
      if (!mounted) return;
    }

    final longestEdge =
        SendSmallerSize.fromKey(preferences.sendSmallerPicturesSize.value)
            .longestEdge;
    for (final f in batch) {
      f.spoiler = f.spoiler && canSpoiler(f);
      final reason = spoilerReasons[f]?.text.trim() ?? "";
      f.spoilerReason = f.spoiler && reason.isNotEmpty ? reason : null;
      f.removeHiddenInfo = removeHiddenInfo;
      f.shrinkLongestEdge = sendSmaller ? longestEdge : null;
    }
    Navigator.of(context).pop(MediaSendResult(batch, caption.text, send: true));
  }

  @override
  Widget build(BuildContext context) {
    final file = current;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !sending) close();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
              key: const ValueKey("media-send-close"),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close),
              onPressed: sending ? null : close),
          centerTitle: true,
          title: Text(MediaSendSheet.labelSelected(files.length)),
          actions: [
            if (widget.pickMore != null)
              TextButton.icon(
                  key: const ValueKey("media-send-add"),
                  onPressed: sending || dragging ? null : addMore,
                  icon: const Icon(Icons.add),
                  label: Text(MediaSendSheet.promptAdd)),
          ],
          bottom: sending
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2))
              : null,
        ),
        body: SafeArea(
          child: IgnorePointer(
            ignoring: sending,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: file == null
                        ? const SizedBox.shrink()
                        : buildPreview(file)),
                if (file != null && file.spoiler) buildSpoilerReason(file),
                buildStrip(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                      child: tiamat.Text.labelLow(MediaSendSheet.labelHint)),
                ),
                if (showHiddenInfoRow || showSendSmallerRow)
                  const Divider(height: 16, indent: 16, endIndent: 16),
                if (showHiddenInfoRow)
                  buildSwitchRow(
                      MediaSendSheet.promptRemoveHiddenInfo,
                      // A smaller picture is re-saved, so it never keeps
                      // hidden info.
                      removeHiddenInfo || sendSmaller,
                      sendSmaller
                          ? null
                          : (v) => setState(() => removeHiddenInfo = v)),
                if (showSendSmallerRow)
                  buildSwitchRow(
                      MediaSendSheet.promptSendSmaller,
                      sendSmaller,
                      (v) => setState(() {
                            sendSmaller = v;
                            sendSmallerTouched = true;
                            sendSmallerForMobileData = false;
                          }),
                      note: sendSmaller && sendSmallerForMobileData
                          ? MediaSendSheet.labelSmallerOnMobileData
                          : null),
                buildCaptionRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPreview(PendingFileAttachment file) {
    final reason = spoilerReasons[file]?.text.trim() ?? "";
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: FilePreview(
                key: ValueKey(
                    (identityHashCode(file), previewVersions[file] ?? 0)),
                mimeType: file.mimeType,
                path: file.path,
                data: file.data,
                videoController: videoControllers[file],
              ),
            ),
            if (file.spoiler)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                          sigmaX: 26, sigmaY: 26, tileMode: TileMode.mirror),
                      child: ColoredBox(
                        color: Colors.black.withAlpha(60),
                        child: Center(
                            child: MediaSpoilerPill(
                                reason: reason.isEmpty ? null : reason)),
                      ),
                    ),
                  ),
                ),
              ),
            if (canSpoiler(file))
              Positioned(
                left: 8,
                bottom: 8,
                child: pill(
                    key: const ValueKey("media-send-spoiler"),
                    onTap: () => toggleSpoiler(file),
                    child: Text(
                        file.spoiler
                            ? MediaSendSheet.labelSpoilerOn
                            : MediaSendSheet.labelSpoilerOff,
                        style: const TextStyle(color: Colors.white))),
              ),
            if (AttachmentCrop.canCrop(file))
              Positioned(
                right: 8,
                bottom: 8,
                child: Tooltip(
                  message: MediaSendSheet.promptEdit,
                  child: pill(
                      key: const ValueKey("media-send-edit"),
                      onTap: () => edit(file),
                      child: const Icon(Icons.edit_outlined,
                          color: Colors.white, size: 20)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget pill(
      {required Key key,
      required Widget child,
      required void Function() onTap}) {
    return Material(
      key: key,
      color: Colors.black.withAlpha(150),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
  }

  Widget buildSpoilerReason(PendingFileAttachment file) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        key: const ValueKey("media-send-spoiler-reason"),
        controller: spoilerReasons[file] ??= TextEditingController(),
        maxLength: 200,
        maxLines: 1,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: MediaSendSheet.labelSpoilerReason,
          counterText: "",
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  void moveFile(PendingFileAttachment file, int position) {
    if (sending) return;
    final index = files.indexOf(file);
    if (index < 0 || position < 0 || position >= files.length) return;
    final preview = current;
    setState(() {
      files.removeAt(index);
      files.insert(position, file);
      selected = preview == null ? 0 : files.indexOf(preview);
    });
  }

  /// The order, including generic files, is the order submitted on Send.
  Widget buildStrip() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (files.length > 1)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(AttachmentOrderStrip.orderHint,
                  style: Theme.of(context).textTheme.labelSmall)),
        AttachmentOrderStrip(
            key: orderStrip,
            files: files,
            onMove: moveFile,
            itemWidth: 88,
            height: 92,
            badgeOnThumbnail: true,
            enabled: !sending,
            trailing: widget.pickMore == null
                ? null
                : Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                    child: OutlinedButton(
                        key: const ValueKey("media-send-add-tile"),
                        style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        onPressed: sending || dragging ? null : addMore,
                        child: const Icon(Icons.add))),
            onDraggingChanged: (value) {
              if (mounted) setState(() => dragging = value);
            },
            itemBuilder: (index, dragTarget) =>
                buildTile(index, files[index], dragTarget: dragTarget)),
      ]);

  Widget buildTile(int index, PendingFileAttachment file,
      {Widget Function(Widget)? dragTarget}) {
    final colors = Theme.of(context).colorScheme;
    final isSelected = index == selected;
    ImageProvider? image;
    if (file.thumbnailFile != null) {
      image = MemoryImage(file.thumbnailFile!);
    } else if (Mime.displayableImageTypes.contains(file.mimeType)) {
      image = ResizeImage(
          file.data != null
              ? MemoryImage(file.data!)
              : FileImage(File(file.path!)) as ImageProvider,
          width: 192);
    }
    return SizedBox(
      key: ValueKey(("media-send-tile", index)),
      width: 88,
      height: 92,
      child: Stack(
        children: [
          Positioned(
            left: 4,
            bottom: 4,
            child: (dragTarget ?? (child) => child)(GestureDetector(
              onTap: () => setState(() => selected = index),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isSelected ? colors.primary : Colors.transparent,
                      width: 3),
                  color: colors.surfaceContainerHighest,
                  image: image == null
                      ? null
                      : DecorationImage(image: image, fit: BoxFit.cover),
                ),
                child: image == null || isVideo(file)
                    ? Icon(Mime.toIcon(file.mimeType),
                        color: image == null
                            ? colors.onSurfaceVariant
                            : Colors.white)
                    : null,
              ),
            )),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Tooltip(
              message: MediaSendSheet.promptRemove,
              child: InkResponse(
                key: ValueKey(("media-send-remove", index)),
                radius: 22,
                onTap: () => remove(file),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                          color: Colors.black.withAlpha(190),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70)),
                      child: const Icon(Icons.close,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSwitchRow(
      String label, bool value, void Function(bool)? onChanged,
      {String? note}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.label(label),
                if (note != null) tiamat.Text.labelLow(note),
              ],
            ),
          ),
          tiamat.Switch(state: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget buildCaptionRow() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 8,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey("media-send-caption"),
              controller: caption,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: MediaSendSheet.labelCaptionHint,
                filled: true,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Badge(
            label: Text("${files.length}"),
            isLabelVisible: files.length > 1,
            child: IconButton.filled(
              key: const ValueKey("media-send-send"),
              tooltip: MediaSendSheet.promptSend,
              iconSize: 24,
              style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary),
              onPressed: files.isEmpty || dragging || sending ? null : send,
              icon: const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }
}
