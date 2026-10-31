import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/share_intake.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// "Share to…" room picker shown when another app shares into Vommet.
/// Returns the chosen room, or null when dismissed.
class ShareTargetDialog extends StatefulWidget {
  const ShareTargetDialog({required this.payload, super.key});

  final SharePayload payload;

  static String get titleShareTo => Intl.message(
        "Share to…",
        desc: "Title of the room picker shown when sharing from another app",
        name: "titleShareTo",
      );

  static String labelShareFiles(int count) => Intl.plural(
        count,
        one: "1 file",
        other: "$count files",
        desc: "Summary of how many files are being shared into a room",
        name: "labelShareFiles",
        args: [count],
      );

  static String get labelShareNoRooms => Intl.message(
        "No rooms found",
        desc: "Shown when no room matches the search in the share picker",
        name: "labelShareNoRooms",
      );

  static Future<Room?> show(BuildContext context, SharePayload payload) {
    return AdaptiveDialog.show<Room>(
      context,
      title: titleShareTo,
      scrollable: false,
      builder: (context) => ShareTargetDialog(payload: payload),
    );
  }

  @override
  State<ShareTargetDialog> createState() => _ShareTargetDialogState();
}

class _ShareTargetDialogState extends State<ShareTargetDialog> {
  late final List<Room> targets;
  List<Room> results = List.empty();

  @override
  void initState() {
    targets = (clientManager?.rooms.toList() ?? <Room>[])
        .where((r) => r.permissions.canSendMessage)
        .toList()
      ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
    results = targets;
    super.initState();
  }

  void setQuery(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      results = q.isEmpty
          ? targets
          : targets
              .where((r) =>
                  r.displayName.toLowerCase().contains(q) ||
                  r.identifier.toLowerCase().contains(q))
              .toList();
    });
  }

  String get summary {
    final parts = <String>[];
    final files = widget.payload.files;
    if (files.isNotEmpty) {
      parts.add(files.length == 1
          ? files.first.name
          : ShareTargetDialog.labelShareFiles(files.length));
    }
    final text = widget.payload.text?.trim();
    if (text != null && text.isNotEmpty) parts.add(text);
    return parts.join(" · ");
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      height: MediaQuery.of(context).desktop
          ? 500
          : MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: tiamat.Text.labelLow(summary,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              decoration: InputDecoration(
                  icon: const Icon(Icons.search),
                  hintText: CommonStrings.promptSearch),
              maxLines: 1,
              onChanged: setQuery,
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: tiamat.Text.labelLow(
                        ShareTargetDialog.labelShareNoRooms))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final room = results[index];
                      return RoomPanel(
                        room,
                        key: ValueKey(
                            "${room.client.identifier}/${room.identifier}"),
                        onTap: () => Navigator.of(context).pop(room),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
