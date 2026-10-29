abstract class Permissions {
  bool get canChangeRoles => false;

  bool get canBan => false;

  bool get canKick => false;

  bool get canSendMessage => false;

  // Vommet issue 317: true when sending is blocked only because this is an
  // encrypted room and encryption isn't available on this device.
  bool get sendBlockedByUnavailableEncryption => false;

  bool get canEditName => false;

  bool get canEditAvatar => false;

  bool get canEditTopic => false;

  bool get canEditAnything =>
      (canEditName || canEditAvatar || canChangeNotificationSettings);

  bool get canEditAppearance => (canEditAvatar || canEditName);

  bool get canEnableE2EE => false;

  bool get canChangeVisibility => false;

  bool get canEditRoomSecurity => canEnableE2EE;

  bool get canChangeNotificationSettings => true;

  bool get canUserEditMessages => true;

  bool get canDeleteOtherUserMessages => true;

  bool get canEditRoomEmoticons => true;

  bool get canEditChildren => true;

  bool get canInviteUser => true;

  bool get canMentionRoom => false;
}
