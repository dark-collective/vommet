import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/composer_notice.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: the composer of a replaced room (m.room.tombstone) becomes a link
/// to the room the conversation moved to.
class ReplacedRoomNotice extends StatefulWidget {
  const ReplacedRoomNotice(this.room, {super.key});

  final Room room;

  @override
  State<ReplacedRoomNotice> createState() => _ReplacedRoomNoticeState();
}

class _ReplacedRoomNoticeState extends State<ReplacedRoomNotice> {
  bool opening = false;

  String get roomReplacedNotice => Intl.message("This room has been replaced.",
      name: "roomReplacedNotice",
      desc: "Shown in place of the message input in a room that was replaced "
          "by another one");

  String roomReplacedContinuesIn(String room) => Intl.message(
      "The conversation continues in $room. Older messages stay here.",
      args: [room],
      name: "roomReplacedContinuesIn",
      desc: "Under 'This room has been replaced.', naming the new room");

  String get roomReplacedContinuesElsewhere => Intl.message(
      "The conversation continues in a new room. Older messages stay here.",
      name: "roomReplacedContinuesElsewhere",
      desc: "Under 'This room has been replaced.', when the new room's name "
          "isn't known yet");

  String get goToReplacementRoom => Intl.message("Go to the new room",
      name: "goToReplacementRoom",
      desc: "Button that joins (if needed) and opens the room that replaced "
          "this one");

  String get errorOpeningReplacementRoom =>
      Intl.message("Couldn't open the new room",
          name: "errorOpeningReplacementRoom",
          desc: "Title of the error shown when joining the replacement room "
              "failed");

  Future<void> open() async {
    final replacement = widget.room.replacement;
    if (replacement == null || opening) return;
    setState(() => opening = true);
    await ErrorUtils.tryRun(context, () async {
      final next = await replacement.openReplacement();
      EventBus.doOpenRoom(next.identifier, clientId: next.client.identifier);
    }, title: errorOpeningReplacementRoom);
    if (mounted) setState(() => opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final tombstone = widget.room.replacement?.tombstone;
    final next = tombstone == null
        ? null
        : widget.room.client.getRoom(tombstone.replacementRoomId);

    return ComposerNotice(
      icon: Icons.moving,
      iconColor: Theme.of(context).colorScheme.primary,
      title: roomReplacedNotice,
      subtitle: replacedNoticeMessage(tombstone) ??
          (next != null
              ? roomReplacedContinuesIn(next.displayName)
              : roomReplacedContinuesElsewhere),
      actionLabel: goToReplacementRoom,
      actionIcon: Icons.arrow_forward,
      onAction: open,
    );
  }
}
