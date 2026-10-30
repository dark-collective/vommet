import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/organisms/share_history/share_history.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/encryption/history_sharing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 439: "Let people who join later read my messages", the
/// MSC4268 shared-history mark on our message keys. Kept in account data
/// by the SDK (`im.nether.shared_history`), so every device of the account
/// follows it. It can only narrow sharing: a room whose history new members
/// can't see never gets the mark.
class SharedHistoryStrings {
  static String get panelTitle => Intl.message("Encrypted history",
      desc:
          "Header of the Security settings section about letting people who join later read your earlier encrypted messages",
      name: "labelSharedHistoryPanelTitle");

  static String get toggleTitle => Intl.message(
      "Let people who join later read my messages",
      desc:
          "Toggle: people who join an encrypted room later may read the user's earlier messages there",
      name: "labelSharedHistoryToggle");

  static String get toggleDescription => Intl.message(
      "In encrypted rooms whose history new members can see, people you invite or who join later can read your earlier messages. Off: only people who were in the room when you sent a message can read it.",
      desc: "Explains the shared history toggle in Security settings",
      name: "labelSharedHistoryToggleDescription");

  static String get roomToggleDescription => Intl.message(
      "Follows your setting in Settings › Security. Off: people who join later can't read what you send in this room.",
      desc: "Explains the per-room shared history toggle in room settings",
      name: "labelSharedHistoryRoomToggleDescription");

  static String get roomOffEverywhere => Intl.message(
      "Off for all rooms in Settings › Security.",
      desc:
          "Shown under the per-room shared history toggle when the user turned it off for every room",
      name: "labelSharedHistoryRoomOffEverywhere");

  static String get roomHistoryNotShared => Intl.message(
      "This room's history isn't visible to new members, so they can't read your earlier messages here either way.",
      desc:
          "Shown under the per-room shared history toggle when the room's history visibility already hides history from new members",
      name: "labelSharedHistoryRoomNotShared");
}

/// Settings › Security › Encrypted history.
class SharedHistoryPanel extends StatelessWidget {
  const SharedHistoryPanel(this.client, {super.key});
  final MatrixClient client;

  @override
  Widget build(BuildContext context) {
    final mx = client.getMatrixClient();
    final sharing = mx.encryption?.historySharing;
    if (sharing == null) return const SizedBox.shrink();
    return tiamat.Panel(
      header: SharedHistoryStrings.panelTitle,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            BooleanToggle(
              setValue: (value) async {
                await ErrorUtils.tryRun(context, () async {
                  await sharing.setSharingAllowed(value);
                });
              },
              getValue: () =>
                  mx.accountData[HistorySharing.settingType]
                      ?.content['enabled'] !=
                  false,
              title: SharedHistoryStrings.toggleTitle,
              description: SharedHistoryStrings.toggleDescription,
              searchId: "security.shared-history",
            ),
            // Vommet issue 744: history shared with someone by hand.
            HistoryGrantsList(client),
          ]),
    );
  }
}

/// Room settings › Security: turns the mark off for one room.
class SharedHistoryRoomToggle extends StatefulWidget {
  const SharedHistoryRoomToggle(this.room, {super.key});
  final MatrixRoom room;

  @override
  State<SharedHistoryRoomToggle> createState() =>
      _SharedHistoryRoomToggleState();
}

class _SharedHistoryRoomToggleState extends State<SharedHistoryRoomToggle> {
  StreamSubscription? _sub;

  matrix.Room get room => widget.room.matrixRoom;

  @override
  void initState() {
    super.initState();
    _sub = widget.room.client.onSync.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  bool get _offEverywhere =>
      room.client.accountData[HistorySharing.settingType]?.content['enabled'] ==
      false;

  bool get _roomOff =>
      room.roomAccountData[HistorySharing.settingType]?.content['mode'] ==
      'off';

  bool get _historyShared => HistorySharing.roomSharesHistory(room);

  @override
  Widget build(BuildContext context) {
    final sharing = room.client.encryption?.historySharing;
    if (sharing == null) return const SizedBox.shrink();
    final locked = _offEverywhere;
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      child: Opacity(
        opacity: locked ? 0.5 : 1,
        child: IgnorePointer(
          ignoring: locked,
          child: BooleanToggle(
            // Rebuilt when the global setting changes.
            key: ValueKey(locked),
            setValue: (value) async {
              await ErrorUtils.tryRun(context, () async {
                await sharing.setRoomSharingOff(room.id, !value);
              });
            },
            getValue: () => !locked && !_roomOff,
            title: SharedHistoryStrings.toggleTitle,
            description: locked
                ? SharedHistoryStrings.roomOffEverywhere
                : _historyShared
                    ? SharedHistoryStrings.roomToggleDescription
                    : SharedHistoryStrings.roomHistoryNotShared,
          ),
        ),
      ),
    );
  }
}
