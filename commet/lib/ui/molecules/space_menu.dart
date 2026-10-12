import 'package:commet/debug/log.dart';
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
import 'package:commet/ui/organisms/space_join_picker/space_join_picker.dart';
import 'package:commet/ui/organisms/space_join_picker/leave_space_dialog.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/space_list.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
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
      // Vommet: join rooms of the space you skipped when joining it.
      SpaceMenuEntry("Browse rooms", Icons.travel_explore,
          () => SpaceJoinPicker.browse(context, space)),
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
      // Vommet: mark every room in the space (and its subspaces) as read
      // (tester request; Commet upstream issue 517).
      if (space.roomsWithChildren.any((r) => r.notificationCount > 0))
        SpaceMenuEntry("Mark space as read", Icons.mark_chat_read_outlined,
            () => markAsRead(space)),
      SpaceMenuEntry("Copy space link", Icons.link, () {
        Clipboard.setData(
            ClipboardData(text: "https://matrix.to/#/${space.identifier}"));
      }),
      SpaceMenuEntry("Leave space", Icons.logout, () => leave(context, space),
          dangerous: true),
    ];
  }

  static Future<void> markAsRead(Space space) async {
    final unread =
        space.roomsWithChildren.where((r) => r.notificationCount > 0).toList();
    await Future.wait(unread.map((r) => r.markAsRead().catchError(
        (Object e, StackTrace s) =>
            Log.onError(e, s, content: "Couldn't mark a room as read"))));
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

  /// Vommet: asks (offering to leave the rooms you're in under it too),
  /// then leaves. Returns whether the user confirmed.
  static Future<bool> leave(BuildContext context, Space space,
          {VoidCallback? onConfirmed}) =>
      LeaveSpaceDialog.leave(context, space, onConfirmed: onConfirmed);
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
///
/// [title], if given, heads the menu in full (a long room name is cut off
/// where the menu was opened).
Future<void> showEntryMenu(BuildContext context, List<SpaceMenuEntry> items,
    {required Rect anchor, String? title}) async {
  final scheme = Theme.of(context).colorScheme;

  if (MediaQuery.of(context).mobile) {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
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
      if (title != null)
        PopupMenuItem<SpaceMenuEntry>(
          enabled: false,
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: scheme.onSurface)),
        ),
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
          anchor: anchor, title: room.displayName);

  static void invite(BuildContext context, Room room) {
    final invitation = room.client.getComponent<InvitationComponent>();
    if (invitation == null) return;
    AdaptiveDialog.show(context,
        builder: (context) => SendInvitationWidget(room.client, invitation,
            roomId: room.identifier, displayName: room.displayName),
        title: "Invite");
  }

  /// Vommet: "Leave '<name>'"; invite-only rooms also say you can't get
  /// back in without an invite. Returns whether the user confirmed.
  static Future<bool> leave(BuildContext context, Room room,
      {VoidCallback? onConfirmed}) async {
    final inviteOnly = room.visibility is RoomVisibilityPrivate;
    if (await AdaptiveDialog.confirmation(context,
            title: "Leave '${room.displayName}'",
            prompt: "Are you sure you want to leave ${room.displayName}?"
                "${inviteOnly ? " You won't be able to rejoin unless you're invited again." : ""}",
            confirmationText: "Leave Room",
            cancelText: "Cancel",
            dangerous: true) !=
        true) {
      return false;
    }
    onConfirmed?.call();
    await room.client.leaveRoom(room);
    return true;
  }
}

/// Vommet: a divider line in a right-click / long-press menu.
tiamat.ContextMenuItem menuDivider() => tiamat.ContextMenuItem(
      text: "",
      customBuilder: (context, onClicked, {closeMenu}) => Divider(
          height: 9,
          indent: 12,
          endIndent: 12,
          color: Theme.of(context).colorScheme.outlineVariant),
    );

/// Vommet: a menu item in the theme's error colour (Leave Room/Space), red
/// on the phone's long-press sheet too.
tiamat.ContextMenuItem dangerMenuItem(
    String text, IconData icon, VoidCallback onPressed) {
  return tiamat.ContextMenuItem(
    text: text,
    icon: icon,
    onPressed: onPressed,
    customBuilder: (context, onClicked, {closeMenu}) {
      final color = Theme.of(context).colorScheme.error;
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: InkWell(
          onTap: onClicked,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                tiamat.Text(text,
                    type: tiamat.TextType.body, maxLines: 1, color: color),
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Vommet: Copy Link, Room Settings and, last and in red, Leave Room: the
/// end of a room's menu in the room list.
List<tiamat.ContextMenuItem> roomListMenuTail(BuildContext context, Room room) {
  return [
    menuDivider(),
    tiamat.ContextMenuItem(
        text: "Copy Link",
        icon: Icons.link,
        onPressed: () => Clipboard.setData(
            ClipboardData(text: "https://matrix.to/#/${room.identifier}"))),
    tiamat.ContextMenuItem(
        text: "Room Settings",
        icon: Icons.settings,
        onPressed: () =>
            NavigationUtils.navigateTo(context, RoomSettingsPage(room: room))),
    menuDivider(),
    dangerMenuItem(
        "Leave Room", Icons.logout, () => RoomMenu.leave(context, room)),
  ];
}

/// Vommet: right-click / long-press menu for a subspace's header in the
/// room list: Mark Space as Read, Collapse/Expand, Invite People, Copy Link,
/// Space Settings, then [items] (e.g. "Remove from <parent>"), and Leave
/// Space last, in red.
class SubspaceHeaderMenu extends StatefulWidget {
  const SubspaceHeaderMenu(
      {required this.space,
      required this.items,
      required this.child,
      super.key});

  final Space space;
  final List<tiamat.ContextMenuItem> items;
  final Widget child;

  @override
  State<SubspaceHeaderMenu> createState() => _SubspaceHeaderMenuState();
}

class _SubspaceHeaderMenuState extends State<SubspaceHeaderMenu> {
  final GlobalKey headerKey = GlobalKey();

  /// The header's own expander isn't ours to drive: tap it, as the user
  /// would (the first tappable thing in it is the header row).
  void toggleExpanded() {
    final root = headerKey.currentContext as Element?;
    if (root == null) return;
    VoidCallback? tap;
    void visit(Element e) {
      if (tap != null) return;
      final w = e.widget;
      if (w is InkWell && w.onTap != null) {
        tap = w.onTap;
        return;
      }
      if (w is GestureDetector && w.onTap != null) {
        tap = w.onTap;
        return;
      }
      e.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    tap?.call();
  }

  /// Open while the subspace's room list is in the tree.
  bool get isExpanded {
    final root = headerKey.currentContext as Element?;
    if (root == null) return true;
    var found = false;
    void visit(Element e) {
      if (found) return;
      final w = e.widget;
      if (w is SpaceList && w.space == widget.space) {
        found = true;
        return;
      }
      e.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    final invitations = space.client.getComponent<InvitationComponent>();
    return AdaptiveContextMenu(
      items: [
        if (space.roomsWithChildren.any((r) => r.notificationCount > 0))
          tiamat.ContextMenuItem(
              text: "Mark Space as Read",
              icon: Icons.mark_chat_read_outlined,
              onPressed: () => SpaceMenu.markAsRead(space)),
        tiamat.ContextMenuItem(
          text: "Collapse",
          onPressed: toggleExpanded,
          // Built when the menu opens, so it says what a click will do.
          customBuilder: (context, onClicked, {closeMenu}) {
            final open = isExpanded;
            return tiamat.ContextMenuItem(
              text: open ? "Collapse" : "Expand",
              icon: open ? Icons.unfold_less : Icons.unfold_more,
            ).build(context, onClicked, closeMenu: closeMenu);
          },
        ),
        menuDivider(),
        if (space.permissions.canInviteUser && invitations != null)
          tiamat.ContextMenuItem(
              text: "Invite People",
              icon: Icons.person_add_alt_1,
              onPressed: () => SpaceMenu.invite(context, space)),
        tiamat.ContextMenuItem(
            text: "Copy Link",
            icon: Icons.link,
            onPressed: () => Clipboard.setData(ClipboardData(
                text: "https://matrix.to/#/${space.identifier}"))),
        tiamat.ContextMenuItem(
            text: "Space Settings",
            icon: Icons.settings,
            onPressed: () => NavigationUtils.navigateTo(
                context, SpaceSettingsPage(space: space))),
        ...widget.items,
        menuDivider(),
        dangerMenuItem(
            "Leave Space", Icons.logout, () => SpaceMenu.leave(context, space)),
      ],
      child: KeyedSubtree(key: headerKey, child: widget.child),
    );
  }
}
