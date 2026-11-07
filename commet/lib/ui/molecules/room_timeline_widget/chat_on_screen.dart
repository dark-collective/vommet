import 'package:flutter/widgets.dart';

/// Vommet issue 408: whether the room's chat is actually on screen. On phones
/// the chat panel stays mounted behind the room list (tapping a space reopens
/// its last room there), where its timeline still sits at the bottom; read
/// receipts wait until the chat is revealed. Without one above it, a chat
/// counts as on screen.
class ChatOnScreen extends InheritedNotifier<ValueNotifier<bool>> {
  const ChatOnScreen(
      {required ValueNotifier<bool> visible, required super.child, super.key})
      : super(notifier: visible);

  static ValueNotifier<bool>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatOnScreen>()?.notifier;
}
