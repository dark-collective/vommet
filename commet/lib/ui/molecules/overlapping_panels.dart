// Based on https://github.com/blackmann/overlapping_panels
// Copyright 2022 De-Great Yartey. All rights reserved.

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/inherited_offstage.dart';
import 'package:flutter/material.dart';
import 'dart:core';

import 'package:tiamat/config/config.dart';

const double bleedWidth = 20;

/// A drag that ends faster than this (logical pixels per second) moves the
/// panels in its direction however short it was.
const double _flingVelocity = 400;

/// Display sections
enum RevealSide { left, right, main }

/// Widget to display three view panels with the [OverlappingPanels.main] being
/// in the center, [OverlappingPanels.left] and [OverlappingPanels.right] also
/// revealing from their respective sides. Just like you will see in the
/// Discord mobile app's navigation.
class OverlappingPanels extends StatefulWidget {
  /// The left panel
  final Widget? left;

  /// The main panel
  final Widget main;

  /// The right panel
  final Widget? right;

  /// The offset to use to keep the main panel visible when the left or right
  /// panel is revealed.
  final double restWidth;

  /// A callback to notify when a panel reveal has completed.
  final ValueChanged<RevealSide>? onSideChange;

  final Function? onDragStart;

  final double threshold = 0.2;

  const OverlappingPanels(
      {this.left,
      required this.main,
      this.right,
      this.restWidth = 40,
      this.onSideChange,
      this.onDragStart,
      super.key});

  static OverlappingPanelsState? of(BuildContext context) {
    return context.findAncestorStateOfType<OverlappingPanelsState>();
  }

  @override
  State<StatefulWidget> createState() {
    return OverlappingPanelsState();
  }
}

class OverlappingPanelsState extends State<OverlappingPanels>
    with TickerProviderStateMixin {
  AnimationController? controller;
  double translate = 0;
  RevealSide currentSide = RevealSide.main;

  final _leftKey = GlobalKey();
  final _mainKey = GlobalKey();
  final _rightKey = GlobalKey();

  /// Vommet issue 322: a panel sliding out of view gives up the keyboard
  /// focus, so typing never goes into a message box you can't see (the room's
  /// while a thread is open, or the thread's after swiping back to the room).
  /// Focus inside the panel being revealed, or outside the panels, is kept.
  void _unfocusOutside(RevealSide side) {
    final focused = FocusManager.instance.primaryFocus;
    final focusedContext = focused?.context;
    if (focused == null || focusedContext == null) return;

    final hidden = [
      if (side != RevealSide.left) _leftKey.currentContext,
      if (side != RevealSide.main) _mainKey.currentContext,
      if (side != RevealSide.right) _rightKey.currentContext,
    ].nonNulls.toSet();

    var inHiddenPanel = hidden.contains(focusedContext);
    if (!inHiddenPanel) {
      focusedContext.visitAncestorElements((element) {
        inHiddenPanel = hidden.contains(element);
        return !inHiddenPanel;
      });
    }

    if (inHiddenPanel) focused.unfocus();
  }

  double _calculateGoal(double width, int multiplier) {
    return (multiplier * width) + (-multiplier * widget.restWidth);
  }

  /// Which way a finished drag moves the panels: 1 towards the left panel,
  /// -1 towards the right panel, 0 back to where the drag started.
  int _swipeDirection(double mediaWidth, double velocity) {
    final rest = switch (currentSide) {
      RevealSide.main => 0.0,
      RevealSide.left => _calculateGoal(mediaWidth, 1),
      RevealSide.right => _calculateGoal(mediaWidth, -1),
    };
    final moved = translate - rest;

    final int direction;
    if (velocity.abs() >= _flingVelocity) {
      direction = velocity > 0 ? 1 : -1;
    } else if (moved.abs() > widget.threshold * mediaWidth) {
      direction = moved > 0 ? 1 : -1;
    } else {
      return 0;
    }

    // From a side panel the only way to go is back to the main panel.
    return switch (currentSide) {
      RevealSide.main =>
        (direction > 0 ? widget.left : widget.right) == null ? 0 : direction,
      RevealSide.left => direction < 0 ? direction : 0,
      RevealSide.right => direction > 0 ? direction : 0,
    };
  }

  void _onApplyTranslation([double velocity = 0]) {
    final mediaWidth =
        MediaQuery.of(context).size.width / preferences.appScale.value;
    final animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));

    animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (widget.onSideChange != null) {
          widget.onSideChange!(translate == 0
              ? RevealSide.main
              : (translate > 0 ? RevealSide.left : RevealSide.right));
        }
        animationController.dispose();
      }
    });

    // Vommet issue 567: judge the drag from the side it started on, and let a
    // quick flick count. The old check wanted the panel between 20% and 80%
    // of the screen, so a long swipe from the room list back to Home ended
    // below 20% and snapped back to the room list.
    final direction = _swipeDirection(mediaWidth, velocity);
    bool crossedThreshold = direction != 0;

    if (crossedThreshold) {
      switch (currentSide) {
        case RevealSide.left:
        case RevealSide.right:
          revealMainPanel(animationController);
          break;
        case RevealSide.main:
          (direction > 0)
              ? revealLeftPanel(mediaWidth, animationController)
              : revealRightPanel(mediaWidth, animationController);
          break;
      }
    } else {
      switch (currentSide) {
        case RevealSide.left:
          revealLeftPanel(mediaWidth, animationController);
          break;
        case RevealSide.right:
          revealRightPanel(mediaWidth, animationController);
          break;
        case RevealSide.main:
          revealMainPanel(animationController);
          break;
      }
    }

    animationController.forward();
  }

  void revealLeftPanel(
      double mediaWidth, AnimationController animationController) {
    currentSide = RevealSide.left;
    _unfocusOutside(RevealSide.left);
    _setTranslateMultiplier(mediaWidth, 1, animationController);
  }

  void revealRightPanel(
      double mediaWidth, AnimationController animationController) {
    currentSide = RevealSide.right;
    _unfocusOutside(RevealSide.right);
    _setTranslateMultiplier(mediaWidth, -1, animationController);
  }

  void revealMainPanel(AnimationController animationController) {
    currentSide = RevealSide.main;
    _unfocusOutside(RevealSide.main);
    final animation = Tween<double>(begin: translate, end: 0).animate(
        CurvedAnimation(
            parent: animationController, curve: Curves.easeOutExpo));

    animation.addListener(() {
      setState(() {
        translate = animation.value;
      });
    });
  }

  void _setTranslateMultiplier(double mediaWidth, int multiplier,
      AnimationController animationController) {
    final goal = _calculateGoal(mediaWidth, multiplier);

    final Tween<double> tween = Tween(begin: translate, end: goal);

    final animation = tween.animate(CurvedAnimation(
        parent: animationController, curve: Curves.easeOutExpo));

    animation.addListener(() {
      setState(() {
        translate = animation.value;
      });
    });
  }

  void reveal(RevealSide direction) {
    final mediaWidth =
        MediaQuery.of(context).size.width / preferences.appScale.value;
    final animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));

    // Vommet: report the new side as a swipe does. Without this the main
    // page kept the "can't close" state from before, and on Android the back
    // button did nothing on the room list once back had opened it.
    animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onSideChange?.call(direction);
        animationController.dispose();
      }
    });

    switch (direction) {
      case RevealSide.left:
        revealLeftPanel(mediaWidth, animationController);
        break;
      case RevealSide.right:
        revealRightPanel(mediaWidth, animationController);
        break;
      case RevealSide.main:
        revealMainPanel(animationController);
        break;
    }

    animationController.forward();
  }

  void onTranslate(double delta) {
    setState(() {
      final translate = this.translate + delta;
      if (translate < 0 && widget.right != null ||
          translate > 0 && widget.left != null) {
        this.translate = translate;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double borderRadius = 20;

    return GestureDetector(
        onHorizontalDragStart: (details) {
          widget.onDragStart?.call();
        },
        onHorizontalDragUpdate: (details) {
          onTranslate(details.delta.dx);
        },
        onHorizontalDragEnd: (details) {
          _onApplyTranslation(details.velocity.pixelsPerSecond.dx);
        },
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(0, 0, widget.restWidth + 3, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                    topRight: Radius.circular(borderRadius),
                    bottomRight: Radius.circular(borderRadius)),
                child: InheritedOffstage(
                  offstage: translate <= 0,
                  child: Offstage(
                    offstage: translate <= 0,
                    child: widget.left == null
                        ? null
                        : KeyedSubtree(key: _leftKey, child: widget.left!),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(widget.restWidth + 3, 0, 0, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(borderRadius),
                    bottomLeft: Radius.circular(borderRadius)),
                child: InheritedOffstage(
                  offstage: translate >= 0,
                  child: Offstage(
                    offstage: translate >= 0,
                    child: widget.right == null
                        ? null
                        : KeyedSubtree(key: _rightKey, child: widget.right!),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(translate, 0),
              child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                          (translate.abs() * 0.1).clamp(0, 20)),
                      boxShadow: Theme.of(context)
                              .extension<ShadowSettings>()
                              ?.shadows ??
                          [
                            BoxShadow(
                                color: Colors.black.withAlpha(30),
                                blurRadius: 20)
                          ]),
                  child: KeyedSubtree(key: _mainKey, child: widget.main)),
            )
          ],
        ));
  }
}
