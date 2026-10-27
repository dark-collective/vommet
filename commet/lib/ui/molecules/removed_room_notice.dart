import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/composer_notice.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 667: the composer of a room the server no longer has us in
/// (a room purged by a server admin, say, with no leave ever synced). The
/// old messages stay readable; the user can rejoin or forget the room.
class RemovedRoomNotice extends StatefulWidget {
  const RemovedRoomNotice(this.room, {super.key});

  final Room room;

  @override
  State<RemovedRoomNotice> createState() => _RemovedRoomNoticeState();
}

class _RemovedRoomNoticeState extends State<RemovedRoomNotice> {
  bool busy = false;

  String get removedFromRoomNotice =>
      Intl.message("You're no longer in this room.",
          name: "removedFromRoomNotice",
          desc: "Shown in place of the message input when the server no "
              "longer has the user in a room the app still showed as joined");

  String get removedFromRoomExplanation => Intl.message(
      "The server no longer has you in it, so messages you send here won't "
      "arrive.",
      name: "removedFromRoomExplanation",
      desc: "Under 'You're no longer in this room.'");

  String get rejoinRemovedRoom => Intl.message("Rejoin",
      name: "rejoinRemovedRoom",
      desc: "Button that joins a room again after the server dropped the user "
          "from it");

  String forgetRemovedRoomPrompt(String room) => Intl.message(
      "Remove $room from your room list? You can't read it again unless you "
      "rejoin.",
      args: [room],
      name: "forgetRemovedRoomPrompt",
      desc: "Confirmation before forgetting a room the user is no longer in");

  String get errorRejoiningRoom => Intl.message("Couldn't rejoin the room",
      name: "errorRejoiningRoom",
      desc: "Title of the error shown when rejoining a room failed");

  String get errorForgettingRoom => Intl.message("Couldn't forget the room",
      name: "errorForgettingRoom",
      desc: "Title of the error shown when forgetting a room the user is no "
          "longer in failed");

  Future<void> run(Future<void> Function() action,
      {required String errorTitle}) async {
    if (busy) return;
    setState(() => busy = true);
    await ErrorUtils.tryRun(context, action, title: errorTitle);
    if (mounted) setState(() => busy = false);
  }

  Future<void> forget() async {
    final confirmed = await AdaptiveDialog.confirmation(context,
        prompt: forgetRemovedRoomPrompt(widget.room.displayName),
        confirmationText: CommonStrings.promptForget,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (confirmed != true || !mounted) return;
    await run(widget.room.forgetRemoved, errorTitle: errorForgettingRoom);
  }

  @override
  Widget build(BuildContext context) {
    return ComposerNotice(
      icon: Icons.link_off,
      title: removedFromRoomNotice,
      subtitle: removedFromRoomExplanation,
      actionLabel: rejoinRemovedRoom,
      actionIcon: Icons.login,
      // Taps while one action runs are ignored (see [run]).
      onAction: () =>
          run(widget.room.rejoinRemoved, errorTitle: errorRejoiningRoom),
      secondaryActionLabel: CommonStrings.promptForget,
      onSecondaryAction: forget,
    );
  }
}
