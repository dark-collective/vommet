import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:flutter/material.dart';

enum UserPresenceStatus {
  offline,
  unknown,
  online,
  unavailable,
}

enum PresenceMessageType {
  userCustom,
}

class UserPresenceMessage {
  PresenceMessageType messageType;
  String message;

  UserPresenceMessage(this.message, this.messageType);
}

class UserPresence {
  UserPresenceStatus status;
  UserPresenceMessage? message;

  /// Vommet: when they were last active, if the server says.
  DateTime? lastActive;

  UserPresence(this.status, {this.message, this.lastActive});
}

extension UserPresenceColor on UserPresenceStatus {
  Color getColor() {
    return switch (this) {
      UserPresenceStatus.offline => Colors.grey,
      UserPresenceStatus.online => Colors.lightGreen,
      UserPresenceStatus.unavailable => Colors.amber,
      UserPresenceStatus.unknown => Colors.grey,
    };
  }
}

abstract class UserPresenceComponent<T extends Client> implements Component<T> {
  Stream<(String, UserPresence)> get onPresenceChanged;

  bool get usePublicReadReceipts;
  Future<void> setUsePublicReadReceipts(bool value);

  bool get typingIndicatorEnabled;
  Future<void> setTypingIndicatorEnabled(bool value);

  /// Vommet: no public read receipts and no typing indicator anywhere,
  /// whatever the settings above and the rooms' own say.
  bool get ghostMode;
  Future<void> setGhostMode(bool value);

  Future<UserPresence> getUserPresence(String userId);

  /// Vommet: the presence already known from sync, without a request; null
  /// when the server hasn't shared one (many disable presence).
  UserPresence? cachedPresence(String userId);

  Future<void> setStatus(UserPresenceStatus status,
      {String? message, bool clearMessage = false});

  /// Vommet: "online" (follows app activity), "idle" or "invisible". Idle and
  /// invisible hold until changed, whatever the app is doing.
  String get presenceMode;

  Future<void> setPresenceMode(String mode);
}
