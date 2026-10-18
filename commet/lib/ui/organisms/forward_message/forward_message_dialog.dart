import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/room_search.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Picks the room or DM to forward a message to.
class ForwardMessageDialog extends StatefulWidget {
  const ForwardMessageDialog({required this.client, this.onPicked, super.key});

  final Client client;
  final void Function(Room room)? onPicked;

  static String get promptForwardMessage => Intl.message(
        "Forward",
        desc: "Label for the menu option to forward a message to another room",
        name: "promptForwardMessage",
      );

  static String get titleForwardTo => Intl.message(
        "Forward to…",
        desc:
            "Title of the dialog used to pick the room to forward a message to",
        name: "titleForwardTo",
      );

  static String get labelNoForwardTargets => Intl.message(
        "No rooms found",
        desc: "Shown when no room matches the search in the forward dialog",
        name: "labelNoForwardTargets",
      );

  /// Shows the picker and returns the chosen room, or null if dismissed.
  static Future<Room?> pick(BuildContext context, Client client) {
    return AdaptiveDialog.show<Room>(
      context,
      title: titleForwardTo,
      scrollable: false,
      builder: (context) => ForwardMessageDialog(
        client: client,
        onPicked: (room) => Navigator.of(context).pop(room),
      ),
    );
  }

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  late final List<Room> targets;
  List<Room> results = List.empty();

  @override
  void initState() {
    targets = widget.client.rooms.where(MatrixForwarding.canForwardTo).toList()
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

  void pickOnlyResult() {
    if (results.length == 1) widget.onPicked?.call(results.first);
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
              onSubmitted: (_) => pickOnlyResult(),
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
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onPicked?.call(room),
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: Row(
              children: [
                tiamat.Avatar(
                    image: room.avatar,
                    placeholderText: room.displayName,
                    placeholderColor: room.defaultColor),
                const SizedBox(width: 10),
                Expanded(
                  child: tiamat.Text.label(room.displayName,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
