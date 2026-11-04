// Vommet issue 744: share a room's encrypted history with a person however
// they join, not only through an invite (MSC4268 bundles sent as "history
// grants" by the SDK, HistorySharing.grantHistory). Started from a member's
// menu or profile card in a room, or the space invite dialog; listed in
// Settings › Security › Encrypted history, where it can be stopped.

import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/telemetry/verification_telemetry.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/encryption/history_sharing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

class ShareHistoryStrings {
  static String get menuItem => Intl.message("Share history…",
      name: "shareHistoryMenuItem",
      desc:
          "Menu item on a person in an encrypted room: share the room's earlier messages with them, however they join");

  static String title(String name) => Intl.message("Share history with $name",
      args: [name],
      name: "shareHistoryTitle",
      desc: "Title of the dialog that shares encrypted history with a person");

  static String get explainer => Intl.message(
      "They get the earlier messages of the rooms you tick, however and whenever they join.",
      name: "shareHistoryExplainer",
      desc: "Share history dialog: what sharing does, under the title");

  static String allRoomsIn(String space) => Intl.message("All rooms in $space",
      args: [space],
      name: "shareHistoryAllRoomsIn",
      desc:
          "Share history dialog: tick that selects every encrypted room of a space; space is its name");

  static String countOf(int ticked, int total) =>
      Intl.message("$ticked of $total",
          args: [ticked, total],
          name: "shareHistoryCountOf",
          desc: "Share history dialog: how many of a space's rooms are ticked");

  static String get footSenders => Intl.message(
      "Only messages their senders agreed to share are included.",
      name: "shareHistoryFootSenders",
      desc:
          "Share history dialog: note that only messages whose senders allow sharing go along");

  static String get footStop => Intl.message(
      "Stopping later won't take back what was already shared.",
      name: "shareHistoryFootStop",
      desc:
          "Share history dialog: note that stopping a share can't take back keys already sent");

  static String get share => Intl.message("Share",
      name: "shareHistoryShare", desc: "Share history dialog: confirm button");

  static String sent(int rooms, String name) => Intl.plural(rooms,
      one: "Shared this room's history with $name.",
      other: "Shared the history of $rooms rooms with $name.",
      args: [rooms, name],
      name: "shareHistorySent",
      desc: "Share history dialog: result when bundles were sent");

  static String noDevices(String name) => Intl.message(
      "$name has no cross-signed sessions yet, so nothing was sent now. Your devices send it when they join.",
      args: [name],
      name: "shareHistoryNoDevices",
      desc:
          "Share history dialog: result when the person has no cross-signed devices yet");

  static String identityChanged(String name) => Intl.message(
      "$name's identity changed since you last shared with them. Verify them, then share again.",
      args: [name],
      name: "shareHistoryIdentityChanged",
      desc:
          "Share history dialog: result when the person's cross-signing identity changed");

  static String nothingShareable(int rooms) => Intl.plural(rooms,
      one: "1 room had no messages that may be shared yet.",
      other: "$rooms rooms had no messages that may be shared yet.",
      args: [rooms],
      name: "shareHistoryNothingShareable",
      desc:
          "Share history dialog: result for rooms with no shareable messages");

  static String get failed => Intl.message(
      "Some rooms couldn't be shared. Your devices try again when they join.",
      name: "shareHistoryFailed",
      desc: "Share history dialog: result when sending failed for some rooms");

  static String get grantsTitle => Intl.message("History you've shared",
      name: "shareHistoryGrantsTitle",
      desc:
          "Settings › Security: header of the list of people you shared encrypted history with");

  static String get grantsDescription =>
      Intl.message("Your devices send fresh history when these people join.",
          name: "shareHistoryGrantsDescription",
          desc: "Settings › Security: explains the list of history shares");

  static String roomsIn(int rooms, String space) => Intl.plural(rooms,
      one: "1 room in $space",
      other: "$rooms rooms in $space",
      args: [rooms, space],
      name: "shareHistoryRoomsIn",
      desc: "Settings › Security: history share row, rooms of one space");

  static String rooms(int rooms) => Intl.plural(rooms,
      one: "1 room",
      other: "$rooms rooms",
      args: [rooms],
      name: "shareHistoryRooms",
      desc: "Settings › Security: history share row, number of rooms");

  static String since(String date) => Intl.message("since $date",
      args: [date],
      name: "shareHistorySince",
      desc: "Settings › Security: history share row, when it started");

  static String get stop => Intl.message("Stop",
      name: "shareHistoryStop",
      desc:
          "Settings › Security: button that stops sharing history with someone");

  static String stopPrompt(String name) => Intl.message(
      "Stop sharing history with $name? What was already shared stays with them.",
      args: [name],
      name: "shareHistoryStopPrompt",
      desc:
          "Settings › Security: confirmation before stopping a history share");

  static String heldTitle(String name) => Intl.message(
      "$name shared earlier messages with you",
      args: [name],
      name: "shareHistoryHeldTitle",
      desc:
          "Strip above a room's timeline: someone you haven't verified shared the room's history");

  static String heldVerify(String name) => Intl.message(
      "Verify $name to read them",
      args: [name],
      name: "shareHistoryHeldVerify",
      desc:
          "Strip above a room's timeline: what to do to read history shared by someone unverified");

  static String get verify => Intl.message("Verify",
      name: "shareHistoryVerifyButton",
      desc:
          "Strip above a room's timeline: button that starts verifying someone");

  static String alsoShareJoined(int rooms) => Intl.plural(rooms,
      one: "Also share history in the room they're already in",
      other: "Also share history in the $rooms rooms they're already in",
      args: [rooms],
      name: "shareHistoryAlsoShareJoined",
      desc:
          "Space invite dialog: tick that shares encrypted history in rooms the person already joined");
}

class ShareHistory {
  static HistorySharing? sharingOf(Room room) => room is MatrixRoom
      ? room.matrixRoom.client.encryption?.historySharing
      : null;

  /// Whether [room]'s history can be shared with [userId] from it.
  static bool canShare(Room room, String userId) =>
      room is MatrixRoom &&
      room.isE2EE &&
      sharingOf(room) != null &&
      userId != room.matrixRoom.client.userID;

  static String nameOf(matrix.Room room, String userId) =>
      room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname();

  /// The space offered along with [room] (the first one we're in that holds
  /// it) and the rooms offered: [room] first, then that space's other
  /// encrypted rooms we're joined to.
  static (Space?, List<MatrixRoom>) roomsAround(MatrixRoom room) {
    final space = room.client.spaces
        .where((s) => s.containsRoom(room.identifier))
        .firstOrNull;
    final rooms = <MatrixRoom>[room];
    for (final r in space?.rooms ?? const <Room>[]) {
      if (r is MatrixRoom &&
          r.identifier != room.identifier &&
          r.isE2EE &&
          r.matrixRoom.membership == matrix.Membership.join) {
        rooms.add(r);
      }
    }
    return (space, rooms);
  }

  /// What a [HistorySharing.grantHistory] result means, for [name].
  static String summary(Map<String, String> outcomes, String name) {
    int count(String o) => outcomes.values.where((v) => v == o).length;
    final sent = count("sent");
    return [
      if (sent > 0) ShareHistoryStrings.sent(sent, name),
      if (count("no_cross_signed_devices") > 0)
        ShareHistoryStrings.noDevices(name),
      if (count("identity_changed") > 0)
        ShareHistoryStrings.identityChanged(name),
      if (count("nothing_shareable") > 0)
        ShareHistoryStrings.nothingShareable(count("nothing_shareable")),
      if (count("error") > 0) ShareHistoryStrings.failed,
    ].join(" ");
  }

  /// Asks which rooms around [room] to share with [userId], shares them.
  static Future<void> show(
      BuildContext context, MatrixRoom room, String userId) async {
    final (space, rooms) = roomsAround(room);
    await AdaptiveDialog.show<void>(context,
        title: ShareHistoryStrings.title(nameOf(room.matrixRoom, userId)),
        builder: (context) => ShareHistoryDialog(
            room: room, userId: userId, space: space, rooms: rooms));
  }

  /// Starts verifying [userId], then tries the history they shared again.
  static Future<void> verify(
      BuildContext context, matrix.Client client, String userId) async {
    final keys = client.userDeviceKeys[userId];
    if (keys == null) return;
    final request = await keys.startVerification();
    VerificationTelemetry.outgoing(request);
    if (!context.mounted) return;
    await AdaptiveDialog.show(context,
        builder: (_) => MatrixVerificationPage(request: request),
        title: ShareHistoryStrings.verify);
    await client.encryption?.historySharing.retryHeldGrants();
  }
}

class ShareHistoryDialog extends StatefulWidget {
  const ShareHistoryDialog(
      {required this.room,
      required this.userId,
      required this.space,
      required this.rooms,
      super.key});

  final MatrixRoom room;
  final String userId;
  final Space? space;
  final List<MatrixRoom> rooms;

  @override
  State<ShareHistoryDialog> createState() => _ShareHistoryDialogState();
}

class _ShareHistoryDialogState extends State<ShareHistoryDialog> {
  late final Set<String> ticked = {widget.room.identifier};
  bool busy = false;
  String? result;

  bool get allTicked => ticked.length == widget.rooms.length;

  Future<void> share() async {
    final sharing = ShareHistory.sharingOf(widget.room);
    if (sharing == null) return;
    setState(() => busy = true);
    String summary;
    try {
      final outcomes = await sharing.grantHistory(widget.userId, ticked,
          spaceId: widget.space != null && allTicked && ticked.length > 1
              ? widget.space!.identifier
              : null);
      summary = ShareHistory.summary(
          outcomes, ShareHistory.nameOf(widget.room.matrixRoom, widget.userId));
    } catch (e, s) {
      Log.onError(e, s);
      summary = ShareHistoryStrings.failed;
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      result = summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: dim);
    final done = result;
    if (done != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tiamat.Text.body(done),
              const SizedBox(height: 12),
              tiamat.Button(
                  key: const ValueKey("share-history-done"),
                  text: CommonStrings.promptDone,
                  onTap: () => Navigator.pop(context)),
            ]),
      );
    }
    final space = widget.space;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(ShareHistoryStrings.explainer, style: small),
          const SizedBox(height: 8),
          if (space != null && widget.rooms.length > 1)
            CheckboxListTile(
              key: const ValueKey("share-history-all"),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              tristate: true,
              value: allTicked ? true : (ticked.isEmpty ? false : null),
              title: Text(ShareHistoryStrings.allRoomsIn(space.displayName),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              secondary: Text(
                  ShareHistoryStrings.countOf(
                      ticked.length, widget.rooms.length),
                  style: small),
              onChanged: busy
                  ? null
                  : (_) => setState(() {
                        if (allTicked) {
                          ticked.clear();
                        } else {
                          ticked.addAll(widget.rooms.map((r) => r.identifier));
                        }
                      }),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in widget.rooms)
                  CheckboxListTile(
                    key: ValueKey("share-history-room-${r.identifier}"),
                    dense: true,
                    contentPadding: EdgeInsets.only(
                        left:
                            space != null && widget.rooms.length > 1 ? 24 : 0),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: ticked.contains(r.identifier),
                    title: Text(r.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onChanged: busy
                        ? null
                        : (v) => setState(() => v == true
                            ? ticked.add(r.identifier)
                            : ticked.remove(r.identifier)),
                  ),
              ],
            ),
          ),
          const Divider(),
          Text(ShareHistoryStrings.footSenders, style: small),
          Text(ShareHistoryStrings.footStop, style: small),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : tiamat.Button(
                    key: const ValueKey("share-history-confirm"),
                    text: ShareHistoryStrings.share,
                    onTap: ticked.isEmpty ? null : share,
                  ),
          ),
          const SizedBox(height: 5),
          tiamat.Button.secondary(
            text: CommonStrings.promptCancel,
            onTap: busy ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

/// Settings › Security › Encrypted history: whom we shared history with.
class HistoryGrantsList extends StatefulWidget {
  const HistoryGrantsList(this.client, {super.key});
  final MatrixClient client;

  @override
  State<HistoryGrantsList> createState() => _HistoryGrantsListState();
}

class _HistoryGrantsListState extends State<HistoryGrantsList> {
  StreamSubscription? _sub;

  matrix.Client get mx => widget.client.getMatrixClient();

  @override
  void initState() {
    super.initState();
    _sub = widget.client.onSync.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String nameOf(String userId, Iterable<String> roomIds) {
    for (final id in roomIds) {
      final room = mx.getRoomById(id);
      if (room != null) return ShareHistory.nameOf(room, userId);
    }
    return userId;
  }

  String detailOf(Map<String, ({DateTime since, String? spaceId})> rooms) {
    final spaces = rooms.values.map((g) => g.spaceId).toSet();
    final spaceName = spaces.length == 1 && spaces.first != null
        ? widget.client.getSpace(spaces.first!)?.displayName
        : null;
    final String what;
    if (spaceName != null) {
      what = ShareHistoryStrings.roomsIn(rooms.length, spaceName);
    } else if (rooms.length == 1) {
      what = mx.getRoomById(rooms.keys.first)?.getLocalizedDisplayname() ??
          ShareHistoryStrings.rooms(1);
    } else {
      what = ShareHistoryStrings.rooms(rooms.length);
    }
    final first = rooms.values
        .map((g) => g.since)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return "$what · ${ShareHistoryStrings.since(DateFormat.MMMd().format(first))}";
  }

  @override
  Widget build(BuildContext context) {
    final sharing = mx.encryption?.historySharing;
    if (sharing == null) return const SizedBox.shrink();
    final byUser = <String, Map<String, ({DateTime since, String? spaceId})>>{};
    for (final room in sharing.historyGrants.entries) {
      for (final user in room.value.entries) {
        (byUser[user.key] ??= {})[room.key] = user.value;
      }
    }
    if (byUser.isEmpty) return const SizedBox.shrink();
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      key: const ValueKey("history-grants-list"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        tiamat.Text.labelEmphasised(ShareHistoryStrings.grantsTitle),
        Text(ShareHistoryStrings.grantsDescription,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dim)),
        for (final entry in byUser.entries)
          ListTile(
            key: ValueKey("history-grant-${entry.key}"),
            contentPadding: EdgeInsets.zero,
            title: Text(nameOf(entry.key, entry.value.keys)),
            subtitle: Text(detailOf(entry.value)),
            trailing: TextButton(
              onPressed: () async {
                final name = nameOf(entry.key, entry.value.keys);
                if (await AdaptiveDialog.confirmation(context,
                        prompt: ShareHistoryStrings.stopPrompt(name),
                        confirmationText: ShareHistoryStrings.stop,
                        dangerous: true) !=
                    true) {
                  return;
                }
                if (!context.mounted) return;
                await ErrorUtils.tryRun(
                    context, () => sharing.stopHistoryGrant(entry.key));
                if (mounted) setState(() {});
              },
              child: Text(ShareHistoryStrings.stop,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
      ],
    );
  }
}
