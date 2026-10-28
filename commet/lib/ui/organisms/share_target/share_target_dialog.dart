import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/room_row_size.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/share_intake.dart';
import 'package:commet/utils/share_target_order.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// "Share to…" room picker shown when another app shares into Vommet.
/// Returns the chosen room, or null when dismissed. Vommet issues 795, 807:
/// long-press a room to tick several; they're returned in the order picked.
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

  static String labelShareSelected(int count) => Intl.message(
      "Selected · $count",
      args: [count],
      desc:
          "Heading over the rooms ticked in the share picker while picking several",
      name: "labelShareSelected");

  static String get labelShareAllRooms => Intl.message("All rooms",
      desc:
          "Heading over the other rooms in the share picker, under the ticked ones",
      name: "labelShareAllRooms");

  static String promptShareToRooms(int count) => Intl.plural(count,
      one: "Share to 1 room",
      other: "Share to $count rooms",
      args: [count],
      desc: "Button in the share picker that shares to every ticked room",
      name: "promptShareToRooms");

  static Future<List<Room>?> show(BuildContext context, SharePayload payload) {
    return AdaptiveDialog.show<List<Room>>(
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

  /// Vommet issues 795, 807: the ticked rooms, in the order picked. Empty
  /// unless a long-press started picking several.
  final Map<String, Room> selected = {};

  bool get selecting => selected.isNotEmpty;

  static String keyOf(Room room) =>
      "${room.client.identifier}/${room.identifier}";

  void toggle(Room room) {
    setState(() {
      if (selected.remove(keyOf(room)) == null) selected[keyOf(room)] = room;
    });
  }

  void tap(Room room) =>
      selecting ? toggle(room) : Navigator.of(context).pop([room]);

  /// Enter: picks the only match, or ticks it while ticking.
  void pickOnlyResult() {
    if (results.length != 1) return;
    final room = results.first;
    if (!selecting) {
      tap(room);
    } else if (!selected.containsKey(keyOf(room))) {
      toggle(room);
    }
  }

  @override
  void initState() {
    targets = orderShareTargets(
      (clientManager?.rooms.toList() ?? <Room>[])
          .where((r) => r.permissions.canSendMessage),
      lastActivity: (r) => r.lastEventTimestamp,
      isFavorite: (r) => r.isFavorite,
      isDirectMessage: (r) =>
          r.client
              .getComponent<DirectMessagesComponent>()
              ?.isRoomDirectMessage(r) ==
          true,
    );
    results = targets;
    super.initState();
  }

  String query = "";

  void setQuery(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      this.query = q;
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

  Widget header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: tiamat.Text.labelLow(text),
      );

  Widget roomRow(Room room) {
    final redaction = RedactionScope.of(context);
    final name = redaction.roomDisplayName(room);
    // Vommet issue 796: Standard or Large rows, as in the room lists.
    final size = roomRowSize;
    return Padding(
      key: ValueKey(keyOf(room)),
      padding: EdgeInsets.fromLTRB(2, 2, 2, 2 + size.rowGap),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: () => tap(room),
          onLongPress: () => toggle(room),
          child: Padding(
            padding: EdgeInsets.all(size.isLarge ? 8 : 6),
            child: Row(
              children: [
                tiamat.Avatar(
                    radius: size.shareAvatarRadius,
                    image: room.avatar,
                    placeholderText: name,
                    placeholderColor: room.defaultColor),
                const SizedBox(width: 10),
                Expanded(
                    child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            textScaler: size
                                .textScaler(MediaQuery.textScalerOf(context))),
                        child: tiamat.Text.label(name,
                            overflow: TextOverflow.ellipsis))),
                if (selecting)
                  Checkbox(
                      value: selected.containsKey(keyOf(room)),
                      onChanged: (_) => toggle(room),
                      mouseCursor: WidgetStateMouseCursor.clickable),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Vommet issues 795, 807: with no search, the ticked rooms sit on top,
    // once.
    final showSelected = selecting && query.isEmpty;
    final rows = [
      if (showSelected) ...[
        header(ShareTargetDialog.labelShareSelected(selected.length)),
        for (final room in selected.values) roomRow(room),
        header(ShareTargetDialog.labelShareAllRooms),
      ],
      for (final room in results)
        if (!showSelected || !selected.containsKey(keyOf(room))) roomRow(room),
    ];

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
              onSubmitted: (_) => pickOnlyResult(),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: tiamat.Text.labelLow(
                        ShareTargetDialog.labelShareNoRooms))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => rows[index],
                  ),
          ),
          if (selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: Text(
                      ShareTargetDialog.promptShareToRooms(selected.length)),
                  onPressed: () =>
                      Navigator.of(context).pop(selected.values.toList()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
