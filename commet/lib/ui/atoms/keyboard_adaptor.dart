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
  });

  final Widget child;
  final bool enabled;
  final Widget? paddingContent;
  final bool Function()? shouldPushContent;
  final KeyboardAdaptorController? controller;

  /// Vommet composer round 6: [child] takes all the height the adaptor
  /// doesn't (the expanded message box).
  final bool expandChild;
  @override
  State<KeyboardAdaptor> createState() => _KeyboardAdaptorState();
}

class _KeyboardAdaptorState extends State<KeyboardAdaptor> {
  double? sizeOverride;
  double? _bottom;

  @override
  initState() {
    super.initState();

    widget.controller?.keepCurrentSize = keepCurrentSize;
    widget.controller?.clearOverride = clearOverride;
    widget.controller?.hasOverride = hasOverride;
  }

  void _updatePosition(Duration _) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final globalBottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (globalBottom != _bottom) {
        setState(() => _bottom = globalBottom);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var scaledQuery = MediaQuery.of(context).scale();
    var viewInsetsBottom = scaledQuery.viewInsets.bottom;

    // Vommet issue 974: on iPad (and desktop/tablet multi-pane layouts),
    // the composer is not at the bottom of the screen; headers, caulk and
    // side panels offset the chat. When the on-screen keyboard opens, the
    // required spacer is the actual overlap between this adaptor's bottom
    // edge and the top edge of the keyboard, not the full viewInsets.bottom
    // from the window edge.
    if (viewInsetsBottom > 0) {
      final screenHeight = scaledQuery.size.height;
      final keyboardTop = screenHeight - viewInsetsBottom;
      final bottom = _bottom ?? screenHeight;
      viewInsetsBottom = max(0.0, bottom - keyboardTop);
    }

    WidgetsBinding.instance.addPostFrameCallback(_updatePosition);

    var offset = max(viewInsetsBottom, scaledQuery.padding.bottom);

    var padding = scaledQuery.viewPadding;

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
      children: [
        Flexible(
            flex: widget.expandChild ? 1 : 0,
            fit: FlexFit.tight,
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

  keepCurrentSize({double min = 300}) {
    var scaledQuery = MediaQuery.of(context).scale();
    var offset = max(scaledQuery.viewInsets.bottom, scaledQuery.padding.bottom);

    if (offset < min) {
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
