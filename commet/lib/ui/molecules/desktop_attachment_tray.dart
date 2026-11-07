import 'dart:io';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/drag_drop_file_target.dart';
import 'package:commet/ui/molecules/attachment_icon.dart';
import 'package:commet/ui/molecules/attachment_order_strip.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:commet/utils/attachment_prepare.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/picture_shrink.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 1066: on desktop and the web, files that are attached,
/// dropped or pasted skip the per-file dialog and wait in this tray above
/// the composer. Whatever is typed is their caption and one Send sends them
/// all. "Remove hidden info" and "Send smaller" apply to every picture and
/// run after Send (AttachmentPrepare), as on the phone send screen (Vommet
/// issue 838). A picture opens a big preview; a video or other file is a
/// tile with its name, and [onOpen] opens its dialog (Convert to GIF, the
/// video's preview frame).
class DesktopAttachmentTray extends StatefulWidget {
  const DesktopAttachmentTray({
    required this.files,
    required this.onRemove,
    required this.onMove,
    this.room,
    this.onOpen,
    this.enabled = true,
    this.onDraggingChanged,
    super.key,
  });

  // Vommet issue 1056.
  final Room? room;
  final List<PendingFileAttachment> files;
  final void Function(PendingFileAttachment file) onRemove;
  final void Function(PendingFileAttachment file, int position) onMove;

  /// Opens the attachment dialog for a file that isn't a picture.
  final Future<void> Function(PendingFileAttachment file)? onOpen;
  final bool enabled;
  final ValueChanged<bool>? onDraggingChanged;

  static const double tileWidth = 112;
  static const double tileHeight = 88;

  /// Desktop and the web; phones use the send screen.
  static bool get platform =>
      PlatformUtils.isWeb || !(PlatformUtils.isAndroid || PlatformUtils.isIOS);

  /// Whether [file] goes straight to the tray instead of the dialog: any
  /// file on desktop and the web.
  static bool handles(PendingFileAttachment file) => platform;

  static bool isPicture(PendingFileAttachment file) =>
      Mime.imageTypes.contains(file.mimeType);

  static bool canSpoiler(PendingFileAttachment file) =>
      isPicture(file) || Mime.videoTypes.contains(file.mimeType);

  /// The composer's shape: square corners in Discord style, round in
  /// Telegram style and a Custom mix (whose composer is round too).
  static double cornerRadius(LayoutStyle style) =>
      style == LayoutStyle.discord ? 8 : 20;

  /// A pasted picture arrives as bytes only: give it a type and a name.
  static void nameAnonymous(PendingFileAttachment file) {
    final data = file.data;
    if (file.mimeType == null && data != null) {
      file.mimeType = Mime.lookupType("", data: data);
    }
    final type = file.mimeType;
    if ((file.name == null || file.name!.isEmpty) && type != null) {
      file.name = "image.${type.split("/").last}";
    }
  }

  /// Gives a picture the tray's settings: those of the pictures already in
  /// [pending], else hidden info removed and "Send smaller" from Settings ›
  /// Data and storage (Vommet issue 128). Other files are sent as they are.
  static Future<void> applySettings(PendingFileAttachment file,
      Iterable<PendingFileAttachment> pending) async {
    if (!isPicture(file)) return;
    final other = pending.where((f) => f != file && isPicture(f)).firstOrNull;
    if (other != null) {
      file.removeHiddenInfo = other.removeHiddenInfo;
      file.shrinkLongestEdge = other.shrinkLongestEdge;
      return;
    }
    file.removeHiddenInfo = true;
    final mode = SendSmallerMode.fromKey(preferences.sendSmallerPictures.value);
    var smaller = mode == SendSmallerMode.always;
    if (mode == SendSmallerMode.mobileData) {
      smaller = await MediaAutoDownload.currentNetwork() != MediaNetwork.wifi;
    }
    file.shrinkLongestEdge = smaller ? longestEdge : null;
  }

  static int get longestEdge =>
      SendSmallerSize.fromKey(preferences.sendSmallerPicturesSize.value)
          .longestEdge;

  static String labelCount(int count) => Intl.plural(count,
      one: "1 file",
      other: "$count files",
      name: "desktopTrayFileCount",
      args: [count],
      desc: "Header of the files waiting above the message box on desktop");

  static String get promptClearAll => Intl.message("Clear all",
      name: "desktopTrayClearAll",
      desc:
          "Button above the message box on desktop that removes every waiting file");

  static String get labelDropHere => Intl.message("Drop to add",
      name: "desktopTrayDropHere",
      desc:
          "Empty slot in the files waiting above the message box on desktop while files are dragged over the window");

  @override
  State<DesktopAttachmentTray> createState() => _DesktopAttachmentTrayState();
}

class _DesktopAttachmentTrayState extends State<DesktopAttachmentTray> {
  List<PendingFileAttachment> get files => widget.files;

  Iterable<PendingFileAttachment> get pictures =>
      files.where(DesktopAttachmentTray.isPicture);

  /// Bumped when a picture is cropped, so its tile reloads.
  final Map<PendingFileAttachment, int> versions = {};

  bool get removeHiddenInfo => pictures
      .where((f) => AttachmentPrepare.canRemoveHiddenInfo(f.mimeType))
      .every((f) => f.removeHiddenInfo);

  bool get sendSmaller => pictures
      .where((f) => PictureShrink.canShrink(f.mimeType))
      .every((f) => f.shrinkLongestEdge != null);

  bool get showHiddenInfo =>
      pictures.any((f) => AttachmentPrepare.canRemoveHiddenInfo(f.mimeType));

  bool get showSendSmaller =>
      pictures.any((f) => PictureShrink.canShrink(f.mimeType));

  void setRemoveHiddenInfo(bool value) => setState(() {
        for (final f in pictures) {
          f.removeHiddenInfo = value;
        }
      });

  void setSendSmaller(bool value) => setState(() {
        final edge = DesktopAttachmentTray.longestEdge;
        for (final f in pictures) {
          f.shrinkLongestEdge = value ? edge : null;
        }
      });

  void toggleSpoiler(PendingFileAttachment file) =>
      setState(() => file.spoiler = !file.spoiler);

  Future<void> open(PendingFileAttachment file) async {
    if (!widget.enabled) return;
    if (!DesktopAttachmentTray.isPicture(file)) {
      await widget.onOpen?.call(file);
      if (mounted) setState(() {});
      return;
    }
    await showDialog<void>(
        context: context,
        builder: (context) => DesktopAttachmentPreview(file,
            room: widget.room,
            onChanged: () =>
                setState(() => versions[file] = (versions[file] ?? 0) + 1)));
    if (mounted) setState(() {});
  }

  void clearAll() {
    for (final f in List.of(files)) {
      widget.onRemove(f);
    }
  }

  Widget toggle(
          Key key, String label, bool value, ValueChanged<bool> onChanged) =>
      Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        Switch(
            key: key,
            value: value,
            onChanged: widget.enabled ? onChanged : null),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ]);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
        valueListenable: DragDropFileTarget.filesHovering,
        builder: (context, hovering, _) => buildTray(context, hovering));
  }

  Widget buildTray(BuildContext context, bool hovering) {
    final scheme = ColorScheme.of(context);
    final multiple = files.length > 1;
    return Container(
      key: const ValueKey("desktop-attachment-tray"),
      margin: const EdgeInsets.fromLTRB(0, 2, 0, 6),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border.all(
              color: hovering ? scheme.primary : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(
              DesktopAttachmentTray.cornerRadius(currentLayoutStyle))),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                children: [
                  Text(DesktopAttachmentTray.labelCount(files.length),
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (showHiddenInfo)
                    toggle(
                        const ValueKey("desktop-tray-hidden-info"),
                        MediaSendSheet.promptRemoveHiddenInfo,
                        removeHiddenInfo,
                        setRemoveHiddenInfo),
                  if (showSendSmaller)
                    toggle(
                        const ValueKey("desktop-tray-send-smaller"),
                        MediaSendSheet.promptSendSmaller,
                        sendSmaller,
                        setSendSmaller),
                  if (multiple)
                    Tooltip(
                        message: AttachmentOrderStrip.dragHint,
                        child: Text(AttachmentOrderStrip.orderHint,
                            style: Theme.of(context).textTheme.labelSmall)),
                  TextButton(
                      key: const ValueKey("desktop-tray-clear-all"),
                      onPressed: widget.enabled ? clearAll : null,
                      child: Text(DesktopAttachmentTray.promptClearAll)),
                ]),
            AttachmentOrderStrip(
              files: files,
              enabled: widget.enabled,
              itemWidth: DesktopAttachmentTray.tileWidth + 8,
              height: DesktopAttachmentTray.tileHeight + (multiple ? 40 : 8),
              onMove: widget.onMove,
              onDraggingChanged: widget.onDraggingChanged,
              itemBuilder: (index, dragTarget) =>
                  tile(files[index], dragTarget),
              trailing: hovering ? dropSlot(scheme) : null,
            ),
          ]),
    );
  }

  /// Where dragged files will land, while they are over the window.
  Widget dropSlot(ColorScheme scheme) => Padding(
        key: const ValueKey("desktop-tray-drop-slot"),
        padding: const EdgeInsets.all(4),
        child: Container(
          width: DesktopAttachmentTray.tileWidth,
          height: DesktopAttachmentTray.tileHeight,
          decoration: BoxDecoration(
              color: scheme.primary.withAlpha(30),
              border: Border.all(color: scheme.primary, width: 2),
              borderRadius: BorderRadius.circular(8)),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 4,
              children: [
                Icon(Icons.add_rounded, color: scheme.primary),
                Text(DesktopAttachmentTray.labelDropHere,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: scheme.primary)),
              ]),
        ),
      );

  /// A file that isn't a picture: its icon, with its name below.
  Widget fileName(PendingFileAttachment file) => Positioned(
        left: DesktopAttachmentTray.canSpoiler(file) ? 30 : 6,
        right: 6,
        bottom: 4,
        child: IgnorePointer(
          child: Text(file.name ?? "",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall),
        ),
      );

  Widget tile(PendingFileAttachment file, Widget Function(Widget) dragTarget) {
    final canSpoiler = DesktopAttachmentTray.canSpoiler(file);
    final scheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        width: DesktopAttachmentTray.tileWidth,
        height: DesktopAttachmentTray.tileHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(children: [
            Positioned.fill(
                child: AttachmentIcon(file,
                    // A crop in the preview changes the picture; a new key
                    // reloads it.
                    key: ValueKey((file, versions[file] ?? 0)),
                    dragTarget: dragTarget,
                    badgeSize: 24,
                    onOpen: DesktopAttachmentTray.isPicture(file) ||
                            widget.onOpen != null
                        ? () => open(file)
                        : null,
                    removeAttachment: () => widget.onRemove(file))),
            if (!DesktopAttachmentTray.isPicture(file)) fileName(file),
            if (file.spoiler)
              Positioned.fill(
                  child: IgnorePointer(
                      child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.55),
                          child: const Icon(Icons.visibility_off_rounded,
                              color: Colors.white)))),
            if (canSpoiler)
              Positioned(
                left: 2,
                bottom: 2,
                child: Tooltip(
                  message: file.spoiler
                      ? MediaSendSheet.labelSpoilerOn
                      : MediaSendSheet.labelSpoilerOff,
                  child: Material(
                    color: file.spoiler
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest.withAlpha(230),
                    shape: const CircleBorder(),
                    child: InkWell(
                      key: ValueKey(
                          "desktop-tray-spoiler-${files.indexOf(file)}"),
                      customBorder: const CircleBorder(),
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      onTap: widget.enabled ? () => toggleSpoiler(file) : null,
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: Icon(
                              file.spoiler
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 16,
                              color: file.spoiler
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurface)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Vommet issue 1066: a picture from the desktop tray, big. Hovering shows
/// "Crop, draw or redact" and the spoiler switch (a tap shows them without
/// a mouse).
class DesktopAttachmentPreview extends StatefulWidget {
  const DesktopAttachmentPreview(this.file,
      {this.onChanged, this.room, super.key});

  // Vommet issue 1056.
  final Room? room;
  final PendingFileAttachment file;

  /// The picture was cropped or its spoiler mark changed.
  final VoidCallback? onChanged;

  @override
  State<DesktopAttachmentPreview> createState() =>
      _DesktopAttachmentPreviewState();
}

class _DesktopAttachmentPreviewState extends State<DesktopAttachmentPreview> {
  PendingFileAttachment get file => widget.file;
  bool showTools = false;
  int version = 0;

  Future<void> crop() async {
    final changed =
        await AttachmentCrop.cropAttachment(context, file, room: widget.room);
    if (!changed || !mounted) return;
    setState(() => version++);
    widget.onChanged?.call();
  }

  void toggleSpoiler() {
    setState(() => file.spoiler = !file.spoiler);
    widget.onChanged?.call();
  }

  Widget picture() {
    Widget error(BuildContext context, Object _, StackTrace? __) =>
        Icon(Mime.toIcon(file.mimeType), size: 64);
    final data = file.data;
    if (data != null) {
      return Image.memory(data,
          key: ValueKey(version), fit: BoxFit.contain, errorBuilder: error);
    }
    final path = file.path;
    if (path != null && !PlatformUtils.isWeb) {
      return Image.file(File(path),
          key: ValueKey(version), fit: BoxFit.contain, errorBuilder: error);
    }
    return error(context, Object(), null);
  }

  Widget tool(Key key, IconData icon, String label, VoidCallback onPressed,
          {bool selected = false}) =>
      FilledButton.tonalIcon(
          key: key,
          style: selected
              ? FilledButton.styleFrom(
                  backgroundColor: ColorScheme.of(context).primaryContainer)
              : null,
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey("desktop-tray-preview"),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: size.width * 0.8, maxHeight: size.height * 0.8),
        child: MouseRegion(
          onEnter: (_) => setState(() => showTools = true),
          onExit: (_) => setState(() => showTools = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => showTools = !showTools),
            child: Stack(children: [
              Center(child: picture()),
              if (file.spoiler)
                Positioned.fill(
                    child: IgnorePointer(
                        child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                            child: const Icon(Icons.visibility_off_rounded,
                                size: 48, color: Colors.white)))),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                    key: const ValueKey("desktop-preview-close"),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: IgnorePointer(
                  ignoring: !showTools,
                  child: AnimatedOpacity(
                    opacity: showTools ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (AttachmentCrop.canCrop(file))
                            tool(const ValueKey("desktop-preview-crop"),
                                Icons.crop, MediaSendSheet.promptEdit, crop),
                          tool(
                              const ValueKey("desktop-preview-spoiler"),
                              file.spoiler
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              file.spoiler
                                  ? MediaSendSheet.labelSpoilerOn
                                  : MediaSendSheet.labelSpoilerOff,
                              toggleSpoiler,
                              selected: file.spoiler),
                        ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
