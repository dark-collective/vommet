// Vommet: select and manipulate overlays without competing with photo zoom (issue 1056).
import 'dart:ui' as ui;

import 'package:commet/ui/organisms/attachment_crop/image_markup.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class PhotoOverlayCanvas extends StatefulWidget {
  const PhotoOverlayCanvas(
      {required this.image,
      this.enabled = true,
      required this.markup,
      required this.controller,
      required this.selected,
      required this.onSelect,
      required this.zoom,
      required this.focus,
      required this.viewport,
      required this.dimPainter,
      super.key});
  final bool enabled;
  final ui.Image image;
  final ImageMarkup markup;
  final CropController controller;
  final MarkupOverlay? selected;
  final ValueChanged<MarkupOverlay?> onSelect;
  final TransformationController zoom;
  final FocusNode focus;
  final GlobalKey viewport;
  final CustomPainter dimPainter;
  static String get objectLabel =>
      Intl.message('Photo overlay', name: 'photoOverlayObject');
  static String get resize =>
      Intl.message('Resize overlay', name: 'photoOverlayResize');
  @override
  State<PhotoOverlayCanvas> createState() => _PhotoOverlayCanvasState();
}

class _PhotoOverlayCanvasState extends State<PhotoOverlayCanvas> {
  FocusNode get focus => widget.focus;
  final sceneKey = GlobalKey();
  RenderBox get scene =>
      sceneKey.currentContext!.findRenderObject() as RenderBox;
  final pointers = <int, Offset>{};
  Rect? before;
  Offset start = Offset.zero;
  MarkupOverlay? dragging;
  bool blocked = false, resizing = false;
  double photoScale = 1, span = 1;
  Offset photoTranslation = Offset.zero, photoFocal = Offset.zero;

  Rect displayed(MarkupOverlay e) => ImageMarkup.mapRect(
      e.rect, (p) => ImageMarkup.rotate(p, widget.controller.rotation));
  Rect source(Rect r) => ImageMarkup.mapRect(
      r, (p) => ImageMarkup.unrotate(p, widget.controller.rotation));
  Rect constrained(Rect r) => r.shift(Offset(
      r.left < 0
          ? -r.left
          : r.right > 1
              ? 1 - r.right
              : 0,
      r.top < 0
          ? -r.top
          : r.bottom > 1
              ? 1 - r.bottom
              : 0));
  void finish({bool cancel = false}) {
    final e = dragging, old = before;
    if (e != null && old != null)
      widget.markup.transformOverlay(e, cancel ? old : e.rect,
          before: cancel ? null : old);
    dragging = null;
    before = null;
  }

  RenderBox get viewport =>
      widget.viewport.currentContext!.findRenderObject() as RenderBox;
  Offset get focal =>
      pointers.values.reduce((a, b) => a + b) / pointers.length.toDouble();
  double get distance => (pointers.values.first - pointers.values.last)
      .distance
      .clamp(1, double.infinity);
  void startPhoto([Offset? position]) {
    photoScale = widget.zoom.value.getMaxScaleOnAxis();
    final t = widget.zoom.value.getTranslation();
    photoTranslation = Offset(t.x, t.y);
    photoFocal = viewport.globalToLocal(position ?? focal);
    span = pointers.isEmpty ? 1 : distance;
  }

  void transformPhoto(double scale, Offset translation) {
    final size = viewport.size;
    widget.zoom.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(translation.dx.clamp(size.width * (1 - scale), 0),
          translation.dy.clamp(size.height * (1 - scale), 0), 0);
  }

  Rect pixels(MarkupOverlay e, Size size) {
    final r = displayed(e);
    return Rect.fromLTRB(r.left * size.width, r.top * size.height,
        r.right * size.width, r.bottom * size.height);
  }

  Rect handle(Rect r, Size size) => Rect.fromLTWH(
      (r.right - 22).clamp(0, (size.width - 44).clamp(0, double.infinity)),
      (r.bottom - 22).clamp(0, (size.height - 44).clamp(0, double.infinity)),
      44,
      44);
  KeyEventResult key(FocusNode _, KeyEvent event) {
    final e = widget.selected;
    if (!widget.enabled ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        e == null ||
        !widget.markup.edits.contains(e)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onSelect(null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      widget.markup.removeOverlay(e);
      widget.onSelect(null);
      return KeyEventResult.handled;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? .02 : .002;
    final delta = {
      LogicalKeyboardKey.arrowLeft: Offset(-step, 0),
      LogicalKeyboardKey.arrowRight: Offset(step, 0),
      LogicalKeyboardKey.arrowUp: Offset(0, -step),
      LogicalKeyboardKey.arrowDown: Offset(0, step)
    }[key];
    if (delta == null) return KeyEventResult.ignored;
    widget.markup.transformOverlay(
        e, source(constrained(displayed(e).shift(delta))),
        before: e.rect);
    return KeyEventResult.handled;
  }

  void pointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    final size = scene.size;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) return;
    pointers[event.pointer] = event.position;
    if (pointers.length > 1) {
      finish(cancel: true);
      blocked = true;
      startPhoto();
      return;
    }
    focus.requestFocus();
    start = event.position;
    final local = (scene).globalToLocal(start);
    final overlays = widget.markup.edits
        .whereType<MarkupOverlay>()
        .where((e) => displayed(e).overlaps(widget.controller.crop));
    dragging = overlays
        .where((e) =>
            pixels(e, size).contains(local) ||
            (e == widget.selected &&
                handle(pixels(e, size), size).contains(local)))
        .lastOrNull;
    before = dragging?.rect;
    resizing = dragging != null &&
        dragging == widget.selected &&
        handle(pixels(dragging!, size), size).contains(local);
    widget.onSelect(dragging);
    startPhoto();
  }

  void pointerMove(PointerMoveEvent event) {
    if (!widget.enabled) return;
    final size = scene.size;
    if (!pointers.containsKey(event.pointer)) return;
    pointers[event.pointer] = event.position;
    if (pointers.length > 1) {
      final next = (photoScale * distance / span).clamp(1.0, 8.0);
      final anchor = (photoFocal - photoTranslation) / photoScale;
      transformPhoto(next, viewport.globalToLocal(focal) - anchor * next);
      return;
    }
    if (blocked) return;
    final e = dragging, old = before;
    if (e == null || old == null) {
      transformPhoto(photoScale,
          photoTranslation + viewport.globalToLocal(focal) - photoFocal);
      return;
    }
    final box = scene;
    final delta = box.globalToLocal(event.position) - box.globalToLocal(start);
    final original = ImageMarkup.mapRect(
        old, (p) => ImageMarkup.rotate(p, widget.controller.rotation));
    var next =
        original.shift(Offset(delta.dx / size.width, delta.dy / size.height));
    if (resizing) {
      final factor =
          (1 + delta.dx / (original.width * size.width)).clamp(.1, 10.0);
      final limit = [
        factor,
        (1 - original.left) / original.width,
        (1 - original.top) / original.height
      ].reduce((a, b) => a < b ? a : b);
      next = Rect.fromLTWH(original.left, original.top, original.width * limit,
          original.height * limit);
    }
    widget.markup.transformOverlay(e, source(constrained(next)));
  }

  void pointerUp(PointerUpEvent event) {
    if (pointers.length == 1 && !blocked) finish();
    pointers.remove(event.pointer);
    if (pointers.isEmpty) blocked = false;
    if (pointers.length > 1) startPhoto();
  }

  void pointerCancel(PointerCancelEvent event) {
    finish(cancel: true);
    pointers.remove(event.pointer);
    if (pointers.isEmpty) blocked = false;
  }

  void pointerSignal(PointerSignalEvent event) {
    if (!widget.enabled) return;
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        final scale = widget.zoom.value.getMaxScaleOnAxis(),
            t = widget.zoom.value.getTranslation();
        transformPhoto(scale, Offset(t.x, t.y) - event.scrollDelta);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sideways = widget.controller.rotation.isSideways;
    final ratio = sideways
        ? widget.image.height / widget.image.width
        : widget.image.width / widget.image.height;
    return Center(
        child: AspectRatio(
            aspectRatio: ratio,
            child: LayoutBuilder(builder: (context, constraints) {
              final size = constraints.biggest;
              return Focus(
                  focusNode: focus,
                  onKeyEvent: key,
                  child: Listener(
                      key: sceneKey,
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: pointerDown,
                      onPointerMove: pointerMove,
                      onPointerUp: pointerUp,
                      onPointerCancel: pointerCancel,
                      onPointerSignal: pointerSignal,
                      onPointerPanZoomStart: (e) {
                        finish(cancel: true);
                        startPhoto(e.position);
                      },
                      onPointerPanZoomUpdate: (e) {
                        final next = (photoScale * e.scale).clamp(1.0, 8.0);
                        final anchor =
                            (photoFocal - photoTranslation) / photoScale;
                        transformPhoto(
                            next,
                            viewport.globalToLocal(e.position) +
                                e.pan -
                                anchor * next);
                      },
                      child: Stack(clipBehavior: Clip.hardEdge, children: [
                        Positioned.fill(
                            child: CustomPaint(
                                painter: ImageMarkupPainter(
                                    widget.markup, widget.controller,
                                    image: widget.image),
                                foregroundPainter: widget.dimPainter)),
                        for (final e
                            in widget.markup.edits.whereType<MarkupOverlay>())
                          if (displayed(e)
                              .overlaps(widget.controller.crop)) ...[
                            Positioned.fromRect(
                                rect: pixels(e, size),
                                child: Semantics(
                                    label: PhotoOverlayCanvas.objectLabel,
                                    selected: widget.selected == e,
                                    button: true,
                                    onTap: () {
                                      focus.requestFocus();
                                      widget.onSelect(e);
                                    },
                                    child: DecoratedBox(
                                        key: ValueKey(e),
                                        decoration: BoxDecoration(
                                            border: widget.selected == e
                                                ? Border.all(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    width: 2)
                                                : null)))),
                            if (widget.selected == e)
                              Positioned.fromRect(
                                  rect: handle(pixels(e, size), size),
                                  child: Semantics(
                                      container: true,
                                      label: PhotoOverlayCanvas.resize,
                                      child: Align(
                                          alignment: Alignment.bottomRight,
                                          child: Container(
                                              width: 24,
                                              height: 24,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              child: const Icon(
                                                  Icons.open_in_full,
                                                  size: 18))))),
                          ],
                      ])));
            })));
  }
}
