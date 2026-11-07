import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/pages/room_info/dm_cards.dart';
import 'package:commet/ui/pages/room_info/room_info_page.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet (New room info page), desktop: the title opens Room info as a
/// dialog, Slack-style, with tabs About · Members · Shared · Settings. Rows
/// open their pages inside the dialog; the side panel is unchanged.
Future<void> showRoomInfoDialog(BuildContext context, Room room,
    {Space? contextSpace,
    VoidCallback? onLeaveRoom,
    RoomInfoSection section = RoomInfoSection.about}) {
  return showDialog(
    context: context,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: min(760, size.width - 48),
          height: min(760, size.height - 48),
          child: RoomInfoDialog(
            room: room,
            contextSpace: contextSpace,
            onLeaveRoom: onLeaveRoom,
            initialTab: section == RoomInfoSection.settings ? 3 : 0,
          ),
        ),
      );
    },
  );
}

class RoomInfoDialog extends StatelessWidget {
  const RoomInfoDialog({
    required this.room,
    this.contextSpace,
    this.onLeaveRoom,
    this.initialTab = 0,
    super.key,
  });

  final Room room;
  final Space? contextSpace;
  final VoidCallback? onLeaveRoom;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    // Pages opened from rows stay inside the dialog.
    return ScaffoldMessenger(
      child: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (context) => _RoomInfoTabs(
            room: room,
            contextSpace: contextSpace,
            onLeaveRoom: onLeaveRoom,
            initialTab: initialTab,
          ),
        ),
      ),
    );
  }
}

class _RoomInfoTabs extends StatelessWidget {
  const _RoomInfoTabs({
    required this.room,
    required this.contextSpace,
    required this.onLeaveRoom,
    required this.initialTab,
  });

  final Room room;
  final Space? contextSpace;
  final VoidCallback? onLeaveRoom;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget scroll(List<Widget> children) => SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children),
        );

    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: RoomInfoListener(
          room: room,
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                child: Row(
                  children: [
                    tiamat.Avatar(
                      radius: 18,
                      image: room.avatar,
                      placeholderText: room.displayName,
                      placeholderColor: room.defaultColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(room.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                        tooltip: "Share room link",
                        icon: const Icon(Icons.ios_share),
                        onPressed: () =>
                            RoomInfoActions.shareLink(context, room)),
                    if (room.permissions.canEditAppearance)
                      IconButton(
                          tooltip: "Edit room profile",
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () =>
                              RoomInfoActions.editProfile(context, room)),
                    IconButton(
                        key: const ValueKey("room-info-dialog-close"),
                        tooltip: "Close",
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop()),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  const Tab(text: "About"),
                  Tab(text: roomInfoIsDirectChat(room) ? "Person" : "Members"),
                  const Tab(text: "Shared"),
                  const Tab(text: "Settings"),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    scroll([
                      RoomInfoHeader(room, contextSpace: contextSpace),
                      DmShapeCard(room),
                      RoomInfoQuickActions(room),
                      RoomInfoFooter(room, onLeaveRoom: onLeaveRoom),
                    ]),
                    roomInfoIsDirectChat(room)
                        ? scroll([RoomInfoMembers(room)])
                        : RoomMemberList(room,
                            listPadding:
                                const EdgeInsets.symmetric(horizontal: 8)),
                    scroll([RoomInfoShared(room)]),
                    scroll([
                      RoomInfoForYou(room, contextSpace: contextSpace),
                      RoomInfoRoomSettings(room, contextSpace: contextSpace),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
