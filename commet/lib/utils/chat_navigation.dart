// Vommet: workspace-local chat navigation (Vommet issue 1068).
import 'dart:async';

import 'package:flutter/widgets.dart';

class RoomOpenArgs {
  String roomId;
  String? clientId;
  String? threadId;
  bool bypassSpecialRoomTypes;
  bool openInSpace;

  /// Vommet issue 665: a message to jump to once the room is open (a link to
  /// a message).
  String? eventId;

  RoomOpenArgs(this.roomId, this.clientId,
      {this.bypassSpecialRoomTypes = false,
      this.threadId,
      this.openInSpace = true,
      this.eventId});
}

/// Navigation belongs to a workspace, never to an authenticated session.
/// The main workspace also accepts legacy application-entry events through
/// EventBus. Other scopes do not subscribe to or rebroadcast those events.
class ChatNavigation {
  ChatNavigation({DateTime Function()? now}) : _now = now ?? DateTime.now {
    openRoom = StreamController<RoomOpenArgs>.broadcast(onListen: () {
      final pending = _pendingOpenRoom;
      _pendingOpenRoom = null;
      if (pending != null) {
        scheduleMicrotask(() {
          if (!_disposed) openRoom.add(pending);
        });
      }
    });
  }

  static final main = ChatNavigation();
  final DateTime Function() _now;
  bool _disposed = false;
  RoomOpenArgs? _pendingOpenRoom;
  late final StreamController<RoomOpenArgs> openRoom;
  final openThread = StreamController<(String, String, String)>.broadcast();
  final replyInThread = StreamController<String>.broadcast();
  final closeThread = StreamController<void>.broadcast();
  final openThreadsList = StreamController<void>.broadcast();
  final focusTimeline = StreamController<void>.broadcast();
  final jumpToEvent = StreamController<String>.broadcast();
  final openThreadRootId = ValueNotifier<String?>(null);

  void doOpenRoom(String roomId,
      {String? clientId,
      bool bypassSpecialRoomType = false,
      String? threadId,
      bool openInSpace = true,
      String? eventId}) {
    if (_disposed) return;
    final args = RoomOpenArgs(roomId, clientId,
        bypassSpecialRoomTypes: bypassSpecialRoomType,
        threadId: threadId,
        openInSpace: openInSpace,
        eventId: eventId);
    if (openRoom.hasListener) {
      openRoom.add(args);
    } else {
      _pendingOpenRoom = args;
    }
  }

  void openThreadFor((String, String, String) target, {bool reply = false}) {
    if (_disposed) return;
    if (reply) replyInThread.add(target.$3);
    openThread.add(target);
  }

  void clearThreadHighlight(String? rootId) {
    if (!_disposed && openThreadRootId.value == rootId) {
      openThreadRootId.value = null;
    }
  }

  _PendingChatTarget? _pendingJump;
  _PendingChatTarget? _pendingThread;
  _PendingChatTarget? _pendingThreadJump;

  void setPendingJump(String roomId, String eventId, {String? clientId}) =>
      _pendingJump = _PendingChatTarget(clientId, roomId, eventId, _now());

  String? takePendingJump(String roomId, {String? clientId}) {
    final pending = _pendingJump;
    if (pending == null || !pending.matches(clientId, roomId)) return null;
    _pendingJump = null;
    return pending.valueAt(_now());
  }

  void setPendingThread(String roomId, String threadRootId,
      {String? clientId, String? eventId}) {
    _pendingThread = _PendingChatTarget(clientId, roomId, threadRootId, _now());
    _pendingThreadJump = eventId == null
        ? null
        : _PendingChatTarget(clientId, roomId, eventId, _now(), threadRootId);
  }

  String? takePendingThread(String roomId, {String? clientId}) {
    final pending = _pendingThread;
    if (pending == null || !pending.matches(clientId, roomId)) return null;
    _pendingThread = null;
    return pending.valueAt(_now());
  }

  String? takePendingThreadJump(String roomId,
      {String? clientId, String? threadId}) {
    final pending = _pendingThreadJump;
    if (pending == null ||
        !pending.matches(clientId, roomId) ||
        (threadId != null && pending.threadId != threadId)) return null;
    _pendingThreadJump = null;
    return pending.valueAt(_now());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingOpenRoom = null;
    _pendingJump = _pendingThread = _pendingThreadJump = null;
    openRoom.close();
    openThread.close();
    replyInThread.close();
    closeThread.close();
    openThreadsList.close();
    focusTimeline.close();
    jumpToEvent.close();
    openThreadRootId.dispose();
  }
}

class _PendingChatTarget {
  _PendingChatTarget(this.clientId, this.roomId, this.value, this.created,
      [this.threadId]);
  final String? clientId;
  final String roomId;
  final String value;
  final DateTime created;
  final String? threadId;

  // A null account is only for legacy main-window entry points. Scoped
  // producers always supply it; a different account must not consume it.
  bool matches(String? client, String room) =>
      room == roomId && (clientId == null || clientId == client);
  String? valueAt(DateTime now) =>
      now.difference(created) > const Duration(minutes: 1) ? null : value;
}

/// A scope's identity stays fixed for the lifetime of its workspace subtree.
/// Its owner disposes [navigation], after unmounting that subtree. Standalone
/// chat surfaces retain the main-window fallback used before this extraction.
class ChatNavigationScope extends InheritedWidget {
  const ChatNavigationScope(
      {required this.navigation, required super.child, super.key});
  final ChatNavigation navigation;

  static ChatNavigation read(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<ChatNavigationScope>()
          ?.navigation ??
      ChatNavigation.main;

  @override
  bool updateShouldNotify(ChatNavigationScope oldWidget) =>
      navigation != oldWidget.navigation;
}
