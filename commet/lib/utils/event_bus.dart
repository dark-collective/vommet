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

  /// Vommet issue 665: a message to jump to once the room is open (a link to
  /// a message).
  String? eventId;

  RoomOpenArgs(this.roomId, this.clientId,
      {this.bypassSpecialRoomTypes = false,
      this.threadId,
      this.openInSpace = true,
      this.eventId});
}

class EventBus {
  /// Vommet issue 595: a room asked for before anything listens (a
  /// notification tap while the main page isn't up yet) used to be dropped.
  /// Keep the latest one and send it once the main page listens; the
  /// microtask lets the rest of the page subscribe first.
  static RoomOpenArgs? _pendingOpenRoom;

  static void _sendPendingOpenRoom() {
    final pending = _pendingOpenRoom;
    if (pending == null) return;
    _pendingOpenRoom = null;
    scheduleMicrotask(() => openRoom.add(pending));
  }

  /// First string is room id, Second string is client id
  static StreamController<RoomOpenArgs> openRoom =
      StreamController<RoomOpenArgs>.broadcast(onListen: _sendPendingOpenRoom);

  static void doOpenRoom(String roomId,
      {String? clientId,
      bool bypassSpecialRoomType = false,
      String? threadId,
      bool openInSpace = true,
      String? eventId}) {
    final args = RoomOpenArgs(roomId, clientId,
        threadId: threadId,
        bypassSpecialRoomTypes: bypassSpecialRoomType,
        openInSpace: openInSpace,
        eventId: eventId);
    if (!openRoom.hasListener) {
      _pendingOpenRoom = args;
      return;
    }
    openRoom.add(args);
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

  /// Vommet issue 665: a jump for a room whose timeline isn't on screen yet
  /// (opening a link to a message in another room). The room's timeline view
  /// takes it once it has laid out; one never taken goes stale, so a later
  /// visit to the room doesn't jump.
  static (String, String, DateTime)? _pendingJump;

  static void setPendingJump(String roomId, String eventId) =>
      _pendingJump = (roomId, eventId, DateTime.now());

  /// The pending jump's event id, when it is for [roomId]; clears it.
  static String? takePendingJump(String roomId) {
    final pending = _pendingJump;
    if (pending == null || pending.$1 != roomId) return null;
    _pendingJump = null;
    if (DateTime.now().difference(pending.$3) > const Duration(minutes: 1)) {
      return null;
    }
    return pending.$2;
  }

  /// Vommet Deep Search: a thread to show in the room's side panel once the
  /// room opens, and the reply in it to jump to. The room's side panel takes
  /// the thread (when it is built, or when the room it shows is opened
  /// again); the thread's timeline view takes the reply. Like
  /// [setPendingJump], one never taken goes stale after a minute.
  static (String, String, DateTime)? _pendingThread;
  static (String, String, DateTime)? _pendingThreadJump;

  static void setPendingThread(String roomId, String threadRootId,
      {String? eventId}) {
    final now = DateTime.now();
    _pendingThread = (roomId, threadRootId, now);
    _pendingThreadJump = eventId == null ? null : (roomId, eventId, now);
  }

  /// The pending thread's root event id, when it is for [roomId]; clears it.
  static String? takePendingThread(String roomId) {
    final pending = _pendingThread;
    if (pending == null || pending.$1 != roomId) return null;
    _pendingThread = null;
    if (DateTime.now().difference(pending.$3) > const Duration(minutes: 1)) {
      return null;
    }
    return pending.$2;
  }

  /// The reply to jump to in the pending thread, when it is for [roomId];
  /// clears it.
  static String? takePendingThreadJump(String roomId) {
    final pending = _pendingThreadJump;
    if (pending == null || pending.$1 != roomId) return null;
    _pendingThreadJump = null;
    if (DateTime.now().difference(pending.$3) > const Duration(minutes: 1)) {
      return null;
    }
    return pending.$2;
  }

  static StreamController<void> focusTimeline = StreamController.broadcast();

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
