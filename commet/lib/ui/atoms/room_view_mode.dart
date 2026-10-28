import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/foundation.dart';

/// Vommet: switching a voice room between its call view and its text chat
/// (experiment `experiment_voice_room_chat`).
class RoomViewMode {
  /// Whether the open room is shown as its text chat instead of its special
  /// view (a voice room's call). Set by MainPageState.selectRoom.
  static final ValueNotifier<bool> showingText = ValueNotifier(false);

  /// A voice room, with the experiment on.
  static bool offersChat(Room room) =>
      preferences.experimentVoiceRoomChat.value &&
      room.getComponent<VoipRoomComponent>() != null;

  static void openChat(Room room) => EventBus.doOpenRoom(room.identifier,
      clientId: room.client.identifier, bypassSpecialRoomType: true);

  static void openCall(Room room) =>
      EventBus.doOpenRoom(room.identifier, clientId: room.client.identifier);
}
