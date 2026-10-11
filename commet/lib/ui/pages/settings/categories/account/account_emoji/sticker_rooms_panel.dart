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

  String get promptNewPackInRoom => Intl.message("New pack",
      name: "promptNewPackInStickerRoom",
      desc: "Tooltip for creating an empty pack in a sticker room");

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

  String get explainStickerRoomsShort => Intl.message(
      "An account holds one personal pack. Make more in sticker rooms: private "
      "rooms that only hold packs, kept out of your room list. Invite friends "
      "to share a room's packs. Other apps show sticker rooms as ordinary rooms.",
      name: "explainStickerRoomsShort",
      desc: "Short explanation at the top of the sticker rooms settings");

  String get promptRenameStickerRoom => Intl.message("Rename",
      name: "promptRenameStickerRoom",
      desc: "Tooltip/title for renaming a sticker room");

  String get labelNoPacksYet => Intl.message("No packs yet",
      name: "labelStickerRoomNoPacks",
      desc: "Shown in a sticker room that has no packs");

  Future<void> rename(RoomEmoticonComponent c) async {
    final controller = TextEditingController(text: c.room.displayName);
    final name = await AdaptiveDialog.show<String>(context,
        title: promptRenameStickerRoom,
        builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tiamat.TextInput(
                    controller: controller, label: "Name", maxLines: 1),
                const SizedBox(height: 8),
                tiamat.Button(
                  text: promptRenameStickerRoom,
                  onTap: () => Navigator.pop(context, controller.text.trim()),
                ),
              ],
            ));
    if (name == null || name.isEmpty || name == c.room.displayName) return;
    try {
      await c.room.setDisplayName(name);
    } catch (e) {
      Log.e("Could not rename sticker room: $e");
    }
    if (mounted) setState(() {});
  }

  void newPack(EmoticonComponent c) {
    AdaptiveDialog.show(context,
        builder: (context) => EmoticonCreator(
              createPack: true,
              creatingNew: true,
              onCreate: (name, usage, newImageData) async {
                await c.createEmoticonPack(name, newImageData);
                return true;
              },
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: tiamat.Panel(
        mode: tiamat.TileType.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: tiamat.Text.labelEmphasised(headerStickerRooms)),
                tiamat.Button.secondary(
                  text: promptNewStickerRoom,
                  isLoading: creating,
                  onTap: creating ? null : createRoom,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
              child: tiamat.Text.labelLow(explainStickerRoomsShort),
            ),
            for (final c in rooms) roomCard(c),
          ],
        ),
      ),
    );
  }

  Widget action(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: tiamat.IconButton(icon: icon, size: 20, onPressed: onPressed),
    );
  }

  Widget roomCard(EmoticonComponent c) {
    final room = c is RoomEmoticonComponent ? c : null;
    final name = room?.room.displayName ?? "";
    final canInvite = room?.room.permissions.canInviteUser == true;
    final canRename = room?.room.permissions.canEditName == true;
    final canEdit = c.canCreatePack;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: tiamat.Panel(
        mode: tiamat.TileType.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sticky_note_2_outlined, size: 20),
                const SizedBox(width: 8),
                Flexible(
                    child: tiamat.Text.labelEmphasised(name,
                        overflow: TextOverflow.ellipsis)),
                if (canRename)
                  action(
                      Icons.edit, promptRenameStickerRoom, () => rename(room!)),
                const Spacer(),
                if (canEdit)
                  action(
                      Icons.download,
                      EmoticonImportDestinations.titleImportPack,
                      () => EmoticonImportDestinations.show(context, c)),
                if (canEdit)
                  action(Icons.add, promptNewPackInRoom, () => newPack(c)),
                if (canInvite)
                  action(Icons.person_add_alt, promptShareStickerRoom,
                      () => invite(c)),
              ],
            ),
            if (c.ownedPacks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 0, 4),
                child: tiamat.Text.labelLow(labelNoPacksYet),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                child: RoomEmojiPackSettingsView(
                  key: ValueKey("sticker_room_${c.hashCode}"),
                  component: c,
                  editable: canEdit,
                  showCreateButtons: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
