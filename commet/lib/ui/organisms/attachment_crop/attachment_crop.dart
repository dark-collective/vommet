// Vommet: crop or rotate a picture in the composer before sending it, and
// draw on it or redact parts of it (Vommet issue 383).
import 'dart:async';
import 'dart:ui' as ui;

// Vommet issue 1056: account/room pack selection and still-photo overlays.
import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/organisms/attachment_crop/image_markup.dart';
import 'package:commet/ui/organisms/attachment_crop/photo_overlay_asset.dart';
import 'package:commet/ui/organisms/attachment_crop/photo_overlay_canvas.dart';
import 'package:commet/ui/organisms/attachment_crop/photo_overlay_picker.dart';
import 'package:commet/utils/mime.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:tiamat/tiamat.dart' as tiamat;

class AttachmentCrop {
  static String get labelEditPicture => Intl.message("Edit picture",
      name: "labelEditPicture",
      desc:
          "Title of the picture editor (crop, draw, redact) shown before sending a picture");

  /// GIFs lose their animation when cropped, so they are left alone.
  static bool canCrop(PendingFileAttachment attachment) =>
      Mime.imageTypes.contains(attachment.mimeType) &&
      attachment.mimeType != "image/gif";

  /// Opens the crop editor and, on Done, replaces the attachment's data in
  /// place. Returns true when the picture changed.
  static Future<bool> cropAttachment(
      BuildContext context, PendingFileAttachment attachment,
      {Room? room}) async {
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

    final encoded = await showGeneralDialog<
            ({Uint8List data, String mimeType, String name})>(
        context: context,
        barrierDismissible: true,
        barrierLabel: "POPUP_DIALOG",
        barrierColor: tiamat.PopupDialog.barrierColor,
        pageBuilder: (context, _, __) =>
            _AttachmentCropDialog(bytes, ratio, room, attachment.name),
        transitionDuration: const Duration(milliseconds: 300),
        transitionBuilder: (context, animation, _, child) => SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ));
    if (encoded == null) return false;

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

  /// Paints [edits] into [image] at full resolution, then crops and rotates
  /// it the way the crop view shows. The caller owns the result.
  static Future<ui.Image> render(ui.Image image, List<MarkupEdit> edits,
      {required Rect crop, required CropRotation rotation}) async {
    if (edits.isEmpty) {
      return CropController.getCroppedBitmap(
          crop: crop, rotation: rotation, image: image);
    }
    await ImageMarkup.ensurePatches(image, edits);
    final flat = await ImageMarkup.flatten(image, edits);
    try {
      return await CropController.getCroppedBitmap(
          crop: crop, rotation: rotation, image: flat);
    } finally {
      flat.dispose();
    }
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

/// The editor inside the dialog route. Owns the crop controller so it is
/// disposed only once the route is gone, not while it still slides out
/// (Vommet issue 703).
class _AttachmentCropDialog extends StatefulWidget {
  const _AttachmentCropDialog(this.bytes, this.ratio, this.room, this.name);
  final String? name;

  final Room? room;

  final Uint8List bytes;
  final double ratio;

  @override
  State<_AttachmentCropDialog> createState() => _AttachmentCropDialogState();
}

class _AttachmentCropDialogState extends State<_AttachmentCropDialog> {
  final _controller = CropController();
  final _fullscreen = ValueNotifier(false);
  // Keeps the editor's state when it moves between the two dialog shapes.
  final _viewKey = GlobalKey();

  @override
  void dispose() {
    _controller.dispose();
    _fullscreen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
        valueListenable: _fullscreen,
        builder: (context, full, _) {
          final view = AttachmentCropView(
            widget.bytes,
            _controller,
            widget.ratio,
            key: _viewKey,
            room: widget.room,
            fullscreen: full,
            onToggleFullscreen: () => _fullscreen.value = !full,
            onDone: (image) async {
              try {
                final encoded =
                    await AttachmentCrop.encodeCropped(image, widget.name);
                if (context.mounted &&
                    ModalRoute.of(context)?.isCurrent == true)
                  Navigator.of(context).pop(encoded);
              } finally {
                image.dispose();
              }
            },
          );
          if (!full) {
            return tiamat.PopupDialog(
                title: AttachmentCrop.labelEditPicture, content: view);
          }
          return Dialog.fullscreen(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text(AttachmentCrop.labelEditPicture,
                          style: Theme.of(context).textTheme.headlineSmall),
                    ),
                    Expanded(child: view),
                  ],
                ),
              ),
            ),
          );
        });
  }
}

enum AttachmentEditTool { crop, draw, redact, stickers }

/// Smallest crop box, in layout pixels of the shown picture. crop_image's
/// default of 100 was too big to cut out a single button from a screenshot
/// (Vommet issue 839).
const double attachmentMinimumCropSize = 20;

class AttachmentCropView extends StatefulWidget {
  const AttachmentCropView(this.imageBytes, this.controller, this.imageRatio,
      {required this.onDone,
      this.room,
      this.overlayLoader = PhotoOverlayAsset.load,
      this.fullscreen = false,
      this.onToggleFullscreen,
      super.key});

  final Room? room;
  final Future<ui.Image> Function(Emoticon) overlayLoader;
  final Uint8List imageBytes;
  final CropController controller;
  final double imageRatio;
  final FutureOr<void> Function(ui.Image image) onDone;

  /// Fill the space the view is given instead of sizing to the picture.
  final bool fullscreen;

  /// Shows the fullscreen toggle (Vommet issue 703).
  final VoidCallback? onToggleFullscreen;

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
      desc: "Crop editor button: undo the crop, rotation and all drawing");

  String get promptCropDone => Intl.message("Done",
      name: "promptCropDone",
      desc: "Crop editor button: use the edited picture");

  String get labelCropRotateLeft => Intl.message("Rotate left",
      name: "labelCropRotateLeft",
      desc: "Tooltip of the crop editor's rotate-left button");

  String get labelCropRotateRight => Intl.message("Rotate right",
      name: "labelCropRotateRight",
      desc: "Tooltip of the crop editor's rotate-right button");

  String get labelEditToolCrop => Intl.message("Crop",
      name: "labelEditToolCrop",
      desc: "Picture editor tool: crop and rotate the picture");

  String get labelEditToolDraw => Intl.message("Draw",
      name: "labelEditToolDraw",
      desc: "Picture editor tool: draw freehand lines on the picture");

  String get labelEditToolRedact => Intl.message("Redact",
      name: "labelEditToolRedact",
      desc:
          "Picture editor tool: drag a box over part of the picture to hide it");

  String get labelRedactColor => Intl.message("Color",
      name: "labelRedactColor",
      desc:
          "Redact tool choice: hide the area under a solid box of the chosen color");

  String get labelRedactPixelate => Intl.message("Pixelate",
      name: "labelRedactPixelate",
      desc: "Redact tool choice: hide the area by pixelating it");

  String get labelRedactBlur => Intl.message("Blur",
      name: "labelRedactBlur",
      desc: "Redact tool choice: hide the area by blurring it");

  String get labelRedactHint => Intl.message(
      "Drag over what to hide. It is covered by a solid box in the picture you send.",
      name: "labelRedactHint",
      desc:
          "Hint shown under the picture while the redact tool is set to color");

  String get labelRedactScrambledHint => Intl.message(
      "Drag over what to hide. It is scrambled first, so it can't be restored from the picture you send.",
      name: "labelRedactScrambledHint",
      desc:
          "Hint shown under the picture while the redact tool is set to pixelate or blur");

  String get labelEditUndo => Intl.message("Undo",
      name: "labelEditUndo",
      desc:
          "Tooltip of the picture editor's undo button (drawing and redacting)");

  String get labelPenColor => Intl.message("Pen color",
      name: "labelPenColor",
      desc: "Tooltip of a color swatch for the picture editor's pen");

  String get labelRedactBoxColor => Intl.message("Box color",
      name: "labelRedactBoxColor",
      desc:
          "Tooltip of a color swatch for the box the picture editor's redact tool draws");

  String get labelZoomIn => Intl.message("Zoom in",
      name: "labelPictureZoomIn",
      desc: "Tooltip of the picture editor's zoom-in button");

  String get labelZoomOut => Intl.message("Zoom out",
      name: "labelPictureZoomOut",
      desc: "Tooltip of the picture editor's zoom-out button");

  String get labelFullscreen => Intl.message("Full screen",
      name: "labelPictureEditorFullscreen",
      desc:
          "Tooltip of the picture editor's button that makes it fill the screen");

  String get labelExitFullscreen => Intl.message("Exit full screen",
      name: "labelPictureEditorExitFullscreen",
      desc:
          "Tooltip of the picture editor's button that shrinks it back to a dialog");

  static const double maxZoom = 8;
  static const double zoomStep = 1.5;

  /// Zooms the picture for all three tools. The tools' gestures sit inside
  /// the zoomed view, so they get positions on the picture, not the screen.
  final zoom = TransformationController();
  final zoomViewKey = GlobalKey();

  double? ratio;
  bool busy = false;
  AttachmentEditTool tool = AttachmentEditTool.crop;
  Color penColor = ImageMarkup.penColors.first;
  RedactionStyle redactStyle = RedactionStyle.pixelate;
  Color redactColor = ImageMarkup.redactionColor;
  final markup = ImageMarkup();
  final overlayFocus = FocusNode();
  MarkupOverlay? selected;
  Rect? sizeBefore;
  String? exportError;
  late final bool overlaysAllowed = () {
    try {
      return PhotoOverlayAsset.isStill(widget.imageBytes);
    } catch (_) {
      return false;
    }
  }();

  String get exportFailed => Intl.message(
      "Couldn't export this picture. Your edits are kept; try Done again.",
      name: 'photoOverlayExportFailed');
  String get removeOverlay =>
      Intl.message('Remove', name: 'photoOverlayRemove');
  String get overlaySize => Intl.message('Size', name: 'photoOverlaySize');
  String get overlayHint =>
      Intl.message('Drag to move. Drag the corner or use Size to resize.',
          name: 'photoOverlayHint');
  String get overlaysUnavailable => Intl.message(
      'Overlays are available for still JPEG, PNG and WebP photos.',
      name: 'photoOverlayUnavailable');

  Future<void> addOverlay() async {
    final image = await showDialog<ui.Image>(
        context: context,
        builder: (context) => Dialog(
            child: SizedBox(
                width: 650,
                height: MediaQuery.sizeOf(context).height * .7,
                child: PhotoOverlayPicker(
                    room: widget.room, loadAsset: widget.overlayLoader))));
    if (image == null) return;
    if (!mounted) {
      image.dispose();
      return;
    }
    final source = widget.controller.getImage();
    if (source == null) {
      image.dispose();
      return;
    }
    final crop = ImageMarkup.mapRect(widget.controller.crop,
        (p) => ImageMarkup.unrotate(p, widget.controller.rotation));
    final shortSide = [crop.width * source.width, crop.height * source.height]
            .reduce((a, b) => a < b ? a : b) *
        .25;
    final factor =
        shortSide / (image.width > image.height ? image.width : image.height);
    final sideways = widget.controller.rotation.isSideways;
    final e = MarkupOverlay(
        image,
        Rect.fromCenter(
            center: crop.center,
            width:
                (sideways ? image.height : image.width) * factor / source.width,
            height: (sideways ? image.width : image.height) *
                factor /
                source.height),
        orientation: widget.controller.rotation);
    markup.add(e);
    setState(() => selected = e);
    overlayFocus.requestFocus();
  }

  Widget overlayOptions() => ListenableBuilder(
      listenable: markup,
      builder: (context, _) {
        final e = selected;
        final active = !busy && e != null && markup.edits.contains(e);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(overlaysAllowed ? overlayHint : overlaysUnavailable,
              textAlign: TextAlign.center),
          Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                    onPressed: !busy && overlaysAllowed ? addOverlay : null,
                    icon: const Icon(Icons.add),
                    label: Text(PhotoOverlayPicker.add)),
                TextButton(
                    onPressed: active
                        ? () {
                            markup.removeOverlay(e);
                            setState(() => selected = null);
                          }
                        : null,
                    child: Text(removeOverlay)),
                undoButton(),
                Text(overlaySize),
                SizedBox(
                    width: 150,
                    child: Slider(
                        label: overlaySize,
                        min: .02,
                        max: 1,
                        value: active ? e.rect.width.clamp(.02, 1) : .1,
                        onChangeStart:
                            active ? (_) => sizeBefore = e.rect : null,
                        onChanged: active
                            ? (w) {
                                final h = w * e.rect.height / e.rect.width;
                                final factor = [1.0, 1 / w, 1 / h]
                                    .reduce((a, b) => a < b ? a : b);
                                final width = w * factor, height = h * factor;
                                markup.transformOverlay(
                                    e,
                                    Rect.fromLTWH(
                                        e.rect.left.clamp(0, 1 - width),
                                        e.rect.top.clamp(0, 1 - height),
                                        width,
                                        height));
                              }
                            : null,
                        onChangeEnd: active
                            ? (_) {
                                markup.transformOverlay(e, e.rect,
                                    before: sizeBefore);
                                sizeBefore = null;
                              }
                            : null)),
              ]),
        ]);
      });

  @override
  void dispose() {
    zoom.dispose();
    overlayFocus.dispose();
    markup.dispose();
    super.dispose();
  }

  /// Zooms by [factor] around the middle of the view, keeping the picture
  /// filling the view.
  void zoomBy(double factor) {
    final size = zoomViewKey.currentContext?.size;
    if (size == null) return;
    final m = zoom.value;
    final scale = m.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, maxZoom);
    final center = size.center(Offset.zero);
    final translation = Offset(m.getTranslation().x, m.getTranslation().y);
    // The picture point under the middle of the view stays there.
    final point = (center - translation) / scale;
    final t = center - point * next;
    zoom.value = Matrix4.diagonal3Values(next, next, 1)
      ..setTranslationRaw(t.dx.clamp(size.width * (1 - next), 0.0),
          t.dy.clamp(size.height * (1 - next), 0.0), 0);
  }

  Widget zoomControls() => ListenableBuilder(
        listenable: zoom,
        builder: (context, _) {
          final scale = zoom.value.getMaxScaleOnAxis();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: labelZoomOut,
                icon: const Icon(Icons.zoom_out),
                onPressed: scale <= 1.001 ? null : () => zoomBy(1 / zoomStep),
              ),
              IconButton(
                tooltip: labelZoomIn,
                icon: const Icon(Icons.zoom_in),
                onPressed:
                    scale >= maxZoom - 0.001 ? null : () => zoomBy(zoomStep),
              ),
            ],
          );
        },
      );

  void setRatio(double? value) {
    setState(() => ratio = value);
    widget.controller.aspectRatio = value;
  }

  void reset() {
    setState(() => ratio = null);
    widget.controller.aspectRatio = null;
    widget.controller.rotation = CropRotation.up;
    widget.controller.crop = const Rect.fromLTRB(0, 0, 1, 1);
    markup.clear();
    selected = null;
  }

  Future<void> done() async {
    if (busy) return;
    final source = widget.controller.getImage();
    if (source == null) return;
    setState(() {
      busy = true;
      exportError = null;
    });
    try {
      final image = await AttachmentCrop.render(source, markup.edits,
          crop: widget.controller.crop, rotation: widget.controller.rotation);
      if (!mounted) {
        image.dispose();
        return;
      }
      await widget.onDone(image);
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          exportError = exportFailed;
        });
    }
  }

  Widget ratioChip(String label, double? value) {
    final selected = ratio == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        mouseCursor: WidgetStateMouseCursor.clickable,
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setRatio(value),
      ),
    );
  }

  void undo() {
    if (busy) return;
    markup.undo();
    setState(
        () => selected = markup.edits.whereType<MarkupOverlay>().lastOrNull);
  }

  Widget undoButton() => ListenableBuilder(
        listenable: markup,
        builder: (context, _) => IconButton(
          tooltip: labelEditUndo,
          icon: const Icon(Icons.undo),
          onPressed: busy || !markup.canUndo ? null : undo,
        ),
      );

  Widget colorSwatch(Color color,
      {required bool selected,
      required String tooltip,
      required String keyPrefix,
      required VoidCallback onTap}) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        mouseCursor: WidgetStateMouseCursor.clickable,
        key: ValueKey("$keyPrefix-${color.toARGB32()}"),
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? colors.primary : colors.outline,
                width: selected ? 3 : 1),
          ),
        ),
      ),
    );
  }

  Widget toolOptions() {
    switch (tool) {
      case AttachmentEditTool.stickers:
        return overlayOptions();
      case AttachmentEditTool.crop:
        return Wrap(
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
        );
      case AttachmentEditTool.draw:
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final color in ImageMarkup.penColors)
              colorSwatch(color,
                  selected: color == penColor,
                  tooltip: labelPenColor,
                  keyPrefix: "pen",
                  onTap: () => setState(() => penColor = color)),
            const SizedBox(width: 8),
            undoButton(),
          ],
        );
      case AttachmentEditTool.redact:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 8,
              children: [
                styleChip(labelRedactPixelate, RedactionStyle.pixelate),
                styleChip(labelRedactBlur, RedactionStyle.blur),
                styleChip(labelRedactColor, RedactionStyle.color),
              ],
            ),
            if (redactStyle == RedactionStyle.color)
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final color in ImageMarkup.penColors)
                    colorSwatch(color,
                        selected: color == redactColor,
                        tooltip: labelRedactBoxColor,
                        keyPrefix: "redact",
                        onTap: () => setState(() => redactColor = color)),
                ],
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                    child: Text(
                        redactStyle == RedactionStyle.color
                            ? labelRedactHint
                            : labelRedactScrambledHint,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall)),
                undoButton(),
              ],
            ),
          ],
        );
    }
  }

  Widget styleChip(String label, RedactionStyle value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        mouseCursor: WidgetStateMouseCursor.clickable,
        label: Text(label),
        selected: redactStyle == value,
        showCheckmark: false,
        shape: const StadiumBorder(),
        onSelected: (_) => setState(() => redactStyle = value),
      ),
    );
  }

  /// One pill per tool, all the same shape.
  Widget toolChip(AttachmentEditTool value, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        mouseCursor: WidgetStateMouseCursor.clickable,
        avatar: Icon(icon),
        label: Text(label),
        selected: tool == value,
        showCheckmark: false,
        shape: const StadiumBorder(),
        onSelected: busy
            ? null
            : (_) => setState(() {
                  tool = value;
                  selected = null;
                }),
      ),
    );
  }

  Widget toolPicker() {
    final tools = [
      toolChip(AttachmentEditTool.crop, Icons.crop_rotate, labelEditToolCrop),
      toolChip(AttachmentEditTool.draw, Icons.brush, labelEditToolDraw),
      toolChip(
          AttachmentEditTool.redact, Icons.hide_source, labelEditToolRedact),
      toolChip(AttachmentEditTool.stickers, Icons.emoji_emotions_outlined,
          PhotoOverlayPicker.stickers),
    ];
    final controls = Row(mainAxisSize: MainAxisSize.min, children: [
      zoomControls(),
      if (widget.onToggleFullscreen != null)
        IconButton(
            tooltip: widget.fullscreen ? labelExitFullscreen : labelFullscreen,
            icon: Icon(
                widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: busy ? null : widget.onToggleFullscreen),
    ]);
    if (MediaQuery.sizeOf(context).width < 600) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(alignment: WrapAlignment.center, children: tools),
        controls
      ]);
    }
    return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [...tools, controls]);
  }

  Widget zoomedPicture() => InteractiveViewer(
        key: zoomViewKey,
        transformationController: zoom,
        panEnabled: tool != AttachmentEditTool.stickers,
        scaleEnabled: tool != AttachmentEditTool.stickers,
        minScale: 1,
        maxScale: maxZoom,
        child: IgnorePointer(ignoring: busy, child: picture()),
      );

  Widget picture() {
    if (tool == AttachmentEditTool.crop) {
      return CropImage(
        image: Image.memory(widget.imageBytes),
        controller: widget.controller,
        overlayPainter: ImageMarkupPainter(markup, widget.controller),
        minimumImageSize: attachmentMinimumCropSize,
      );
    }
    final image = widget.controller.getImage();
    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tool == AttachmentEditTool.stickers) {
      return ListenableBuilder(
          listenable: markup,
          builder: (context, _) => PhotoOverlayCanvas(
              image: image,
              markup: markup,
              controller: widget.controller,
              selected: selected,
              zoom: zoom,
              focus: overlayFocus,
              enabled: !busy,
              viewport: zoomViewKey,
              onSelect: (e) => setState(() => selected = e),
              dimPainter: _CropDimPainter(widget.controller.crop)));
    }
    return AttachmentMarkupCanvas(
      image: image,
      markup: markup,
      controller: widget.controller,
      crop: widget.controller.crop,
      redact: tool == AttachmentEditTool.redact,
      redactStyle: redactStyle,
      redactColor: redactColor,
      penColor: penColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.of(context).desktop;
    final buttons = [
      Expanded(
        flex: desktop ? 1 : 0,
        child: tiamat.Button.secondary(
            text: promptCropReset, onTap: busy ? null : reset),
      ),
      Expanded(
        flex: desktop ? 1 : 0,
        child: tiamat.Button(
            text: promptCropDone, onTap: busy ? null : () => done()),
      ),
    ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          mainAxisSize: widget.fullscreen ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scales down rather than overflowing on narrow phones.
            toolPicker(),
            const SizedBox(height: 12),
            if (widget.fullscreen)
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: widget.imageRatio,
                    child: zoomedPicture(),
                  ),
                ),
              )
            else
              Flexible(
                child: SizedBox(
                  width: 1000,
                  child: AspectRatio(
                    aspectRatio: widget.imageRatio,
                    child: zoomedPicture(),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            toolOptions(),
            if (exportError != null)
              Text(exportError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
        ),
      ),
    );
  }
}

/// The picture, rotated like the crop view shows it, taking pen strokes or
/// redaction boxes. The area outside the crop is dimmed.
class AttachmentMarkupCanvas extends StatefulWidget {
  const AttachmentMarkupCanvas({
    required this.image,
    required this.markup,
    required this.controller,
    required this.crop,
    required this.redact,
    required this.penColor,
    this.redactStyle = RedactionStyle.color,
    this.redactColor = ImageMarkup.redactionColor,
    super.key,
  });

  final ui.Image image;
  final ImageMarkup markup;
  final CropController controller;
  final Rect crop;
  final bool redact;
  final RedactionStyle redactStyle;
  final Color redactColor;
  final Color penColor;

  @override
  State<AttachmentMarkupCanvas> createState() => _AttachmentMarkupCanvasState();
}

class _AttachmentMarkupCanvasState extends State<AttachmentMarkupCanvas> {
  Offset? redactStart;

  Offset toImage(Offset local, Size size) {
    final p = Offset((local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0));
    return ImageMarkup.unrotate(p, widget.controller.rotation);
  }

  void start(Offset local, Size size) {
    final p = toImage(local, size);
    if (widget.redact) {
      redactStart = p;
      widget.markup.add(MarkupRedaction(Rect.fromPoints(p, p),
          style: widget.redactStyle, color: widget.redactColor));
    } else {
      widget.markup
          .add(MarkupStroke(widget.penColor, ImageMarkup.penWidth, [p]));
    }
  }

  void update(Offset local, Size size) {
    final p = toImage(local, size);
    final from = redactStart;
    if (widget.redact) {
      if (from != null) {
        widget.markup.replaceLast(MarkupRedaction(Rect.fromPoints(from, p),
            style: widget.redactStyle, color: widget.redactColor));
      }
    } else {
      widget.markup.addPoint(p);
    }
  }

  void end() {
    final last = widget.markup.edits.lastOrNull;
    if (widget.redact && last is MarkupRedaction && last.rect.isEmpty) {
      widget.markup.undo();
    } else if (widget.redact && last is MarkupRedaction) {
      // Show the scrambled area now; Done makes any that are missing.
      widget.markup.preparePatches(widget.image).ignore();
    }
    redactStart = null;
  }

  @override
  Widget build(BuildContext context) {
    var ratio = widget.image.width / widget.image.height;
    if (widget.controller.rotation.isSideways) ratio = 1 / ratio;
    return Center(
      child: AspectRatio(
        aspectRatio: ratio,
        child: LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            // Trackpad scrolls pan the zoomed picture instead of drawing.
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
              PointerDeviceKind.unknown,
            },
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (d) => start(d.localPosition, size),
            onPanUpdate: (d) => update(d.localPosition, size),
            onPanEnd: (_) => end(),
            onTapUp: widget.redact
                ? null
                : (d) {
                    start(d.localPosition, size);
                    end();
                  },
            child: CustomPaint(
              size: size,
              painter: ImageMarkupPainter(widget.markup, widget.controller,
                  image: widget.image),
              foregroundPainter: _CropDimPainter(widget.crop),
            ),
          );
        }),
      ),
    );
  }
}

class _CropDimPainter extends CustomPainter {
  _CropDimPainter(this.crop);

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    if (crop == const Rect.fromLTRB(0, 0, 1, 1)) return;
    final inside = Rect.fromLTRB(crop.left * size.width, crop.top * size.height,
        crop.right * size.width, crop.bottom * size.height);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(inside);
    canvas.drawPath(path, Paint()..color = const Color(0x99000000));
  }

  @override
  bool shouldRepaint(_CropDimPainter oldDelegate) => oldDelegate.crop != crop;
}
