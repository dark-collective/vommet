// Vommet: the fold of a foldable iPhone as a Flutter DisplayFeature.
//
// Flutter fills MediaQuery.displayFeatures on Android foldables, but not on
// iOS. iOS 27.1 reports the hinge's status and angle (UIHingeInteraction, via
// the vommet_hinge plugin), though not where the fold is. On the iPhone Duo
// the fold splits the inner display in half, so it is placed in the middle:
// across the longer side, a vertical line in landscape and a horizontal one in
// portrait.

import 'dart:async';
import 'dart:ui';

import 'package:commet/config/layout_size_rule.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:vommet_hinge/vommet_hinge.dart';

/// Adds the fold to [MediaQuery.displayFeatures] while a foldable iPhone's
/// inner display is in use. Platforms that report display features
/// themselves (Android) are left alone.
class HingeDisplayFeatures extends StatefulWidget {
  const HingeDisplayFeatures({required this.child, super.key});

  final Widget child;

  @override
  State<HingeDisplayFeatures> createState() => _HingeDisplayFeaturesState();
}

class _HingeDisplayFeaturesState extends State<HingeDisplayFeatures> {
  StreamSubscription<HingeState?>? subscription;
  HingeStatus? status;

  @override
  void initState() {
    super.initState();
    subscription = Hinge.states.listen((state) {
      if (state?.status == status) return;
      setState(() => status = state?.status);
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = MediaQuery.of(context);
    final feature = foldFor(status, query);
    if (feature == null) return widget.child;
    return MediaQuery(
      data: query.copyWith(displayFeatures: [feature]),
      child: widget.child,
    );
  }

  /// The fold for [status] on the display [query] describes, or null when
  /// there is none to add: no hinge, already reported by the platform, or the
  /// small outer display of a closed device (iOS says "partially open" from
  /// about 20 degrees, while the app is still on the outer display).
  static DisplayFeature? foldFor(HingeStatus? status, MediaQueryData query) {
    if (query.displayFeatures.isNotEmpty) return null;
    final DisplayFeatureState posture;
    switch (status) {
      case HingeStatus.partiallyOpen:
        posture = DisplayFeatureState.postureHalfOpened;
      case HingeStatus.fullyOpen:
        posture = DisplayFeatureState.postureFlat;
      default:
        return null;
    }
    if (query.size.shortestSide < desktopLayoutMinSide) return null;

    final size = query.size;
    final bounds = size.width >= size.height
        ? Rect.fromLTWH(size.width / 2, 0, 0, size.height)
        : Rect.fromLTWH(0, size.height / 2, size.width, 0);
    return DisplayFeature(
      bounds: bounds,
      type: DisplayFeatureType.fold,
      state: posture,
    );
  }
}

extension FoldQuery on MediaQueryData {
  /// Whether this display has a fold or hinge (a foldable, Android or iOS);
  /// camera cutouts don't count.
  bool get hasFold => displayFeatures.any((feature) =>
      feature.type == DisplayFeatureType.fold ||
      feature.type == DisplayFeatureType.hinge);

  /// Whether Vommet's touch-and-fold layout rules apply: on iOS (iPad,
  /// foldable iPhones) and on any foldable. Other platforms keep the layout
  /// they had.
  bool get foldLayoutRules => PlatformUtils.isIOS || hasFold;

  /// Where a half-open fold runs top to bottom (a book held open), as a
  /// distance from the left edge; null otherwise.
  double? get halfOpenVerticalFoldX {
    for (final feature in displayFeatures) {
      if (feature.state == DisplayFeatureState.postureHalfOpened &&
          feature.bounds.top <= 0 &&
          feature.bounds.bottom >= size.height) {
        return feature.bounds.center.dx;
      }
    }
    return null;
  }

  /// Where a half-open fold runs side to side (standing like a laptop), as a
  /// distance from the top edge; null otherwise.
  double? get halfOpenHorizontalFoldY {
    for (final feature in displayFeatures) {
      if (feature.state == DisplayFeatureState.postureHalfOpened &&
          feature.bounds.left <= 0 &&
          feature.bounds.right >= size.width) {
        return feature.bounds.center.dy;
      }
    }
    return null;
  }
}

/// Builds [builder] with where a half-open horizontal fold (a foldable
/// standing like a laptop) crosses this widget, measured from its own top, or
/// null when none does or a part would be shorter than [minPart]. Lets a
/// widget put its content above the fold and its controls below.
class HorizontalFoldBuilder extends StatefulWidget {
  const HorizontalFoldBuilder({
    required this.builder,
    this.minPart = 120,
    super.key,
  });

  final Widget Function(BuildContext context, double? foldY) builder;
  final double minPart;

  @override
  State<HorizontalFoldBuilder> createState() => _HorizontalFoldBuilderState();
}

class _HorizontalFoldBuilderState extends State<HorizontalFoldBuilder> {
  // This widget's top in screen coordinates, known after the first layout.
  double? top;

  void measure(Duration _) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final measured = box.localToGlobal(Offset.zero).dy;
    if (measured != top) setState(() => top = measured);
  }

  @override
  Widget build(BuildContext context) {
    final foldY = MediaQuery.of(context).halfOpenHorizontalFoldY;
    // Where this widget sits can change without a rebuild here, so measure
    // after every frame it builds in while there is a fold; setState only on
    // a change.
    if (foldY != null) SchedulerBinding.instance.addPostFrameCallback(measure);
    // Always a LayoutBuilder, so the subtree keeps its state when the device
    // folds or unfolds.
    return LayoutBuilder(builder: (context, constraints) {
      final top = this.top;
      if (foldY == null || top == null) return widget.builder(context, null);
      final local = foldY - top;
      if (local < widget.minPart ||
          local > constraints.maxHeight - widget.minPart) {
        return widget.builder(context, null);
      }
      return widget.builder(context, local);
    });
  }
}
