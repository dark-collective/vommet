import 'package:commet/config/build_config.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet: visible zoom for the image viewer (Vommet issue 343). On desktop a
/// − / percentage / + pill sits under the picture and a click zooms in around
/// the pointer; on phones and tablets a double tap does. + / − / 0 on the
/// keyboard zoom in, out and back to fit.
///
/// Drives the viewer's [TransformationController]; the lightbox only renames
/// its `build` to [buildViewer] and hands over its taps.
mixin LightboxZoom on State<Lightbox>, TickerProviderStateMixin<Lightbox> {
  TransformationController get controller;

  /// The lightbox's own content, wrapped here with the zoom pill.
  Widget buildViewer(BuildContext context);

  /// Put on the viewer's [InteractiveViewer]: its box is the viewport.
  final GlobalKey zoomViewerKey = GlobalKey();

  late final AnimationController _zoomAnimation;

  Matrix4Tween? _zoomTween;

  /// Only pictures zoom by click and buttons; a video's taps are its own.
  bool get zoomControlsApply =>
      widget.image != null && widget.customWidget == null;

  @override
  void initState() {
    super.initState();
    _zoomAnimation = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..addListener(_onZoomTick);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _zoomAnimation.dispose();
    super.dispose();
  }

  RenderBox? get _viewport {
    final box = zoomViewerKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  double get currentZoom => controller.value.getMaxScaleOnAxis();

  void _onZoomTick() {
    final tween = _zoomTween;
    if (tween == null) return;
    controller.value =
        tween.transform(Curves.easeOut.transform(_zoomAnimation.value));
  }

  /// Zooms to [scale], keeping the viewport point [focal] (default: its
  /// centre) where it is.
  void zoomTo(double scale, {Offset? focal}) {
    final viewport = _viewport;
    if (viewport == null) return;
    final size = viewport.size;
    final target = zoomMatrix(
      scenePoint: controller.toScene(focal ?? size.center(Offset.zero)),
      focal: focal ?? size.center(Offset.zero),
      scale: scale,
      viewport: size,
    );
    _zoomTween = Matrix4Tween(begin: controller.value.clone(), end: target);
    _zoomAnimation.forward(from: 0);
  }

  void stepZoom(int direction) => zoomTo(nextZoomStep(currentZoom, direction));

  void resetZoom() => zoomTo(1);

  /// A click (or double tap) on the picture: in to 200% around the pointer,
  /// or back to fit when already zoomed.
  void toggleZoomAt(Offset globalPosition) {
    final viewport = _viewport;
    if (viewport == null) return;
    if (currentZoom > 1.01) {
      resetZoom();
    } else {
      zoomTo(clickZoom, focal: viewport.globalToLocal(globalPosition));
    }
  }

  Offset? _doubleTapPosition;

  /// Handlers for the GestureDetector around the picture.
  GestureTapUpCallback? get onZoomTapUp =>
      zoomControlsApply && !BuildConfig.MOBILE
          ? (details) => toggleZoomAt(details.globalPosition)
          : null;

  GestureTapDownCallback? get onZoomDoubleTapDown =>
      zoomControlsApply && BuildConfig.MOBILE
          ? (details) => _doubleTapPosition = details.globalPosition
          : null;

  VoidCallback? get onZoomDoubleTap => zoomControlsApply && BuildConfig.MOBILE
      ? () {
          final position = _doubleTapPosition;
          if (position != null) toggleZoomAt(position);
        }
      : null;

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent || !zoomControlsApply || !mounted) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }
    final key = event.logicalKey;
    final int? action;
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      action = 1;
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      action = -1;
    } else if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      action = 0;
    } else {
      action = null;
    }
    if (action == null || !_isShown()) return false;
    if (action == 0) {
      resetZoom();
    } else {
      stepZoom(action);
    }
    return true;
  }

  /// The viewer on top and on screen: the picture gallery keeps its
  /// neighbouring pages built off screen, and a menu may be open above.
  bool _isShown() {
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final viewport = _viewport;
    if (viewport == null || !viewport.attached) return false;
    final centre = viewport.localToGlobal(viewport.size.center(Offset.zero));
    return (Offset.zero & MediaQuery.sizeOf(context)).contains(centre);
  }

  @override
  Widget build(BuildContext context) {
    final viewer = buildViewer(context);
    if (!zoomControlsApply || BuildConfig.MOBILE) return viewer;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        viewer,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              // Centred in the viewer's 100 px desktop margin.
              padding: const EdgeInsets.only(bottom: 30),
              child: Center(
                // Taps between the buttons must not close the viewer.
                child: GestureDetector(
                  onTap: () {},
                  child: _zoomPill(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _zoomPill(BuildContext context) {
    // The viewer is a bare overlay with no Material above it, so the text
    // style must be complete (see the gallery's counter).
    final style = (Theme.of(context).textTheme.labelMedium ??
            const TextStyle(fontSize: 12))
        .copyWith(
            inherit: false,
            color: Colors.white,
            decoration: TextDecoration.none,
            fontFeatures: const [FontFeature.tabularFigures()]);
    final divider = Container(width: 1, height: 16, color: Colors.white24);
    return Material(
      color: Colors.black54,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final zoom = currentZoom;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey("lightbox_zoom_out"),
                icon: const Icon(Icons.remove),
                iconSize: 20,
                color: Colors.white,
                disabledColor: Colors.white38,
                onPressed: zoom > minZoom + 0.01 ? () => stepZoom(-1) : null,
              ),
              divider,
              InkWell(
                key: const ValueKey("lightbox_zoom_reset"),
                onTap: resetZoom,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text("${(zoom * 100).round()}%", style: style),
                ),
              ),
              divider,
              IconButton(
                key: const ValueKey("lightbox_zoom_in"),
                icon: const Icon(Icons.add),
                iconSize: 20,
                color: Colors.white,
                disabledColor: Colors.white38,
                onPressed: zoom < maxZoom - 0.01 ? () => stepZoom(1) : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

const double minZoom = 1;

/// Matches the viewer's `InteractiveViewer.maxScale`.
const double maxZoom = 3.5;

const double clickZoom = 2;

const List<double> zoomSteps = [1, 1.25, 1.5, 2, 2.5, 3, 3.5];

/// The next step up (`direction > 0`) or down from [current]; a zoom
/// between steps (from a pinch or the wheel) goes to the nearest step that
/// way.
double nextZoomStep(double current, int direction) {
  if (direction > 0) {
    return zoomSteps.firstWhere((s) => s > current + 0.01,
        orElse: () => zoomSteps.last);
  }
  return zoomSteps.lastWhere((s) => s < current - 0.01,
      orElse: () => zoomSteps.first);
}

/// The transform at [scale] that puts [scenePoint] under the viewport point
/// [focal], clamped so the picture's area still fills the viewport (as the
/// InteractiveViewer's own boundary does).
Matrix4 zoomMatrix({
  required Offset scenePoint,
  required Offset focal,
  required double scale,
  required Size viewport,
}) {
  final s = scale.clamp(minZoom, maxZoom);
  final tx = (focal.dx - scenePoint.dx * s)
      .clamp(viewport.width * (1 - s), 0.0)
      .toDouble();
  final ty = (focal.dy - scenePoint.dy * s)
      .clamp(viewport.height * (1 - s), 0.0)
      .toDouble();
  return Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
}
