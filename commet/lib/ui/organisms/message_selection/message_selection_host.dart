import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a key does while messages are selected.
enum SelectionKeyAction { exit, copy, delete }

/// The action for a key press, or null to leave the key alone. [typing]
/// is true while a text field has focus, [textSelected] when that field
/// has text selected: Delete and Ctrl+C then stay the field's.
SelectionKeyAction? selectionKeyAction(LogicalKeyboardKey key,
    {required bool ctrlOrMeta,
    required bool typing,
    required bool textSelected}) {
  if (key == LogicalKeyboardKey.escape) return SelectionKeyAction.exit;
  if (key == LogicalKeyboardKey.keyC && ctrlOrMeta && !textSelected) {
    return SelectionKeyAction.copy;
  }
  if (key == LogicalKeyboardKey.delete && !ctrlOrMeta && !typing) {
    return SelectionKeyAction.delete;
  }
  return null;
}

/// Vommet: owns a room view's [MessageSelection] and hands it down to the
/// timeline. Esc (desktop) and the back gesture (Android) stop selecting;
/// Ctrl+C copies the selection and Delete asks to delete it.
class MessageSelectionHost extends StatefulWidget {
  const MessageSelectionHost(
      {required this.room,
      required this.timeline,
      required this.child,
      this.enabled = true,
      super.key});

  final Room room;
  final Timeline timeline;
  final bool enabled;
  final Widget child;

  @override
  State<MessageSelectionHost> createState() => _MessageSelectionHostState();
}

class _MessageSelectionHostState extends State<MessageSelectionHost> {
  MessageSelection? selection;
  StreamSubscription? popSubscription;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;

    selection = MessageSelection(widget.room)
      ..timeline = widget.timeline
      ..register();
    popSubscription = EventBus.onPopInvoked.stream.listen(onPopInvoked);
    HardwareKeyboard.instance.addHandler(onKey);
  }

  @override
  void didUpdateWidget(covariant MessageSelectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeline != widget.timeline) {
      selection?.exit();
      selection?.timeline = widget.timeline;
    }
  }

  @override
  void dispose() {
    if (selection != null) HardwareKeyboard.instance.removeHandler(onKey);
    popSubscription?.cancel();
    selection?.dispose();
    super.dispose();
  }

  bool onKey(KeyEvent event) {
    final selection = this.selection;
    if (selection == null || !selection.active || selection.busy) return false;
    if (event is! KeyDownEvent) return false;

    final field = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    final keyboard = HardwareKeyboard.instance;
    final action = selectionKeyAction(event.logicalKey,
        ctrlOrMeta: keyboard.isControlPressed || keyboard.isMetaPressed,
        typing: field != null,
        textSelected:
            field != null && !field.textEditingValue.selection.isCollapsed);
    if (action == null) return false;
    // Leave keys to a dialog or menu open above the room.
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;

    switch (action) {
      case SelectionKeyAction.exit:
        selection.exit();
      case SelectionKeyAction.copy:
        selection.copy();
      case SelectionKeyAction.delete:
        if (selection.deletableCount == 0) return false;
        selection.delete(context);
    }
    return true;
  }

  void onPopInvoked(ScopePopped event) {
    final selection = this.selection;
    if (event.handled || selection == null || !selection.active) return;
    if (event.currentMobileSide == RevealSide.left) return;

    selection.exit();
    event.handled = true;
  }

  @override
  Widget build(BuildContext context) {
    final selection = this.selection;
    if (selection == null) return widget.child;
    return MessageSelectionScope(selection: selection, child: widget.child);
  }
}
