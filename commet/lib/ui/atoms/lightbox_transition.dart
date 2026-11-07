import 'package:flutter/material.dart';

/// Keeps the viewer's closing slide moving in the direction of its swipe.
/// Both the standalone viewer and gallery use the same route transition.
class LightboxTransition extends StatefulWidget {
  const LightboxTransition({
    required this.animation,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;

  static void setDismissDirection(BuildContext context, double direction) {
    context
        .findAncestorStateOfType<_LightboxTransitionState>()
        ?.setDismissDirection(direction);
  }

  @override
  State<LightboxTransition> createState() => _LightboxTransitionState();
}

class _LightboxTransitionState extends State<LightboxTransition> {
  double direction = 1;
  double? dismissAt;
  double dismissFrom = 0;

  double get offset {
    final curved = Curves.easeOutCubic.transform(widget.animation.value);
    final at = dismissAt;
    if (at == null) return 1 - curved;
    final progress = at == 0 ? 0.0 : (1 - curved / at).clamp(0.0, 1.0);
    return dismissFrom + (direction - dismissFrom) * progress;
  }

  void setDismissDirection(double value) {
    // A swipe can end while the opening slide is still moving. Start the
    // closing motion exactly there instead of flipping its current offset.
    final from = offset;
    final at = Curves.easeOutCubic.transform(widget.animation.value);
    setState(() {
      dismissFrom = from;
      dismissAt = at;
      direction = value < 0 ? -1 : 1;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.animation,
        child: widget.child,
        builder: (context, child) => FractionalTranslation(
          translation: Offset(0, offset),
          child: child,
        ),
      );
}
