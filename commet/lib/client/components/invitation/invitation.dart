import 'package:flutter/material.dart';

class Invitation {
  String roomId;
  String? displayName;
  String? senderId;
  Color? color;
  ImageProvider? avatar;

  /// Vommet: the inviter marked this as a direct message.
  bool isDirect;

  /// Vommet issue 734: room invites shown under this one, a space's invite
  /// (or a space you're in, see [spaceJoined]). Empty for a plain invite.
  List<Invitation> groupedRooms = [];

  /// Vommet issue 734: this entry stands for a space you're already in and
  /// only groups its room invites; there is no invite to the space itself.
  bool spaceJoined;

  bool get isGroup => groupedRooms.isNotEmpty;

  Invitation(
      {required this.roomId,
      this.displayName,
      this.color,
      this.avatar,
      this.senderId,
      this.isDirect = false,
      this.spaceJoined = false});

  @override
  bool operator ==(Object other) {
    if (other is! Invitation) return false;
    return roomId == other.roomId;
  }

  @override
  int get hashCode => roomId.hashCode;
}
