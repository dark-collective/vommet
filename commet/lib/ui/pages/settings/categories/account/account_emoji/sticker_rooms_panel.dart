import 'dart:async';

import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/send_invitation.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/import_destinations.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Settings › Account › Emoticons section listing your sticker rooms
/// (private rooms that only hold packs; hidden from the room list), with
/// their packs, an invite button for sharing, and "New sticker room".
class StickerRoomsPanel extends StatefulWidget {
  const StickerRoomsPanel({required this.account, super.key});

  /// The account-level emoticon component.
  final EmoticonComponent account;

  @override
  State<StickerRoomsPanel> createState() => _StickerRoomsPanelState();
}

class _StickerRoomsPanelState extends State<StickerRoomsPanel> {
  StreamSubscription? accountSub;
  StreamSubscription? roomsSub;
  List<EmoticonComponent> rooms = [];
  bool creating = false;

  String get headerStickerRooms => Intl.message("Sticker rooms",
      name: "headerStickerRooms",
      desc: "Header of the settings section listing the user's sticker rooms");

  String get promptNewStickerRoom => Intl.message("New sticker room",
      name: "promptNewStickerRoom", desc: "Button that creates a sticker room");

  String get promptShareStickerRoom => Intl.message("Invite",
      name: "promptShareStickerRoom",
      desc: "Button that invites someone to a sticker room to share its packs");

  @override
  void initState() {
    super.initState();
    accountSub = widget.account.onStateChanged.listen((_) => refresh());
    roomsSub = widget.account.client.onSync.listen((_) => refresh());
    rooms = widget.account.stickerRoomComponents;
  }

  void refresh() {
    final next = widget.account.stickerRoomComponents;
    if (!mounted) return;
    if (next.length == rooms.length && next.every((c) => rooms.contains(c))) {
      return;
    }
    setState(() => rooms = next);
  }

  @override
  void dispose() {
    accountSub?.cancel();
    roomsSub?.cancel();
    super.dispose();
  }

  Future<void> createRoom() async {
    final controller = TextEditingController(text: "Sticker packs");
    final name = await AdaptiveDialog.show<String>(context,
        title: promptNewStickerRoom,
        builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tiamat.TextInput(
                    controller: controller, label: "Name", maxLines: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: tiamat.Text.labelLow(
                      EmoticonImportDestinations.explainStickerRooms),
                ),
                tiamat.Button(
                  text: promptNewStickerRoom,
                  onTap: () => Navigator.pop(context, controller.text.trim()),
                ),
              ],
            ));
    if (name == null || name.isEmpty) return;

    setState(() => creating = true);
    try {
      await widget.account.createStickerRoom(name);
    } catch (e) {
      Log.e("Could not create sticker room: $e");
    }
    if (!mounted) return;
    setState(() => creating = false);
    refresh();
  }

  void invite(EmoticonComponent room) {
    if (room is! RoomEmoticonComponent) return;
    final invitation =
        widget.account.client.getComponent<InvitationComponent>();
    if (invitation == null) return;
    AdaptiveDialog.show(context,
        builder: (context) => SendInvitationWidget(
            widget.account.client, invitation,
            roomId: room.room.identifier, displayName: room.room.displayName));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: tiamat.Panel(
        header: headerStickerRooms,
        mode: tiamat.TileType.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: tiamat.Text.labelLow(
                  EmoticonImportDestinations.explainStickerRooms),
            ),
            for (final c in rooms) roomSection(c),
            Align(
              alignment: Alignment.topRight,
              child: tiamat.Button.secondary(
                text: promptNewStickerRoom,
                isLoading: creating,
                onTap: creating ? null : createRoom,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget roomSection(EmoticonComponent c) {
    final name = c is RoomEmoticonComponent ? c.room.displayName : "";
    final canInvite =
        c is RoomEmoticonComponent && c.room.permissions.canInviteUser;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: tiamat.Text.labelEmphasised(name)),
              if (canInvite)
                tiamat.Button.secondary(
                    text: promptShareStickerRoom, onTap: () => invite(c)),
            ],
          ),
          RoomEmojiPackSettingsView(
            key: ValueKey("sticker_room_${c.hashCode}"),
            component: c,
            editable: c.canCreatePack,
          ),
        ],
      ),
    );
  }
}
