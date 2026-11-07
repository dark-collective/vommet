import 'dart:math';
import 'package:commet/main.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:flutter/material.dart';

class KeyboardAdaptorController {
  Function()? keepCurrentSize;
  Function()? clearOverride;

  bool Function()? hasOverride;
}

class KeyboardAdaptor extends StatefulWidget {
  const KeyboardAdaptor({
    super.key,
    required this.child,
    this.paddingContent,
    this.enabled = true,
    this.shouldPushContent,
    this.controller,
    this.expandChild = false,
    this.boundChild = false,
  });

  final Widget child;
  final bool enabled;
  final Widget? paddingContent;
  final bool Function()? shouldPushContent;
  final KeyboardAdaptorController? controller;

  /// Vommet composer round 6: [child] takes all the height the adaptor
  /// doesn't (the expanded message box).
  final bool expandChild;

  // Vommet issue 1143: give a shrink-wrapped desktop footer its remaining
  // height after any keyboard spacer.
  final bool boundChild;
  @override
  State<KeyboardAdaptor> createState() => _KeyboardAdaptorState();
}

class _KeyboardAdaptorState extends State<KeyboardAdaptor> {
  double? sizeOverride;
  double? _bottom;
  bool _positionCallbackPending = false;

  @override
  initState() {
    super.initState();

    widget.controller?.keepCurrentSize = keepCurrentSize;
    widget.controller?.clearOverride = clearOverride;
    widget.controller?.hasOverride = hasOverride;
  }

  void _updatePosition(Duration _) {
    _positionCallbackPending = false;
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final globalBottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (globalBottom != _bottom) {
        setState(() => _bottom = globalBottom);
      }
    }
  }

  // Vommet issue 974: on iPad (and desktop/tablet multi-pane layouts),
  // the composer is not at the bottom of the screen; headers, caulk and
  // side panels offset the chat. When the on-screen keyboard opens, the
  // required spacer is the actual overlap between this adaptor's bottom
  // edge and the top edge of the keyboard, not the full viewInsets.bottom
  // from the window edge. On phones the adaptor ends at the screen bottom,
  // so the overlap equals viewInsets.bottom.
  double _keyboardOverlap(MediaQueryData scaledQuery) {
    final viewInsetsBottom = scaledQuery.viewInsets.bottom;
    if (viewInsetsBottom <= 0) return viewInsetsBottom;
    final screenHeight = scaledQuery.size.height;
    final keyboardTop = screenHeight - viewInsetsBottom;
    final bottom = _bottom ?? screenHeight;
    return max(0.0, bottom - keyboardTop);
  }

  @override
  Widget build(BuildContext context) {
    var scaledQuery = MediaQuery.of(context).scale();
    var overlap = _keyboardOverlap(scaledQuery);

    if (!_positionCallbackPending) {
      _positionCallbackPending = true;
      WidgetsBinding.instance.addPostFrameCallback(_updatePosition);
    }

    var offset = max(overlap, scaledQuery.padding.bottom);

    var padding = scaledQuery.viewPadding;
    // While the keyboard is open, the home indicator area is behind it; an
    // overlap smaller than that padding must not leave a gap above it. Only
    // when the adaptor ends above the screen bottom: on phones the overlap
    // is the full inset, and capping there would make the composer dip
    // while the keyboard animates over the home indicator.
    if (scaledQuery.viewInsets.bottom > 0 &&
        overlap < scaledQuery.viewInsets.bottom) {
      padding = padding.copyWith(bottom: min(padding.bottom, offset));
    }

    bool shouldPushContent = widget.shouldPushContent == null ||
        widget.shouldPushContent?.call() == true;

    if (sizeOverride != null && offset > sizeOverride!) {
      preferences.emojiPickerHeight.set(offset);
      sizeOverride = null;
    }

    var contentHeight = (sizeOverride ?? offset) - padding.bottom;
    var pushHeight = (shouldPushContent ? (offset - padding.bottom) : 0.0);
    pushHeight = max(pushHeight, 0);
    contentHeight = max(contentHeight, 0);

    return Column(
      mainAxisSize: widget.boundChild ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Flexible(
            flex: widget.expandChild || widget.boundChild ? 1 : 0,
            fit: widget.boundChild ? FlexFit.loose : FlexFit.tight,
            child: widget.child),
        Container(
          //color: Colors.green.withAlpha(40),
          child: AnimatedContainer(
            duration: Durations.short1,
            child: widget.paddingContent,
            height:
                (!widget.enabled && sizeOverride == null) ? 0 : contentHeight,
          ),
        ),
        Container(
          // color: Colors.blue.withAlpha(40),
          child: AnimatedContainer(
            duration: Durations.short1,
            height: widget.enabled ? pushHeight : 0,
          ),
        ),
        SizedBox(
          height: widget.enabled ? padding.bottom : 0,
        )
      ],
    );
  }

  static const minPickerHeight = 150.0;

  keepCurrentSize({double min = 300}) {
    var scaledQuery = MediaQuery.of(context).scale();
    // Same overlap-based units as build(), so the picker replacing the
    // keyboard is exactly as tall as the part of the keyboard it covered.
    var offset = max(_keyboardOverlap(scaledQuery), scaledQuery.padding.bottom);

    // Decide on the keyboard itself: on iPad the overlap can be well under
    // [min] even with a full-size keyboard open.
    // A composer above the keyboard (no or little overlap) keeps the stored
    // height: a picker that small would be unusable.
    if (scaledQuery.viewInsets.bottom < min || offset < minPickerHeight) {
      offset = preferences.emojiPickerHeight.value;
    } else {
      preferences.emojiPickerHeight.set(offset);
    }

    sizeOverride = offset;
  }

  clearOverride() {
    setState(() {
      sizeOverride = null;
    });
  }

  bool hasOverride() {
    return sizeOverride != null;
  }
}
