import 'package:commet/client/client.dart';
import 'package:commet/ui/pages/settings/categories/room/advanced/replace_room_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: room settings › Advanced: the room's version, and replacing the
/// room (an upgrade, or a move to a room that already exists).
class RoomAdvancedSettingsPage extends StatefulWidget {
  const RoomAdvancedSettingsPage(this.room, {this.contextSpace, super.key});

  final Room room;
  final Space? contextSpace;

  @override
  State<RoomAdvancedSettingsPage> createState() =>
      _RoomAdvancedSettingsPageState();
}

class _RoomAdvancedSettingsPageState extends State<RoomAdvancedSettingsPage> {
  late final Future<RoomVersionOptions?> versions;

  String get labelRoomVersion => Intl.message("Room version",
      name: "labelRoomVersion",
      desc: "Header of the room settings panel showing the room's version");

  String roomIsOnVersion(String version) =>
      Intl.message("This room is on version $version.",
          args: [version],
          name: "roomIsOnVersion",
          desc: "The room's current room version");

  String serverNewestStableRoomVersion(String version) =>
      Intl.message("Your server's newest stable version is $version.",
          args: [version],
          name: "serverNewestStableRoomVersion",
          desc: "The newest stable room version the user's server offers");

  String get labelReplaceThisRoom => Intl.message("Replace this room",
      name: "labelReplaceThisRoom",
      desc: "Header of the room settings panel for replacing the room");

  String get replaceThisRoomExplanation => Intl.message(
      "Close this room and point everyone to a replacement: an upgraded copy "
      "on a newer room version, or a room that already exists. Nobody can "
      "post here afterwards; older messages stay readable.",
      name: "replaceThisRoomExplanation",
      desc: "Explains what replacing a room does");

  String get roomAlreadyReplaced =>
      Intl.message("This room has already been replaced.",
          name: "roomAlreadyReplaced",
          desc: "Shown instead of the Replace room button in a replaced room");

  String get promptReplaceRoomEllipsis => Intl.message("Replace room…",
      name: "promptReplaceRoomEllipsis",
      desc: "Button that opens the Replace room dialog");

  @override
  void initState() {
    versions = loadVersions();
    super.initState();
  }

  Future<RoomVersionOptions?> loadVersions() async {
    try {
      return await widget.room.replacement?.getVersionOptions();
    } catch (e) {
      // The room version line just goes without the server's newest.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final replacement = widget.room.replacement;
    if (replacement == null) return const SizedBox.shrink();

    return StreamBuilder(
        stream: widget.room.onUpdate,
        builder: (context, _) {
          return Column(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              versionPanel(context, replacement),
              replacePanel(context, replacement),
            ],
          );
        });
  }

  Widget versionPanel(BuildContext context, RoomReplacement replacement) {
    final theme = Theme.of(context);
    final version = replacement.roomVersion ?? "1";
    return tiamat.Panel(
      header: labelRoomVersion,
      mode: tiamat.TileType.surfaceContainerLow,
      mainAxisSize: MainAxisSize.min,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(roomIsOnVersion(version), style: theme.textTheme.bodyMedium),
            FutureBuilder(
                future: versions,
                builder: (context, snapshot) {
                  final newest = snapshot.data?.newestStable;
                  if (newest == null) return const SizedBox.shrink();
                  return Text(serverNewestStableRoomVersion(newest),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant));
                }),
          ],
        ),
      ),
    );
  }

  Widget replacePanel(BuildContext context, RoomReplacement replacement) {
    final theme = Theme.of(context);
    final replaced = replacement.tombstone != null;
    return tiamat.Panel(
      header: labelReplaceThisRoom,
      mode: tiamat.TileType.surfaceContainerLow,
      mainAxisSize: MainAxisSize.min,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(replaced ? roomAlreadyReplaced : replaceThisRoomExplanation,
                style: theme.textTheme.bodyMedium),
            if (!replaced) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 40,
                  width: 220,
                  child: tiamat.Button.danger(
                    text: promptReplaceRoomEllipsis,
                    onTap: () => ReplaceRoomDialog.show(context, widget.room,
                        versions: versions),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
