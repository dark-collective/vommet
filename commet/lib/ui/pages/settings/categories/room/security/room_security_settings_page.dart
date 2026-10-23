import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/shared_history_setting.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/get_or_create_room/room_creator.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/client/matrix/matrix_join_rules.dart';
import 'package:commet/client/matrix/matrix_room.dart' as vommet_access;
import 'package:commet/ui/pages/settings/categories/room/security/room_access_settings.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class RoomSecuritySettingsPage extends StatefulWidget {
  const RoomSecuritySettingsPage({
    required this.room,
    this.contextSpace,
    this.showEncryptionToggle = true,
    super.key,
  });
  final Room room;
  final Space? contextSpace;
  final bool showEncryptionToggle;

  @override
  State<RoomSecuritySettingsPage> createState() =>
      _RoomSecuritySettingsPageState();
}

class _RoomSecuritySettingsPageState extends State<RoomSecuritySettingsPage> {
  late bool isE2EEEnabled;
  late RoomVisibility visibility;

  // Vommet: Matrix access settings (history visibility, guest access).
  matrix.Room? get matrixRoom => switch (widget.room) {
        vommet_access.MatrixRoom r => r.matrixRoom,
        _ => null,
      };
  bool get isSpace => matrixRoom?.isSpace ?? false;
  matrix.HistoryVisibility? historyVisibility;
  bool guestCanJoin = false;

  String get labelRoomVisibilityHeader => Intl.message("Room Visibility",
      name: "labelRoomVisibilityHeader",
      desc: "Header for the room visibility (who can join) setting");

  String get labelSpaceVisibilityHeader => Intl.message("Space Visibility",
      name: "labelSpaceVisibilityHeader",
      desc: "Header for the space visibility (who can join) setting");

  String get promptEnableEncryptionRoomSettings =>
      Intl.message("Enable Encryption",
          name: "promptEnableEncryptionRoomSettings",
          desc: "Short prompt to enable encryption for a room");

  String get encryptionCannotBeDisabledExplanationRoomSettings =>
      Intl.message("If enabled, encryption cannot be disabled later",
          name: "encryptionCannotBeDisabledExplanationRoomSettings",
          desc: "Explains that encryption cannot be disabled once enabled");

  @override
  void initState() {
    isE2EEEnabled = widget.room.isE2EE;
    visibility = widget.room.visibility;
    historyVisibility = matrixRoom?.historyVisibility;
    guestCanJoin = matrixRoom?.guestAccess == matrix.GuestAccess.canJoin;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        if (widget.room.client.supportsE2EE && widget.showEncryptionToggle)
          buildE2EEToggle(),
        buildRoomVisibility(),
        // Vommet issue 439.
        if (widget.room case MatrixRoom room when room.isE2EE)
          SharedHistoryRoomToggle(room),
      ],
    );
  }

  Widget buildE2EEToggle() {
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      child: Opacity(
        opacity: widget.room.permissions.canEnableE2EE ? 1 : 0.5,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelEmphasised(
                      promptEnableEncryptionRoomSettings),
                  tiamat.Text.labelLow(
                      encryptionCannotBeDisabledExplanationRoomSettings)
                ]),
            IgnorePointer(
              ignoring: isE2EEEnabled || !widget.room.permissions.canEnableE2EE,
              child: tiamat.Switch(
                state: isE2EEEnabled,
                onChanged: (value) {
                  if (value != true) return;
                  setState(() {
                    isE2EEEnabled = true;
                    widget.room.enableE2EE();
                  });
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget buildRoomVisibility() {
    // Vommet: the visibility picker plus Element's other access settings.
    final room = matrixRoom;
    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildVisibilityPicker(),
        if (room != null &&
            !isSpace &&
            (visibility is RoomVisibilityPublic || guestCanJoin))
          buildGuestAccess(room),
        if (room != null && isSpace)
          SpacePreviewPanel(
            preview:
                historyVisibility == matrix.HistoryVisibility.worldReadable,
            enabled: room.canChangeHistoryVisibility,
            onChanged: (preview) => setHistoryVisibility(
                room,
                preview
                    ? matrix.HistoryVisibility.worldReadable
                    : matrix.HistoryVisibility.shared),
          ),
        if (room != null && !isSpace)
          RoomHistoryVisibilityPanel(
            value: historyVisibility,
            enabled: room.canChangeHistoryVisibility,
            encrypted: widget.room.isE2EE,
            onChanged: (value) => setHistoryVisibility(room, value),
          ),
        if (room != null && isSpace) buildGuestAccess(room),
      ],
    );
  }

  Widget buildGuestAccess(matrix.Room room) {
    return GuestAccessPanel(
      canJoin: guestCanJoin,
      enabled: room.canChangeGuestAccess,
      isSpace: isSpace,
      onChanged: (canJoin) => ErrorUtils.tryRun(context, () async {
        await room.setGuestAccess(canJoin
            ? matrix.GuestAccess.canJoin
            : matrix.GuestAccess.forbidden);
        if (mounted) setState(() => guestCanJoin = canJoin);
      }),
    );
  }

  void setHistoryVisibility(matrix.Room room, matrix.HistoryVisibility value) {
    ErrorUtils.tryRun(context, () async {
      await room.setHistoryVisibility(value);
      if (mounted) setState(() => historyVisibility = value);
    });
  }

  Widget buildVisibilityPicker() {
    return IgnorePointer(
      ignoring: !widget.room.permissions.canChangeVisibility,
      child: tiamat.Panel(
        header:
            isSpace ? labelSpaceVisibilityHeader : labelRoomVisibilityHeader,
        mode: TileType.surfaceContainerLow,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              List<String> spaces = List.empty(growable: true);
              if (widget.room.visibility
                  case RoomVisibilityRestricted restricted) {
                spaces.addAll(restricted.spaces);
              }
              if (widget.room.visibility case RoomVisibilityKnock knock) {
                spaces.addAll(knock.spaces);
              }

              if (widget.contextSpace != null &&
                  !spaces.contains(widget.contextSpace?.identifier)) {
                spaces.add(widget.contextSpace!.identifier);
              }

              if (spaces.isEmpty) {
                var parents = widget.room.client.spaces.where((i) => i.subspaces
                    .any((i) => i.identifier == widget.room.identifier));

                for (var p in parents) {
                  spaces.add(p.identifier);
                }
              }

              final version = matrixRoom?.roomVersion;
              var items = roomVisibilityChoices(
                spaces: spaces,
                supportsKnock:
                    matrixRoom != null && roomVersionSupportsKnock(version),
                supportsKnockRestricted: matrixRoom != null &&
                    roomVersionSupportsKnockRestricted(version),
              );

              var newVisibility = await AdaptiveDialog.pickOne(
                title: "Set Visibility",
                context,
                items: items,
                itemBuilder: (context, item, callback) =>
                    buildRoomVisibilityChoice(
                        widget.room.client, item, callback),
              );

              if (newVisibility != null) {
                ErrorUtils.tryRun(context, () async {
                  await widget.room.setVisibility(newVisibility);

                  setState(() {
                    visibility = newVisibility;
                  });
                });
              }
            },
            child: RoomFieldVisibility.buildRoomVisibility(
                widget.room.client, visibility),
          ),
        ),
      ),
    );
  }
}
