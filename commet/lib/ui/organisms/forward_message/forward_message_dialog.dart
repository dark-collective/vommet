import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/ui/organisms/forward_message/forward_picker_view.dart';
import 'package:commet/utils/room_search.dart';
import 'package:commet/utils/space_paths.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  static String get labelForwardFilterAll => Intl.message(
        "All",
        desc:
            "Filter in the forward dialog that shows rooms from every space and direct messages",
        name: "labelForwardFilterAll",
      );

  static String get labelForwardFilterDirectMessages => Intl.message(
        "Direct messages",
        desc: "Filter in the forward dialog that shows only direct messages",
        name: "labelForwardFilterDirectMessages",
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
  static const _all = "all";
  static const _dms = "dms";

  /// Vommet: the filter used last, per account, so the next forward starts
  /// there (Vommet issue 252). Kept until the app closes.
  static final Map<String, List<String>> _lastFilter = {};

  late final List<Room> targets;
  late final List<Space> topSpaces;
  late final Map<String, List<List<Space>>> paths;
  DirectMessagesComponent? directMessages;

  /// [_all], [_dms], or a top-level space's id.
  String filter = _all;

  /// The open space and the subspaces opened inside it, top first.
  List<Space> spacePath = [];

  String query = "";

  @override
  void initState() {
    final client = widget.client;
    targets = client.rooms.where(MatrixForwarding.canForwardTo).toList()
      ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
    topSpaces = client.spaces.where((s) => s.isTopLevel).toList();
    paths = SpacePaths.index<Space>(topSpaces,
        roomIds: (s) => s.rooms.map((r) => r.identifier),
        subspaces: (s) => s.subspaces,
        id: (s) => s.identifier);
    directMessages = client.getComponent<DirectMessagesComponent>();
    restoreFilter();
    super.initState();
  }

  void restoreFilter() {
    final last = _lastFilter[widget.client.identifier];
    // No spaces, no filter row: always start with everything.
    if (last == null || last.isEmpty || topSpaces.isEmpty) return;
    if (last.first == _dms && directMessages != null) {
      filter = _dms;
      return;
    }

    var children = topSpaces;
    final restored = <Space>[];
    for (final id in last) {
      final space = children.where((s) => s.identifier == id).firstOrNull;
      if (space == null) break;
      restored.add(space);
      children = space.subspaces;
    }
    if (restored.isEmpty) return;
    filter = restored.first.identifier;
    spacePath = restored;
  }

  void rememberFilter() {
    _lastFilter[widget.client.identifier] = switch (filter) {
      _all => [],
      _dms => [_dms],
      _ => spacePath.map((s) => s.identifier).toList(),
    };
  }

  void selectChip(String id) {
    setState(() {
      filter = id;
      spacePath = [
        if (id != _all && id != _dms)
          ...topSpaces.where((s) => s.identifier == id).take(1),
      ];
    });
  }

  void openSubspace(Space space) {
    setState(() => spacePath = [...spacePath, space]);
  }

  void backTo(int index) {
    setState(() => spacePath = spacePath.take(index + 1).toList());
  }

  void pick(Room room) {
    rememberFilter();
    widget.onPicked?.call(room);
  }

  bool isDirectMessage(Room room) =>
      directMessages?.isRoomDirectMessage(room) == true;

  /// The rooms the current filter allows, before searching.
  List<Room> get pool {
    if (filter == _dms) return targets.where(isDirectMessage).toList();
    if (spacePath.isEmpty) return targets;
    final inSpace =
        spacePath.last.roomsWithChildren.map((r) => r.identifier).toSet();
    return targets.where((r) => inSpace.contains(r.identifier)).toList();
  }

  List<Room> get results {
    if (query.isEmpty) {
      if (spacePath.isEmpty) return pool;
      // Inside a space: its own rooms, in the space's order.
      final ids = targets.map((r) => r.identifier).toSet();
      return spacePath.last.rooms
          .where((r) => ids.contains(r.identifier))
          .toList();
    }

    return RoomSearch.rank(pool, query,
        name: (r) => r.displayName,
        id: (r) => r.identifier,
        lastActive: (r) => r.lastEventTimestamp);
  }

  void setQuery(String query) {
    setState(() => this.query = query);
  }

  void pickOnlyResult() {
    final found = results;
    if (found.length == 1) pick(found.first);
  }

  @override
  Widget build(BuildContext context) {
    final rooms = results;
    // Vommet issue 475: names follow redacted mode.
    final redaction = RedactionScope.of(context);
    String spaceName(Space s) =>
        redaction.roomName(s.displayName, s.identifier);
    final rows = [
      if (query.isEmpty && spacePath.isNotEmpty)
        for (final space in spacePath.last.subspaces)
          ForwardPickerRow(
              title: spaceName(space),
              avatar: space.avatar,
              color: space.color,
              isSpace: true,
              onTap: () => openSubspace(space)),
      for (final room in rooms)
        ForwardPickerRow(
            title: redaction.roomDisplayName(room),
            subtitle: filter == _dms
                ? null
                : SpacePaths.label<Space>(paths[room.identifier],
                    name: spaceName,
                    id: (s) => s.identifier,
                    inside: spacePath),
            avatar: room.avatar,
            color: room.defaultColor,
            onTap: () => pick(room)),
    ];

    return SizedBox(
      width: 500,
      height: MediaQuery.of(context).desktop
          ? 500
          : MediaQuery.of(context).size.height * 0.6,
      child: ForwardPickerView(
        searchHint: CommonStrings.promptSearch,
        autofocus: MediaQuery.of(context).desktop,
        onQueryChanged: setQuery,
        onSubmitted: (_) => pickOnlyResult(),
        // Filters only help once there's a space to pick.
        chips: [
          if (topSpaces.isNotEmpty) ...[
            ForwardPickerChip(
                id: _all,
                name: ForwardMessageDialog.labelForwardFilterAll,
                icon: Icons.all_inclusive),
            if (directMessages != null)
              ForwardPickerChip(
                  id: _dms,
                  name: ForwardMessageDialog.labelForwardFilterDirectMessages,
                  icon: Icons.person),
            for (final space in topSpaces)
              ForwardPickerChip(
                  id: space.identifier,
                  name: spaceName(space),
                  avatar: space.avatar,
                  color: space.color),
          ],
        ],
        selectedChip: filter,
        onChipSelected: selectChip,
        breadcrumb: spacePath.map(spaceName).toList(),
        onBreadcrumbSelected: backTo,
        rows: rows,
        emptyText: ForwardMessageDialog.labelNoForwardTargets,
      ),
    );
  }
}
