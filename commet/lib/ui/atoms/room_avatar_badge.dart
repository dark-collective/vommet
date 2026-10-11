import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';

/// Icon to show on a room avatar's corner so its type stays visible when an
/// avatar (or a placeholder letter) replaces the type icon. Only voice rooms
/// get one for now; uses the same speaker as the sidebar's type icon.
IconData? roomAvatarBadge(Room room) {
  final dm = room.client.getComponent<DirectMessagesComponent>();
  if (dm?.isRoomDirectMessage(room) == true) return null;
  if (room.getComponent<VoipRoomComponent>() != null) {
    // A speaker reads as "someone is talking"; headphones only say "voice".
    return preferences.experimentSidebarSubspaceGuides.value
        ? Icons.headphones
        : Icons.volume_up;
  }
  return null;
}
