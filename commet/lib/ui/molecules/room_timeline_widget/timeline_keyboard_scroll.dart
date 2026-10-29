import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Vommet: keyboard scrolling for a room's timeline (Vommet issue 481).
///
/// Wraps a chat (timeline + message input). Key events bubble up from
/// whatever has focus inside it (the message box, a selected message), so:
/// - Page Up / Page Down scroll the timeline by about one screen,
/// - Home jumps to the oldest loaded message,
/// - End jumps to the newest message.
///
/// Home and End are left to a text field that has text in it, so they keep
/// moving the text cursor there. Keys with modifiers are never taken.
///
/// The timeline registers itself with [attach]; it is a reversed list, so
/// "up" (older messages) is towards the max scroll extent.
class TimelineKeyboardScroll extends StatefulWidget {
  const TimelineKeyboardScroll({required this.child, super.key});

  final Widget child;

  static TimelineKeyboardScrollState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<TimelineKeyboardScrollState>();

  @override
  State<TimelineKeyboardScroll> createState() => TimelineKeyboardScrollState();
}

class TimelineKeyboardScrollState extends State<TimelineKeyboardScroll> {
  ScrollController Function()? _controller;
  VoidCallback? _jumpToLatest;

  static const pageFraction = 0.9;
  static const duration = Duration(milliseconds: 150);

  /// Called by the timeline. [controller] is a getter because the timeline
  /// replaces its controller when it reloads; [jumpToLatest] is the
  /// timeline's own "scroll to the newest message".
  void attach(ScrollController Function() controller,
      [VoidCallback? jumpToLatest]) {
    _controller = controller;
    _jumpToLatest = jumpToLatest;
  }

  bool get _focusedTextHasContent {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    final editable = context.findAncestorStateOfType<EditableTextState>();
    return editable != null && editable.textEditingValue.text.isNotEmpty;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isHomeOrEnd =
        key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end;
    if (!isHomeOrEnd &&
        key != LogicalKeyboardKey.pageUp &&
        key != LogicalKeyboardKey.pageDown) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    if (isHomeOrEnd && _focusedTextHasContent) return KeyEventResult.ignored;

    final controller = _controller?.call();
    if (controller == null || !controller.hasClients) {
      return KeyEventResult.ignored;
    }

    final position = controller.position;
    final page = position.viewportDimension * pageFraction;

    double target;
    if (key == LogicalKeyboardKey.pageUp) {
      target = min(position.pixels + page, position.maxScrollExtent);
    } else if (key == LogicalKeyboardKey.pageDown) {
      target = max(position.pixels - page, position.minScrollExtent);
    } else if (key == LogicalKeyboardKey.home) {
      target = position.maxScrollExtent;
    } else {
      if (_jumpToLatest != null) {
        _jumpToLatest!.call();
        return KeyEventResult.handled;
      }
      target = position.minScrollExtent;
    }

    controller.animateTo(target, duration: duration, curve: Curves.easeOut);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}
