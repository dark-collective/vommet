import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/ui/pages/settings/categories/room/advanced/replace_room_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: room settings › Advanced: the room's ID and version for everyone;
/// for those who may, the server's newest version and replacing the room
/// (an upgrade, or a move to a room that already exists).
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

  @override
  void initState() {
    versions = loadVersions();
    super.initState();
  }

  Future<RoomVersionOptions?> loadVersions() async {
    // Only those who can replace the room see the server's newest version.
    if (widget.room.replacement?.canReplace != true) return null;
    try {
      return await widget.room.replacement?.getVersionOptions();
    } catch (e) {
      // The room version line just goes without the server's newest.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: widget.room.onUpdate,
        builder: (context, _) {
          final replacement = widget.room.replacement;
          final canReplace = replacement?.canReplace == true;
          return RoomAdvancedSettingsView(
            roomId: widget.room.identifier,
            roomVersion: replacement?.roomVersion,
            versions: canReplace ? versions : null,
            canReplace: canReplace,
            replaced: replacement?.tombstone != null,
            onReplace: () => ReplaceRoomDialog.show(context, widget.room,
                versions: versions),
          );
        });
  }
}

/// The Advanced tab's content, fed plain values.
class RoomAdvancedSettingsView extends StatelessWidget {
  const RoomAdvancedSettingsView({
    required this.roomId,
    required this.roomVersion,
    this.versions,
    this.canReplace = false,
    this.replaced = false,
    this.onReplace,
    super.key,
  });

  final String roomId;
  final String? roomVersion;

  /// The server's room versions, for the "newest stable" line.
  final Future<RoomVersionOptions?>? versions;
  final bool canReplace;
  final bool replaced;
  final void Function()? onReplace;

  static String get labelReplaceThisRoom => Intl.message("Replace this room",
      name: "labelReplaceThisRoom",
      desc: "Header of the room settings panel for replacing the room");

  static String get replaceThisRoomExplanation => Intl.message(
      "Close this room and point everyone to a replacement: an upgraded copy "
      "on a newer room version, or a room that already exists. Nobody can "
      "post here afterwards; older messages stay readable.",
      name: "replaceThisRoomExplanation",
      desc: "Explains what replacing a room does");

  static String get roomAlreadyReplaced =>
      Intl.message("This room has already been replaced.",
          name: "roomAlreadyReplaced",
          desc: "Shown instead of the Replace room button in a replaced room");

  static String get promptReplaceRoomEllipsis => Intl.message("Replace room…",
      name: "promptReplaceRoomEllipsis",
      desc: "Button that opens the Replace room dialog");

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoomIdVersionPanel(
            roomId: roomId, roomVersion: roomVersion, versions: versions),
        if (canReplace) replacePanel(context),
      ],
    );
  }

  Widget replacePanel(BuildContext context) {
    final theme = Theme.of(context);
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
                    onTap: onReplace,
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

/// The "Room information" panel: the copyable room ID and the version (with
/// the server's newest stable one when [versions] is given). Spaces use it
/// too ([isSpace]).
class RoomIdVersionPanel extends StatefulWidget {
  const RoomIdVersionPanel({
    required this.roomId,
    required this.roomVersion,
    this.versions,
    this.isSpace = false,
    this.note,
    super.key,
  });

  final String roomId;
  final String? roomVersion;
  final Future<RoomVersionOptions?>? versions;
  final bool isSpace;

  /// An extra line under the version (e.g. why a space can't be upgraded
  /// here).
  final String? note;

  static String get labelRoomInformation => Intl.message("Room information",
      name: "labelRoomInformation",
      desc: "Header of the room settings panel with the room ID and version");

  static String get labelSpaceInformation => Intl.message("Space information",
      name: "labelSpaceInformation",
      desc: "Header of the space settings panel with the space ID and version");

  static String get labelInternalRoomId => Intl.message("Internal room ID",
      name: "labelInternalRoomId",
      desc: "Label above a room's ID (!abc:server) in its settings");

  static String get labelInternalSpaceId => Intl.message("Internal space ID",
      name: "labelInternalSpaceId",
      desc: "Label above a space's ID (!abc:server) in its settings");

  static String get labelRoomVersion => Intl.message("Room version",
      name: "labelRoomVersion",
      desc: "Label for the room's version in its settings");

  static String roomIsOnVersion(String version) =>
      Intl.message("This room is on version $version.",
          args: [version],
          name: "roomIsOnVersion",
          desc: "The room's current room version");

  static String spaceIsOnVersion(String version) =>
      Intl.message("This space is on version $version.",
          args: [version],
          name: "spaceIsOnVersion",
          desc: "The space's current room version");

  static String serverNewestStableRoomVersion(String version) =>
      Intl.message("Your server's newest stable version is $version.",
          args: [version],
          name: "serverNewestStableRoomVersion",
          desc: "The newest stable room version the user's server offers");

  @override
  State<RoomIdVersionPanel> createState() => _RoomIdVersionPanelState();
}

class _RoomIdVersionPanelState extends State<RoomIdVersionPanel> {
  bool copied = false;
  Timer? copiedTimer;

  @override
  void dispose() {
    copiedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = widget.roomVersion ?? "1";
    final low = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return tiamat.Panel(
      header: widget.isSpace
          ? RoomIdVersionPanel.labelSpaceInformation
          : RoomIdVersionPanel.labelRoomInformation,
      mode: tiamat.TileType.surfaceContainerLow,
      mainAxisSize: MainAxisSize.min,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                widget.isSpace
                    ? RoomIdVersionPanel.labelInternalSpaceId
                    : RoomIdVersionPanel.labelInternalRoomId,
                style: low),
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: SelectableText(widget.roomId,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontFamily: "Code")),
                ),
                const SizedBox(width: 4),
                tiamat.Tooltip(
                  text: copied
                      ? CommonStrings.promptCopyComplete
                      : CommonStrings.promptCopy,
                  child: tiamat.IconButton(
                    icon: copied ? Icons.check : Icons.copy,
                    size: 16,
                    iconColor: theme.colorScheme.onSurfaceVariant,
                    onPressed: copy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(RoomIdVersionPanel.labelRoomVersion, style: low),
            const SizedBox(height: 2),
            Text(
                widget.isSpace
                    ? RoomIdVersionPanel.spaceIsOnVersion(version)
                    : RoomIdVersionPanel.roomIsOnVersion(version),
                style: theme.textTheme.bodyMedium),
            if (widget.versions != null)
              FutureBuilder(
                  future: widget.versions,
                  builder: (context, snapshot) {
                    final newest = snapshot.data?.newestStable;
                    if (newest == null) return const SizedBox.shrink();
                    return Text(
                        RoomIdVersionPanel.serverNewestStableRoomVersion(
                            newest),
                        style: low);
                  }),
            if (widget.note != null) ...[
              const SizedBox(height: 8),
              Text(widget.note!, style: low),
            ],
          ],
        ),
      ),
    );
  }

  void copy() {
    Clipboard.setData(ClipboardData(text: widget.roomId));
    copiedTimer?.cancel();
    setState(() => copied = true);
    copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => copied = false);
    });
  }
}
