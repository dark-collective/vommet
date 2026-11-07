import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/message_effects/message_effect_particles.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/utils/chat_navigation.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

export 'package:commet/utils/chat_navigation.dart' show RoomOpenArgs;

class EventBus {
  // Vommet: legacy application-entry events target the main workspace only
  // (Vommet issue 1068). Local chat widgets use ChatNavigationScope instead.
  static StreamController<RoomOpenArgs> get openRoom =>
      ChatNavigation.main.openRoom;

  static void doOpenRoom(String roomId,
          {String? clientId,
          bool bypassSpecialRoomType = false,
          String? threadId,
          bool openInSpace = true,
          String? eventId}) =>
      ChatNavigation.main.doOpenRoom(roomId,
          clientId: clientId,
          bypassSpecialRoomType: bypassSpecialRoomType,
          threadId: threadId,
          openInSpace: openInSpace,
          eventId: eventId);

  /// Vommet: open a space. First string is space id, second is client id.
  static StreamController<(String, String)> openSpace =
      StreamController<(String, String)>.broadcast();

  /// First string is user id, Second string is client id, third string is context room
  static StreamController<(String, String, String?)> openUserProfile =
      StreamController<(String, String, String?)>.broadcast();

  /// 0] Client Id, 1] Room Id, 2] Thread Root Event Id.
  static get openThread => ChatNavigation.main.openThread;

  /// Vommet issue 322: legacy reply intent for the main workspace.
  static get replyInThread => ChatNavigation.main.replyInThread;

  static StreamController<void> openHomeScreen = StreamController.broadcast();

  static get closeThread => ChatNavigation.main.closeThread;

  static StreamController<Client?> setFilterClient =
      StreamController.broadcast();

  static StreamController<bool> onTextFieldFocused =
      StreamController.broadcast();

  /// Called when the user initially logs in to the app, or on app startup when atleast one user account is already logged in
  static StreamController<BuildContext> onLoggedIn =
      StreamController<BuildContext>.broadcast();

  static StreamController<DropDoneDetails> onFileDropped =
      StreamController<DropDoneDetails>.broadcast();

  static StreamController<Space?> onSelectedSpaceChanged =
      StreamController<Space?>.broadcast();

  static StreamController<Room?> onSelectedRoomChanged =
      StreamController<Room?>.broadcast();

  /// Vommet issue 457: the room [onSelectedRoomChanged] last sent, so a room
  /// list built later (another space, a reopened subspace) still marks it.
  static Room? selectedRoom;

  /// Vommet issue 457: the root event id of the thread open in the side
  /// panel; the main timeline shades that message.
  static ValueNotifier<String?> get openThreadRootId =>
      ChatNavigation.main.openThreadRootId;

  static StreamController<void> startSearch = StreamController.broadcast();

  static StreamController<void> openPinnedMessages =
      StreamController.broadcast();

  // Vommet: the room's thread list in the side panel.
  static get openThreadsList => ChatNavigation.main.openThreadsList;

  static StreamController<void> openCalendar = StreamController.broadcast();

  static StreamController<void> openWidgets = StreamController.broadcast();

  static StreamController<String> onReceivedPushNotificationData =
      StreamController.broadcast();

  static StreamController<void> toggleRoomSidePanel =
      StreamController.broadcast();

  /// Vommet: a room's timeline view swapped in a fresh live timeline ("Jump
  /// to latest" from one opened around an older message); the room's chat
  /// adopts it.
  static StreamController<Timeline> liveTimelineLoaded =
      StreamController.broadcast();

  static get jumpToEvent => ChatNavigation.main.jumpToEvent;

  /// Vommet issue 665: pending main-window message jumps expire after a minute.
  static void setPendingJump(String roomId, String eventId,
          {String? clientId}) =>
      ChatNavigation.main.setPendingJump(roomId, eventId, clientId: clientId);
  static String? takePendingJump(String roomId) =>
      ChatNavigation.main.takePendingJump(roomId);

  /// Vommet Deep Search: pending main-window thread and reply jumps.
  static void setPendingThread(String roomId, String threadRootId,
          {String? eventId, String? clientId}) =>
      ChatNavigation.main.setPendingThread(roomId, threadRootId,
          eventId: eventId, clientId: clientId);
  static String? takePendingThread(String roomId) =>
      ChatNavigation.main.takePendingThread(roomId);
  static String? takePendingThreadJump(String roomId) =>
      ChatNavigation.main.takePendingThreadJump(roomId);

  static get focusTimeline => ChatNavigation.main.focusTimeline;

  /// Vommet: the pinned message bar's list button. Toggles the pinned
  /// messages panel on desktop; on phones it only opens it.
  static StreamController<void> showPinnedMessages =
      StreamController.broadcast();

  static StreamController<MessageEffectParticles> doMessageEffect =
      StreamController.broadcast();

  static StreamController<ScopePopped> onPopInvoked =
      StreamController.broadcast(sync: true);

  /// Vommet issue 555: this client's own profile (`self`) changed.
  static StreamController<Client> ownProfileChanged =
      StreamController.broadcast();
}

class ScopePopped {
  RevealSide? currentMobileSide;
  bool handled = false;
}
