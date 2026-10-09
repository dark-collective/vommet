import 'package:commet/client/client.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/client/components/space_banner/space_banner_component.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/invitation_view/send_invitation.dart';
import 'package:commet/ui/pages/manage_space_rooms/manage_space_rooms_page.dart';
import 'package:commet/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:commet/ui/pages/settings/room_settings_page.dart';
import 'package:commet/ui/pages/settings/space_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet: the space menu opened from the space name in the sidebar header
/// (Discord's server menu, limited to what a Matrix space can do).
class SpaceMenu {
  static List<SpaceMenuEntry> entries(BuildContext context, Space space) {
    final banner = space.getComponent<SpaceBannerComponent>()?.banner;
    final invitations = space.client.getComponent<InvitationComponent>();
    return [
      if (space.permissions.canInviteUser && invitations != null)
        SpaceMenuEntry("Invite people to space", Icons.person_add_alt_1,
            () => invite(context, space)),
      SpaceMenuEntry(
          "Space settings",
          Icons.settings,
          () => NavigationUtils.navigateTo(
              context, SpaceSettingsPage(space: space))),
      if (space.permissions.canEditChildren)
        SpaceMenuEntry("Create or add a room", Icons.add_circle,
            () => addRoom(context, space)),
      if (space.permissions.canEditChildren &&
          preferences.experimentManageSpaceRooms.value)
        SpaceMenuEntry(
            "Manage rooms",
            Icons.reorder,
            () => NavigationUtils.navigateTo(
                context, ManageSpaceRoomsPage(space))),
      if (banner != null)
        SpaceMenuEntry("View space banner", Icons.image_outlined,
            () => Lightbox.show(context, image: banner)),
      SpaceMenuEntry("Copy space link", Icons.link, () {
        Clipboard.setData(
            ClipboardData(text: "https://matrix.to/#/${space.identifier}"));
      }),
      SpaceMenuEntry("Leave space", Icons.logout, () => leave(context, space),
          dangerous: true),
    ];
  }

  /// Opens the menu under [anchor] (desktop) or as a bottom sheet (phone).
  static Future<void> show(BuildContext context, Space space,
          {required Rect anchor}) =>
      showEntryMenu(context, entries(context, space), anchor: anchor);

  static void invite(BuildContext context, Space space) {
    final invitation = space.client.getComponent<InvitationComponent>();
    if (invitation == null) return;
    AdaptiveDialog.show(context,
        builder: (context) => SendInvitationWidget(space.client, invitation,
            roomId: space.identifier, displayName: space.displayName),
        title: "Invite");
  }

  static Future<void> addRoom(BuildContext context, Space space) async {
    final room = await GetOrCreateRoom.show(
      space.client,
      context,
      currentSpace: space,
      joinRoom: false,
      showAllRoomTypes: true,
      existingRoomsRemoveWhere: (child) {
        if (child case SpaceChildSpace s) {
          if (s.child == space) return true;
        }
        return space.children.any((i) => i.id == child.id);
      },
    );
    if (room is SpaceChildRoom) await space.setSpaceChildRoom(room.child);
    if (room is SpaceChildSpace) await space.setSpaceChildSpace(room.child);
  }

  static Future<void> leave(BuildContext context, Space space) async {
    if (await AdaptiveDialog.confirmation(context,
            title: "Leave Space",
            prompt: "Are you sure you want to leave ${space.displayName}?",
            dangerous: true) ==
        true) {
      await space.client.leaveSpace(space);
    }
  }
}

class SpaceMenuEntry {
  const SpaceMenuEntry(this.label, this.icon, this.onSelected,
      {this.dangerous = false});
  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool dangerous;
}

/// Vommet: [items] as a popup under [anchor], the header the menu belongs to
/// (desktop), or a bottom sheet (phone), like Discord's server menu.
Future<void> showEntryMenu(BuildContext context, List<SpaceMenuEntry> items,
    {required Rect anchor}) async {
  final scheme = Theme.of(context).colorScheme;

  if (MediaQuery.of(context).mobile) {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              ListTile(
                leading: Icon(item.icon,
                    color: item.dangerous ? scheme.error : null),
                title: Text(item.label,
                    style:
                        TextStyle(color: item.dangerous ? scheme.error : null)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  item.onSelected();
                },
              ),
          ],
        ),
      ),
    );
    return;
  }

  // Like Discord's server menu: right under the header, as wide as its
  // column (inset a little), over the list below.
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final width = (anchor.width - 16).clamp(200.0, double.infinity);
  final chosen = await showMenu<SpaceMenuEntry>(
    context: context,
    position: RelativeRect.fromRect(
        Rect.fromLTWH(anchor.left + 8, anchor.bottom + 4, width, 0),
        Offset.zero & overlay.size),
    constraints: BoxConstraints.tightFor(width: width),
    items: [
      for (final item in items)
        PopupMenuItem(
          value: item,
          child: Row(
            spacing: 12,
            children: [
              Icon(item.icon,
                  size: 20, color: item.dangerous ? scheme.error : null),
              Text(item.label,
                  style:
                      TextStyle(color: item.dangerous ? scheme.error : null)),
            ],
          ),
        ),
    ],
  );
  chosen?.onSelected();
}

/// Vommet: the room menu opened from the room name on its banner.
class RoomMenu {
  static List<SpaceMenuEntry> entries(BuildContext context, Room room,
      {List<SpaceMenuEntry> extra = const []}) {
    final banner = room.getComponent<RoomBannerComponent>()?.banner;
    final invitations = room.client.getComponent<InvitationComponent>();
    return [
      if (room.permissions.canInviteUser && invitations != null)
        SpaceMenuEntry("Invite people to room", Icons.person_add_alt_1,
            () => invite(context, room)),
      // Room actions that didn't fit in the phone's actions row.
      ...extra,
      SpaceMenuEntry(
          "Room settings",
          Icons.settings,
          () => NavigationUtils.navigateTo(
              context, RoomSettingsPage(room: room))),
      if (banner != null)
        SpaceMenuEntry("View room banner", Icons.image_outlined,
            () => Lightbox.show(context, image: banner)),
      SpaceMenuEntry("Copy room link", Icons.link, () {
        Clipboard.setData(
            ClipboardData(text: "https://matrix.to/#/${room.identifier}"));
      }),
      SpaceMenuEntry("Leave room", Icons.logout, () => leave(context, room),
          dangerous: true),
    ];
  }

  static Future<void> show(BuildContext context, Room room,
          {required Rect anchor, List<SpaceMenuEntry> extra = const []}) =>
      showEntryMenu(context, entries(context, room, extra: extra),
          anchor: anchor);

  static void invite(BuildContext context, Room room) {
    final invitation = room.client.getComponent<InvitationComponent>();
    if (invitation == null) return;
    AdaptiveDialog.show(context,
        builder: (context) => SendInvitationWidget(room.client, invitation,
            roomId: room.identifier, displayName: room.displayName),
        title: "Invite");
  }

  static Future<void> leave(BuildContext context, Room room) async {
    if (await AdaptiveDialog.confirmation(context,
            title: "Leave Room",
            prompt: "Are you sure you want to leave ${room.displayName}?",
            dangerous: true) ==
        true) {
      await room.client.leaveRoom(room);
    }
  }
}
