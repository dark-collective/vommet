import 'dart:async';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/message_effects/message_effect_particles.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class RoomOpenArgs {
  String roomId;
  String? clientId;
  String? threadId;
  bool bypassSpecialRoomTypes;
  bool openInSpace;

  RoomOpenArgs(this.roomId, this.clientId,
      {this.bypassSpecialRoomTypes = false,
      this.threadId,
      this.openInSpace = true});
}

class EventBus {
  /// First string is room id, Second string is client id
  static StreamController<RoomOpenArgs> openRoom =
      StreamController<RoomOpenArgs>.broadcast();

  static void doOpenRoom(String roomId,
      {String? clientId,
      bool bypassSpecialRoomType = false,
      String? threadId,
      bool openInSpace = true}) {
    openRoom.add(RoomOpenArgs(roomId, clientId,
        threadId: threadId,
        bypassSpecialRoomTypes: bypassSpecialRoomType,
        openInSpace: openInSpace));
  }

  /// Vommet: open a space. First string is space id, second is client id.
  static StreamController<(String, String)> openSpace =
      StreamController<(String, String)>.broadcast();

  /// First string is user id, Second string is client id, third string is context room
  static StreamController<(String, String, String?)> openUserProfile =
      StreamController<(String, String, String?)>.broadcast();

  /// 0] Client Id
  /// 1] Room Id
  /// 2] Thread Root Event Id
  static StreamController<(String, String, String)> openThread =
      StreamController<(String, String, String)>.broadcast();

  /// Vommet issue 322: "Reply in Thread" was picked for this thread root
  /// event id. Sent just before its [openThread], whose message box then
  /// takes the focus like a reply's does.
  static StreamController<String> replyInThread =
      StreamController<String>.broadcast();

  static StreamController<void> openHomeScreen = StreamController.broadcast();

  static StreamController<void> closeThread = StreamController.broadcast();

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
  static final ValueNotifier<String?> openThreadRootId = ValueNotifier(null);

  static StreamController<void> startSearch = StreamController.broadcast();

  static StreamController<void> openPinnedMessages =
      StreamController.broadcast();

  // Vommet: the room's thread list in the side panel.
  static StreamController<void> openThreadsList = StreamController.broadcast();

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

  static StreamController<String> jumpToEvent = StreamController.broadcast();

  static StreamController<void> focusTimeline = StreamController.broadcast();

  /// Vommet: opens the pinned messages panel (unlike [openPinnedMessages],
  /// never closes it).
  static StreamController<void> showPinnedMessages =
      StreamController.broadcast();

  static StreamController<MessageEffectParticles> doMessageEffect =
      StreamController.broadcast();

  static StreamController<ScopePopped> onPopInvoked =
      StreamController.broadcast(sync: true);
}

class ScopePopped {
  RevealSide? currentMobileSide;
  bool handled = false;
}
