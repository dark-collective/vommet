import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:tiamat/config/style/room_list_fill.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// Vommet issue 1194: records the real window bounds for pinned-header paint.
class RoomListFoundation extends SingleChildRenderObjectWidget {
  const RoomListFoundation({required super.child, super.key});
  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _FoundationBounds();
}

class _FoundationBounds extends RenderProxyBox {}

/// Only explicitly named navigation panes opt in. A header replays the same
/// backdrop and fill at the pane's coordinates, hiding scrolled rows without
/// compositing translucent stops twice. No timers or cached sizes; any backdrop
/// image subscription belongs to the disposable header painter.
class RoomListSurface extends SingleChildRenderObjectWidget {
  const RoomListSurface({required super.child, this.header = false, super.key});
  final bool header;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final render = _RoomListPaint();
    updateRenderObject(context, render);
    return render;
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderProxyBox object) {
    final render = object as _RoomListPaint;
    final theme = Theme.of(context);
    render.configure(
        theme.extension<RoomListFill>(),
        theme.extension<FoundationSettings>(),
        theme.colorScheme.surfaceDim,
        theme.extension<GlassSettings>()?.surfaceContainerLowSigma ?? 0,
        header);
  }
}

class _RoomListPaint extends RenderProxyBox {
  RoomListFill? fill;
  Color fallback = Colors.black;
  double sigma = 0;
  bool header = false;
  BoxPainter? backdrop;

  void configure(RoomListFill? value, FoundationSettings? window, Color color,
      double blur, bool pinned) {
    fill = value;
    fallback = color;
    sigma = blur;
    header = pinned;
    backdrop?.dispose();
    backdrop = value == null ||
            (!pinned &&
                value.opacity == 1 &&
                value.colors.every((c) => c.a == 1))
        ? null
        : BoxDecoration(
            color: window?.color ?? color,
            gradient: window?.gradient,
            image: window?.image == null
                ? null
                : DecorationImage(
                    image: window!.image!,
                    fit: window.imageFit,
                    alignment:
                        [BoxFit.cover, BoxFit.fill].contains(window.imageFit)
                            ? Alignment.center
                            : window.imageAlignment),
          ).createBoxPainter(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void dispose() {
    backdrop?.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final current = fill;
    if (current != null) {
      final canvas = context.canvas;
      var bounds = offset & size;
      final replay =
          header || current.opacity < 1 || current.colors.any((c) => c.a < 1);
      if (replay) {
        RenderObject? ancestor = parent;
        RenderBox? window;
        while (ancestor != null) {
          if (header && ancestor is _RoomListPaint && !ancestor.header) {
            bounds = (offset - localToGlobal(Offset.zero, ancestor: ancestor)) &
                ancestor.size;
          }
          if (window == null && ancestor is _FoundationBounds) {
            window = ancestor;
          }
          ancestor = ancestor.parent;
        }
        canvas.save();
        canvas.clipRect(offset & size);
        final root = window;
        final rect = root == null
            ? bounds
            : (offset - localToGlobal(Offset.zero, ancestor: root)) & root.size;
        canvas.drawRect(rect, Paint()..color = fallback);
        if (sigma > 0) {
          canvas.saveLayer(
              rect,
              Paint()
                ..imageFilter =
                    ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
        }
        backdrop?.paint(
            canvas, rect.topLeft, ImageConfiguration(size: rect.size));
        if (sigma > 0) {
          canvas.restore();
        }
      }
      canvas.drawRect(
          bounds, Paint()..shader = current.paintGradient.createShader(bounds));
      if (replay) {
        canvas.restore();
      }
    }
    super.paint(context, offset);
  }
}
