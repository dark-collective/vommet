import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_power_levels.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_room_banned_users.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_room_privileged_users.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixRoomPermissionEntry {
  String title;
  String description;
  String key;
  String? keyParent;
  int powerLevel;
  late int originalPowerLevel;
  IconData? icon;

  /// Vommet: for `events` entries, whether the type is a state event; picks
  /// the fallback (state_default or events_default) when the key is unset.
  bool isStateEvent;
  MatrixRoomPermissionEntry({
    required this.key,
    required this.title,
    required this.description,
    required this.powerLevel,
    this.icon,
    this.keyParent,
    this.isStateEvent = true,
  }) {
    originalPowerLevel = powerLevel;
  }
}

class MatrixRoomRoleEntry {
  String name;
  int powerlevel;
  IconData? icon;

  MatrixRoomRoleEntry({
    required this.name,
    required this.powerlevel,
    this.icon,
  });
}

class MatrixRoomPermissionsPage extends StatefulWidget {
  const MatrixRoomPermissionsPage(this.room,
      {super.key, this.showCalendarPermissions = false});
  final matrix.Room room;
  final bool showCalendarPermissions;

  @override
  State<MatrixRoomPermissionsPage> createState() =>
      _MatrixRoomPermissionsPageState();
}

class _MatrixRoomPermissionsPageState extends State<MatrixRoomPermissionsPage> {
  late List<MatrixRoomRoleEntry> roles;
  late List<MatrixRoomPermissionEntry> permissions;
  bool loading = false;

  String get labelMatrixPermissionsRoleOwner => Intl.message(
        "Owner",
        name: "labelMatrixPermissionsRoleOwner",
        desc: "Label for the room owner role",
      );

  String get labelMatrixPermissionsRoleAdmin => Intl.message(
        "Admin",
        name: "labelMatrixPermissionsRoleAdmin",
        desc: "Label for the room administrator role",
      );

  String get labelMatrixPermissionsRoleModerator => Intl.message(
        "Moderator",
        name: "labelMatrixPermissionsRoleModerator",
        desc: "Label for the room moderator role",
      );

  String get labelMatrixPermissionsRoleMember => Intl.message(
        "Room Member",
        name: "labelMatrixPermissionsRoleMember",
        desc: "Label for the room member role",
      );

  String get labelMatrixPermissionsSpaceManageChildrenTitle => Intl.message(
        "Manage Children",
        name: "labelMatrixPermissionsSpaceManageChildrenTitle",
        desc: "Title for permission to manage children",
      );

  String get labelMatrixPermissionsSpaceManageChildrenDescription =>
      Intl.message(
        "Allows the user to manage which rooms are part of this space",
        name: "labelMatrixPermissionsSpaceManageChildrenDescription",
        desc: "Describes the permission to manage child rooms",
      );

  String get labelMatrixPermissionsRoomDeleteMessagesTitle => Intl.message(
        "Delete Messages",
        name: "labelMatrixPermissionsRoomDeleteMessagesTitle",
        desc: "Title for permission to delete messages",
      );

  String get labelMatrixPermissionsRoomDeleteMessagesDescription =>
      Intl.message(
        "Allows the user to delete messages sent by others",
        name: "labelMatrixPermissionsRoomDeleteMessagesDescription",
        desc: "Describes the permission to delete messages",
      );

  String get labelMatrixPermissionsRoomSendMessagesTitle => Intl.message(
        "Send Messages",
        name: "labelMatrixPermissionsRoomSendMessagesTitle",
        desc: "Title for the permission to send messages",
      );

  String get labelMatrixPermissionsRoomSendMessagesDescription => Intl.message(
        "Allows a user to send messages in this room",
        name: "labelMatrixPermissionsRoomSendMessagesDescription",
        desc: "Describes the permission to send messages",
      );

  String get labelMatrixPermissionsRoomAddReactionsTitle => Intl.message(
        "Add Reactions",
        name: "labelMatrixPermissionsRoomAddReactionsTitle",
        desc: "Title for the permission to add an emoji reaction to a message",
      );

  String get labelMatrixPermissionsRoomAddReactionsDescription => Intl.message(
        "Add reactions to messages",
        name: "labelMatrixPermissionsRoomAddReactionsDescription",
        desc: "describes the permission to add an emoji reaction to a message",
      );

  String get labelMatrixPermissionsRoomHistoryVisibilityTitle => Intl.message(
        "History Visibility",
        name: "labelMatrixPermissionsRoomHistoryVisibilityTitle",
        desc: "Title for the permission to add change room history settings",
      );

  String get labelMatrixPermissionsRoomHistoryVisibilityDescription =>
      Intl.message(
        "Allows the user to change the visibility of chat history in this room",
        name: "labelMatrixPermissionsRoomHistoryVisibilityDescription",
        desc: "describes the permission to change room history settings",
      );

  String get labelMatrixPermissionsRoomAvatarTitle => Intl.message(
        "Set Room Avatar",
        name: "labelMatrixPermissionsRoomAvatarTitle",
        desc: "Title for the permission to add change the rooms avatar image",
      );

  String get labelMatrixPermissionsRoomAvatarDescription => Intl.message(
        "Change the room's avatar image",
        name: "labelMatrixPermissionsRoomAvatarDescription",
        desc: "Title for the permission to add change the rooms avatar image",
      );

  String get labelMatrixPermissionsMentionRoomTitle => Intl.message(
        "Use @room mentions",
        name: "labelMatrixPermissionsMentionRoomTitle",
        desc: "Title for the permission to use '@room' mentions in a message",
      );

  String get labelMatrixPermissionsMentionRoomDescription => Intl.message(
        "Allow use of '@room' to notify all members of the room.",
        name: "labelMatrixPermissionsMentionRoomDescription",
        desc:
            "Description for the permission to use '@room' mentions in a message",
      );

  String get labelMatrixPermissionsChangeRoomNameTitle => Intl.message(
        "Change room name",
        name: "labelMatrixPermissionsChangeRoomNameTitle",
        desc: "Title for the permission to add change the rooms name",
      );

  String get labelMatrixPermissionsChangeRoomNameDescription => Intl.message(
        "Allows the user to change the name of this room",
        name: "labelMatrixPermissionsChangeRoomNameDescription",
        desc: "Description for the permission to add change the rooms name",
      );

  String get labelMatrixPermissionsChangeRoomTopicTitle => Intl.message(
        "Change room topic",
        name: "labelMatrixPermissionsChangeRoomTopicTitle",
        desc: "Title for the permission to add change the rooms topic",
      );

  String get labelMatrixPermissionsChangeRoomTopicDescription => Intl.message(
        "Allows the user to change the topic of this room",
        name: "labelMatrixPermissionsChangeRoomTopicDescription",
        desc: "Description for the permission to add change the rooms topic",
      );

  String get labelMatrixPermissionsChangeRoomPermissionsTitle => Intl.message(
        "Change permissions",
        name: "labelMatrixPermissionsChangeRoomPermissionsTitle",
        desc: "Title for the permission to change permissions of the room",
      );

  String get labelMatrixPermissionsChangeRoomPermissionsDescription =>
      Intl.message(
        "Allows the user to change permission settings",
        name: "labelMatrixPermissionsChangeRoomPermissionsDescription",
        desc:
            "Description for the permission to change permissions of the room",
      );

  String get labelMatrixPermissionsKickUserTitle => Intl.message(
        "Kick users",
        name: "labelMatrixPermissionsKickUserTitle",
        desc: "Title for the permission to kick other users out of the room",
      );

  String get labelMatrixPermissionsKickUserDescription => Intl.message(
        "Kick other users out of the room",
        name: "labelMatrixPermissionsKickUserDescription",
        desc:
            "Description for the permission to kick other users out of the room",
      );

  String get labelMatrixPermissionsBanUserTitle => Intl.message(
        "Ban users",
        name: "labelMatrixPermissionsBanUserTitle",
        desc: "Title for the permission to ban other users from the room",
      );

  String get labelMatrixPermissionsBanUserDescription => Intl.message(
        "Ban other users from the room",
        name: "labelMatrixPermissionsBanUserDescription",
        desc: "Description for the permission to ban other users from the room",
      );

  String get labelMatrixPermissionsJoinCallTitle => Intl.message(
        "Join Call",
        name: "labelMatrixPermissionsJoinCallTitle",
        desc:
            "Title for the permission to allow users to join a call in a room",
      );

  String get labelMatrixPermissionsJoinCallDescription => Intl.message(
        "Allow users to join an ongoing call in this room",
        name: "labelMatrixPermissionsJoinCallDescription",
        desc:
            "Description for the permission to allow users to join a call in a room",
      );

  String get labelMatrixPermissionsAddCalendarEventTitle => Intl.message(
        "Edit Calendar Events",
        name: "labelMatrixPermissionsAddCalendarEventTitle",
        desc: "Title for the permission to allow users to edit the calendar",
      );

  String get labelMatrixPermissionsAddCalendarEventDescription => Intl.message(
        "Allow users to edit events in the calendar",
        name: "labelMatrixPermissionsAddCalendarEventDescription",
        desc:
            "Description for the permission to allow users to create an event on the calendar",
      );

  // Vommet: permission row "Invite users".
  String get labelMatrixPermissionsInviteUsersTitle => Intl.message(
        "Invite users",
        name: "labelMatrixPermissionsInviteUsersTitle",
        desc: "Title for the permission to invite people",
      );

  String get labelMatrixPermissionsInviteUsersDescription => Intl.message(
        "Allows the user to invite people to this room",
        name: "labelMatrixPermissionsInviteUsersDescription",
        desc: "Description for the permission to invite people",
      );

  String get labelMatrixPermissionsInviteUsersSpaceDescription => Intl.message(
        "Allows the user to invite people to this space",
        name: "labelMatrixPermissionsInviteUsersSpaceDescription",
        desc: "Description for the permission to invite people, in a space",
      );

  // Vommet: permission row "Change other settings".
  String get labelMatrixPermissionsChangeSettingsTitle => Intl.message(
        "Change other settings",
        name: "labelMatrixPermissionsChangeSettingsTitle",
        desc:
            "Title for the permission to change settings without a dedicated permission (state_default)",
      );

  String get labelMatrixPermissionsChangeSettingsDescription => Intl.message(
        "Allows the user to change any setting that has no permission of its own here",
        name: "labelMatrixPermissionsChangeSettingsDescription",
        desc:
            "Description for the permission to change settings without a dedicated permission (state_default)",
      );

  // Vommet: permission row "Enable encryption".
  String get labelMatrixPermissionsEnableEncryptionTitle => Intl.message(
        "Enable encryption",
        name: "labelMatrixPermissionsEnableEncryptionTitle",
        desc: "Title for the permission to enable encryption",
      );

  String get labelMatrixPermissionsEnableEncryptionDescription => Intl.message(
        "Allows the user to turn on end-to-end encryption for this room. It can't be turned off again",
        name: "labelMatrixPermissionsEnableEncryptionDescription",
        desc: "Description for the permission to enable encryption",
      );

  // Vommet: permission row "Change main address".
  String get labelMatrixPermissionsChangeMainAddressTitle => Intl.message(
        "Change main address",
        name: "labelMatrixPermissionsChangeMainAddressTitle",
        desc: "Title for the permission to change the canonical alias",
      );

  String get labelMatrixPermissionsChangeMainAddressDescription => Intl.message(
        "Allows the user to change the main address of this room",
        name: "labelMatrixPermissionsChangeMainAddressDescription",
        desc: "Description for the permission to change the canonical alias",
      );

  String get labelMatrixPermissionsChangeMainAddressSpaceDescription =>
      Intl.message(
        "Allows the user to change the main address of this space",
        name: "labelMatrixPermissionsChangeMainAddressSpaceDescription",
        desc:
            "Description for the permission to change the canonical alias, in a space",
      );

  // Vommet: permission row "Upgrade the room".
  String get labelMatrixPermissionsUpgradeRoomTitle => Intl.message(
        "Upgrade the room",
        name: "labelMatrixPermissionsUpgradeRoomTitle",
        desc: "Title for the permission to upgrade (tombstone) the room",
      );

  String get labelMatrixPermissionsUpgradeRoomDescription => Intl.message(
        "Allows the user to upgrade this room to a new room version",
        name: "labelMatrixPermissionsUpgradeRoomDescription",
        desc: "Description for the permission to upgrade (tombstone) the room",
      );

  String get labelMatrixPermissionsUpgradeRoomSpaceDescription => Intl.message(
        "Allows the user to upgrade this space to a new room version",
        name: "labelMatrixPermissionsUpgradeRoomSpaceDescription",
        desc:
            "Description for the permission to upgrade (tombstone) the room, in a space",
      );

  // Vommet: permission row "Change server access rules".
  String get labelMatrixPermissionsServerAccessTitle => Intl.message(
        "Change server access rules",
        name: "labelMatrixPermissionsServerAccessTitle",
        desc: "Title for the permission to change the server ACL",
      );

  String get labelMatrixPermissionsServerAccessDescription => Intl.message(
        "Allows the user to block or allow whole servers from taking part in this room",
        name: "labelMatrixPermissionsServerAccessDescription",
        desc: "Description for the permission to change the server ACL",
      );

  String get labelMatrixPermissionsServerAccessSpaceDescription => Intl.message(
        "Allows the user to block or allow whole servers from taking part in this space",
        name: "labelMatrixPermissionsServerAccessSpaceDescription",
        desc:
            "Description for the permission to change the server ACL, in a space",
      );

  // Vommet: permission row "Manage pinned messages".
  String get labelMatrixPermissionsPinnedMessagesTitle => Intl.message(
        "Manage pinned messages",
        name: "labelMatrixPermissionsPinnedMessagesTitle",
        desc: "Title for the permission to pin messages",
      );

  String get labelMatrixPermissionsPinnedMessagesDescription => Intl.message(
        "Allows the user to pin and unpin messages",
        name: "labelMatrixPermissionsPinnedMessagesDescription",
        desc: "Description for the permission to pin messages",
      );

  // Vommet: permission row "Manage widgets".
  String get labelMatrixPermissionsWidgetsTitle => Intl.message(
        "Manage widgets",
        name: "labelMatrixPermissionsWidgetsTitle",
        desc: "Title for the permission to modify widgets",
      );

  String get labelMatrixPermissionsWidgetsDescription => Intl.message(
        "Allows the user to add, change and remove widgets in this room",
        name: "labelMatrixPermissionsWidgetsDescription",
        desc: "Description for the permission to modify widgets",
      );

  // Vommet: permission row "Delete own messages".
  String get labelMatrixPermissionsDeleteOwnMessagesTitle => Intl.message(
        "Delete own messages",
        name: "labelMatrixPermissionsDeleteOwnMessagesTitle",
        desc:
            "Title for the permission to redact own messages (m.room.redaction)",
      );

  String get labelMatrixPermissionsDeleteOwnMessagesDescription => Intl.message(
        "Allows the user to delete messages they sent themselves",
        name: "labelMatrixPermissionsDeleteOwnMessagesDescription",
        desc:
            "Description for the permission to redact own messages (m.room.redaction)",
      );

  void initPermissions() {
    bool isCalendarRoom = widget.showCalendarPermissions;
    final isSpace = widget.room.isSpace;
    var version = int.tryParse(widget.room.roomVersion ?? "1");

    roles = [
      if (version != null && version >= 12)
        MatrixRoomRoleEntry(
            name: labelMatrixPermissionsRoleOwner,
            powerlevel: 150,
            icon: Icons.local_police),
      MatrixRoomRoleEntry(
        name: labelMatrixPermissionsRoleAdmin,
        powerlevel: 100,
        icon: Icons.security,
      ),
      MatrixRoomRoleEntry(
        name: labelMatrixPermissionsRoleModerator,
        powerlevel: 50,
        icon: Icons.shield_rounded,
      ),
      if (isCalendarRoom)
        MatrixRoomRoleEntry(
          name: "Calendar Moderator",
          powerlevel: 25,
          icon: Icons.edit_calendar,
        ),
      MatrixRoomRoleEntry(
        name: labelMatrixPermissionsRoleMember,
        powerlevel: 0,
        icon: Icons.groups,
      ),
    ];

    permissions = List.empty(growable: true);

    if (widget.room.isSpace) {
      permissions.addAll([
        MatrixRoomPermissionEntry(
          key: "m.space.child",
          keyParent: "events",
          title: labelMatrixPermissionsSpaceManageChildrenTitle,
          description: labelMatrixPermissionsSpaceManageChildrenDescription,
          powerLevel: 50,
          icon: Icons.list,
        ),
      ]);
    } else {
      permissions.addAll([
        MatrixRoomPermissionEntry(
          key: "redact",
          title: labelMatrixPermissionsRoomDeleteMessagesTitle,
          description: labelMatrixPermissionsRoomDeleteMessagesDescription,
          powerLevel: 50,
          icon: Icons.delete,
        ),
        MatrixRoomPermissionEntry(
          key: "events_default",
          title: labelMatrixPermissionsRoomSendMessagesTitle,
          description: labelMatrixPermissionsRoomSendMessagesDescription,
          powerLevel: 0,
          icon: Icons.message,
        ),
        MatrixRoomPermissionEntry(
          key: "m.reaction",
          keyParent: "events",
          title: labelMatrixPermissionsRoomAddReactionsTitle,
          description: labelMatrixPermissionsRoomAddReactionsDescription,
          icon: Icons.favorite,
          powerLevel: 0,
          isStateEvent: false,
        ),
        MatrixRoomPermissionEntry(
          key: "m.room.history_visibility",
          keyParent: "events",
          title: labelMatrixPermissionsRoomHistoryVisibilityTitle,
          description: labelMatrixPermissionsRoomHistoryVisibilityDescription,
          powerLevel: 50,
          icon: Icons.history,
        ),
        // Vommet: the rest of Element's room-only permissions.
        MatrixRoomPermissionEntry(
          key: "m.room.redaction",
          keyParent: "events",
          title: labelMatrixPermissionsDeleteOwnMessagesTitle,
          description: labelMatrixPermissionsDeleteOwnMessagesDescription,
          powerLevel: 0,
          icon: Icons.delete_outline,
          isStateEvent: false,
        ),
        // Encryption can't be turned off, so the level only matters before.
        if (!widget.room.encrypted)
          MatrixRoomPermissionEntry(
            key: "m.room.encryption",
            keyParent: "events",
            title: labelMatrixPermissionsEnableEncryptionTitle,
            description: labelMatrixPermissionsEnableEncryptionDescription,
            powerLevel: 100,
            icon: Icons.lock,
          ),
        MatrixRoomPermissionEntry(
          key: "m.room.pinned_events",
          keyParent: "events",
          title: labelMatrixPermissionsPinnedMessagesTitle,
          description: labelMatrixPermissionsPinnedMessagesDescription,
          powerLevel: 50,
          icon: Icons.push_pin,
        ),
        MatrixRoomPermissionEntry(
          key: "im.vector.modular.widgets",
          keyParent: "events",
          title: labelMatrixPermissionsWidgetsTitle,
          description: labelMatrixPermissionsWidgetsDescription,
          powerLevel: 50,
          icon: Icons.widgets,
        ),
      ]);
    }

    permissions.addAll([
      MatrixRoomPermissionEntry(
        key: "m.room.avatar",
        keyParent: "events",
        title: labelMatrixPermissionsRoomAvatarTitle,
        description: labelMatrixPermissionsRoomAvatarDescription,
        icon: Icons.image,
        powerLevel: 50,
      ),
      MatrixRoomPermissionEntry(
        key: "room",
        keyParent: "notifications",
        title: labelMatrixPermissionsMentionRoomTitle,
        description: labelMatrixPermissionsMentionRoomDescription,
        icon: Icons.notification_add,
        powerLevel: 50,
      ),
      MatrixRoomPermissionEntry(
        key: "m.room.power_levels",
        keyParent: "events",
        title: labelMatrixPermissionsChangeRoomPermissionsTitle,
        description: labelMatrixPermissionsChangeRoomPermissionsDescription,
        powerLevel: 50,
        icon: Icons.admin_panel_settings,
      ),
      MatrixRoomPermissionEntry(
        key: "m.room.name",
        keyParent: "events",
        title: labelMatrixPermissionsChangeRoomNameTitle,
        description: labelMatrixPermissionsChangeRoomNameDescription,
        powerLevel: 50,
        icon: Icons.edit,
      ),
      MatrixRoomPermissionEntry(
        key: "m.room.topic",
        keyParent: "events",
        title: labelMatrixPermissionsChangeRoomTopicTitle,
        description: labelMatrixPermissionsChangeRoomTopicDescription,
        icon: Icons.edit_note_rounded,
        powerLevel: 50,
      ),
      MatrixRoomPermissionEntry(
        key: "kick",
        title: labelMatrixPermissionsKickUserTitle,
        description: labelMatrixPermissionsKickUserDescription,
        powerLevel: 50,
        icon: Icons.gavel,
      ),
      MatrixRoomPermissionEntry(
        key: "ban",
        title: labelMatrixPermissionsBanUserTitle,
        description: labelMatrixPermissionsBanUserDescription,
        powerLevel: 100,
        icon: Icons.gavel,
      ),
      // Vommet: the rest of Element's permissions that rooms and spaces share.
      MatrixRoomPermissionEntry(
        key: "invite",
        title: labelMatrixPermissionsInviteUsersTitle,
        description: isSpace
            ? labelMatrixPermissionsInviteUsersSpaceDescription
            : labelMatrixPermissionsInviteUsersDescription,
        powerLevel: 0,
        icon: Icons.person_add,
      ),
      MatrixRoomPermissionEntry(
        key: "m.room.canonical_alias",
        keyParent: "events",
        title: labelMatrixPermissionsChangeMainAddressTitle,
        description: isSpace
            ? labelMatrixPermissionsChangeMainAddressSpaceDescription
            : labelMatrixPermissionsChangeMainAddressDescription,
        powerLevel: 50,
        icon: Icons.alternate_email,
      ),
      MatrixRoomPermissionEntry(
        key: "m.room.tombstone",
        keyParent: "events",
        title: labelMatrixPermissionsUpgradeRoomTitle,
        description: isSpace
            ? labelMatrixPermissionsUpgradeRoomSpaceDescription
            : labelMatrixPermissionsUpgradeRoomDescription,
        powerLevel: 100,
        icon: Icons.upgrade,
      ),
      MatrixRoomPermissionEntry(
        key: "m.room.server_acl",
        keyParent: "events",
        title: labelMatrixPermissionsServerAccessTitle,
        description: isSpace
            ? labelMatrixPermissionsServerAccessSpaceDescription
            : labelMatrixPermissionsServerAccessDescription,
        powerLevel: 100,
        icon: Icons.dns,
      ),
      MatrixRoomPermissionEntry(
        key: "state_default",
        title: labelMatrixPermissionsChangeSettingsTitle,
        description: labelMatrixPermissionsChangeSettingsDescription,
        powerLevel: 50,
        icon: Icons.settings,
      ),
    ]);

    permissions.addAll([
      MatrixRoomPermissionEntry(
        key: "org.matrix.msc3401.call.member",
        keyParent: "events",
        title: labelMatrixPermissionsJoinCallTitle,
        description: labelMatrixPermissionsJoinCallDescription,
        icon: Icons.call,
        powerLevel: 0,
      ),
    ]);

    if (isCalendarRoom) {
      permissions.addAll([
        MatrixRoomPermissionEntry(
          key: "chat.commet.calendar_events",
          keyParent: "events",
          title: labelMatrixPermissionsAddCalendarEventTitle,
          description: labelMatrixPermissionsAddCalendarEventDescription,
          icon: Icons.calendar_month,
          powerLevel: 0,
        ),
      ]);
    }

    if (preferences.developerMode.value == true) {
      var powerLevels = widget.room.states["m.room.power_levels"]?[""];
      if (powerLevels != null) {
        var events = powerLevels.content.tryGetMap<String, dynamic>("events");
        if (events != null) {
          for (var entry in events.entries) {
            if (permissions.any(
                (i) => i.keyParent == "events" && i.key == entry.key)) continue;

            permissions.add(MatrixRoomPermissionEntry(
                key: entry.key,
                title: entry.key,
                keyParent: "events",
                description:
                    "Allow the user to send events of type '${entry.key}'",
                icon: Icons.question_mark_rounded,
                powerLevel: entry.value));
          }
        }
      }

      Log.i("Power Levels: ${powerLevels!.content}");
    }
  }

  @override
  void initState() {
    initPermissions();

    var event = widget.room.states["m.room.power_levels"]?[""];
    if (event != null) {
      updatePowerLevels(event.content);
    } else {
      loading = true;

      widget.room.postLoad().then((value) {
        var event = widget.room.getState("m.room.power_levels");
        updatePowerLevels(event!.content);
        setState(() {
          loading = false;
        });
      });
    }

    super.initState();
  }

  void updatePowerLevels(Map<String, Object?> content) {
    // Vommet: an unset key falls back per the spec (state_default for state
    // events, events_default for message events, spec defaults for top-level
    // keys such as invite = 0), not always to state_default.
    for (var perm in permissions) {
      final level = resolvePermissionLevel(content,
          key: perm.key,
          parent: perm.keyParent,
          isStateEvent: perm.isStateEvent);
      perm.powerLevel = level;
      perm.originalPowerLevel = level;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    var canEdit = widget.room.canChangeStateEvent("m.room.power_levels");
    return MatrixRoomPermissionsView(
      permissions,
      roles,
      setPermissions: setPermissions,
      canEdit: canEdit,
      // Vommet: people first, like Element's Roles & Permissions.
      leading: [
        MatrixRoomPrivilegedUsers(widget.room, roles: roles),
        MatrixRoomBannedUsers(widget.room),
      ],
    );
  }

  Future<void> setPermissions(
    List<MatrixRoomPermissionEntry> permissions,
  ) async {
    var mxRoom = widget.room;
    var event = mxRoom.states["m.room.power_levels"]?[""];
    // Vommet: edit a copy, so a failed send doesn't leave the cached state
    // changed.
    var content = powerLevelsWithPermissions(event?.content ?? {}, {
      for (var perm in permissions)
        if (perm.powerLevel != perm.originalPowerLevel)
          (perm.keyParent, perm.key): perm.powerLevel
    });

    await mxRoom.client.setRoomStateWithKey(
      mxRoom.id,
      "m.room.power_levels",
      "",
      content,
    );
  }
}
