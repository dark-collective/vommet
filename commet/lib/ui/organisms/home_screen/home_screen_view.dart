import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/molecules/alert_view.dart';
import 'package:commet/ui/molecules/invitation_display.dart';
import 'package:commet/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:flutter/material.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HomeScreenView extends StatelessWidget {
  final ClientManager clientManager;
  final List<Room>? rooms;
  final List<Room>? recentActivity;
  final List<Invitation>? invitations;
  final Function(Room room)? onRoomClicked;
  final Future<void> Function(Invitation invite)? acceptInvite;
  final Future<void> Function(Invitation invite)? rejectInvite;
  final Future<void> Function(Client client, String address)? joinRoom;
  final Future<void> Function(Client client, CreateRoomArgs args)? createRoom;

  /// Vommet: shown above the sections, inside the same scroll view.
  final Widget? header;

  const HomeScreenView(
      {super.key,
      required this.clientManager,
      this.header,
      this.rooms,
      this.recentActivity,
      this.onRoomClicked,
      this.acceptInvite,
      this.rejectInvite,
      this.joinRoom,
      this.createRoom,
      this.invitations});

  String get labelHomeRecentActivity => Intl.message("Recent Activity",
      name: "labelHomeRecentActivity",
      desc: "Short label for header of recent room activity");

  String get labelHomeAlerts => Intl.message("Alerts",
      name: "labelHomeAlerts", desc: "Short label for header of alerts");

  static String get labelHomeRoomsList => Intl.message("Rooms",
      name: "labelHomeRoomsList", desc: "Short label for header of rooms list");

  String get labelHomeInvitations => Intl.message("Invitations",
      name: "labelHomeInvitations",
      desc: "Short label for header of invitations list");

  // Vommet: a scroll view of slivers instead of a Column of shrink-wrapped
  // lists. Shrink-wrapping built a RoomPanel for every room at startup, and
  // each one looked up its last sender (a "Get user" database query): ~300
  // queued queries on a 300-room account. Now only the rows on screen are
  // built. The small sections (alerts, invitations, recent activity) stay
  // as they were.
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverMainAxisGroup(
            slivers: [
              if (header != null) SliverToBoxAdapter(child: header),
              if (clientManager.alertManager.alerts.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                    child: alerts(),
                  ),
                ),
              if (invitations?.isNotEmpty == true)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                    child: invitationsList(),
                  ),
                ),
              if (recentActivity?.isNotEmpty == true)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                    child: recentRooms(),
                  ),
                ),
              roomsListSliver(context),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget alerts() {
    return Panel(
        mode: TileType.surfaceContainerLow,
        header: labelHomeAlerts,
        child: ImplicitlyAnimatedList(
          padding: EdgeInsetsGeometry.zero,
          shrinkWrap: true,
          itemData: clientManager.alertManager.alerts,
          initialAnimation: false,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, alert) {
            return AlertView(alert);
          },
        ));
  }

  Widget recentRooms() {
    return Panel(
        mode: TileType.surface,
        header: labelHomeRecentActivity,
        child: ImplicitlyAnimatedList(
          shrinkWrap: true,
          padding: EdgeInsetsGeometry.zero,
          itemData: recentActivity!,
          initialAnimation: false,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, room) {
            return Padding(
              padding: EdgeInsetsGeometry.fromLTRB(0, 2, 0, 2),
              child: RoomPanel(
                  shouldShowAvatarForRoom: (room) =>
                      clientManager.clients
                          .where((i) => i.hasRoom(room.identifier))
                          .length >
                      1,
                  key: ValueKey("recent-activity-room_${room.localId}"),
                  room),
            );
          },
        ));
  }

  /// The Rooms section, drawn like a [Panel] but built lazily.
  Widget roomsListSliver(BuildContext context) {
    final shadows = Theme.of(context).extension<ShadowSettings>();
    return DecoratedSliver(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surface,
          boxShadow: shadows?.shadows),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                  child: tiamat.Text.labelLow(
                    labelHomeRoomsList,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 4, 0, 0),
                  child: tiamat.Seperator(padding: 0),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            sliver: SliverImplicitlyAnimatedList(
              initialAnimation: false,
              itemData: rooms!,
              itemBuilder: (context, room) {
                return Padding(
                  padding: EdgeInsetsGeometry.fromLTRB(0, 2, 0, 2),
                  child: RoomPanel(room,
                      shouldShowAvatarForRoom: (room) =>
                          clientManager.clients
                              .where((i) => i.hasRoom(room.identifier))
                              .length >
                          1,
                      key: ValueKey("homescreen-room_${room.localId}")),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: tiamat.CircleButton(
                  radius: BuildConfig.MOBILE ? 24 : 16,
                  icon: Icons.add,
                  onPressed: () => addRoomDialog(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget invitationsList() {
    return Panel(
        mode: TileType.surfaceContainer,
        header: labelHomeInvitations,
        child: ImplicitlyAnimatedList(
          padding: EdgeInsetsGeometry.zero,
          physics: const NeverScrollableScrollPhysics(),
          initialAnimation: false,
          shrinkWrap: true,
          itemData: invitations!,
          itemBuilder: (context, invitation) {
            return InvitationDisplay(
              invitation,
              acceptInvitation: acceptInvite,
              rejectInvitation: rejectInvite,
            );
          },
        ));
  }

  void addRoomDialog(BuildContext context) {
    GetOrCreateRoom.show(null, context,
        pickExisting: false, showAllRoomTypes: true);
  }
}
