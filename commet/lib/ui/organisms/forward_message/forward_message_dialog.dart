import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/room_search.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum _ForwardState { idle, sending, sent, failed }

/// Lists the rooms a message can be forwarded to. Each room has its own Send
/// button, so one message can go to several rooms before the dialog is closed.
class ForwardMessageDialog extends StatefulWidget {
  const ForwardMessageDialog(
      {required this.event, required this.timeline, super.key});

  final TimelineEvent event;
  final Timeline timeline;

  static String get promptForwardMessage => Intl.message(
        "Forward",
        desc: "Label for the menu option to forward a message to another room",
        name: "promptForwardMessage",
      );

  static String get titleForwardMessage => Intl.message(
        "Forward message",
        desc: "Title of the dialog used to pick rooms to forward a message to",
        name: "titleForwardMessage",
      );

  static String get promptSendForward => Intl.message(
        "Send",
        desc: "Button that forwards the message to one room in the list",
        name: "promptSendForward",
      );

  static String get labelForwardSent => Intl.message(
        "Sent",
        desc: "Shown next to a room once the message was forwarded to it",
        name: "labelForwardSent",
      );

  static String get labelForwardFailed => Intl.message(
        "Failed, retry",
        desc: "Button shown next to a room when forwarding to it failed",
        name: "labelForwardFailed",
      );

  static String get labelNoForwardTargets => Intl.message(
        "No rooms found",
        desc: "Shown when no room matches the search in the forward dialog",
        name: "labelNoForwardTargets",
      );

  static Future<void> show(
      BuildContext context, TimelineEvent event, Timeline timeline) {
    return AdaptiveDialog.show(
      context,
      title: titleForwardMessage,
      scrollable: false,
      builder: (context) =>
          ForwardMessageDialog(event: event, timeline: timeline),
    );
  }

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  late final List<Room> targets;
  List<Room> results = List.empty();
  final Map<String, _ForwardState> states = {};

  @override
  void initState() {
    targets = widget.timeline.client.rooms
        .where(MatrixForwarding.canForwardTo)
        .toList()
      ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
    results = targets;
    super.initState();
  }

  void setQuery(String query) {
    setState(() {
      results = RoomSearch.rank(targets, query,
          name: (r) => r.displayName,
          id: (r) => r.identifier,
          lastActive: (r) => r.lastEventTimestamp);
    });
  }

  Future<void> forwardTo(Room room) async {
    setState(() => states[room.identifier] = _ForwardState.sending);

    try {
      await MatrixForwarding.forward(widget.event, widget.timeline, room);
      if (mounted) setState(() => states[room.identifier] = _ForwardState.sent);
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to forward message");
      if (mounted) {
        setState(() => states[room.identifier] = _ForwardState.failed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      height: MediaQuery.of(context).desktop
          ? 500
          : MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              decoration: InputDecoration(
                  icon: const Icon(Icons.search),
                  hintText: CommonStrings.promptSearch),
              maxLines: 1,
              autofocus: MediaQuery.of(context).desktop,
              onChanged: setQuery,
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: tiamat.Text.labelLow(
                        ForwardMessageDialog.labelNoForwardTargets))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) =>
                        buildRoom(context, results[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget buildRoom(BuildContext context, Room room) {
    var state = states[room.identifier] ?? _ForwardState.idle;

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Row(
        children: [
          tiamat.Avatar(
              image: room.avatar,
              placeholderText: room.displayName,
              placeholderColor: room.defaultColor),
          const SizedBox(width: 8),
          Expanded(
            child: tiamat.Text.label(room.displayName,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          switch (state) {
            _ForwardState.sent => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child:
                    tiamat.Text.labelLow(ForwardMessageDialog.labelForwardSent),
              ),
            _ForwardState.failed => tiamat.Button.danger(
                text: ForwardMessageDialog.labelForwardFailed,
                onTap: () => forwardTo(room),
              ),
            _ => tiamat.Button.secondary(
                text: ForwardMessageDialog.promptSendForward,
                isLoading: state == _ForwardState.sending,
                onTap: state == _ForwardState.sending
                    ? null
                    : () => forwardTo(room),
              ),
          },
        ],
      ),
    );
  }
}
