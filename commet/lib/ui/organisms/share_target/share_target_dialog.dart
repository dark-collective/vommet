import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/room_row_size.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/ui/organisms/forward_message/forward_picker_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/share_intake.dart';
import 'package:commet/utils/share_target_order.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// "Share to…" room picker shown when another app shares into Vommet.
/// Returns the chosen room, or null when dismissed. Vommet issues 795, 807:
/// long-press a room to tick several; they're returned in the order picked.
/// Vommet issue 889: All / Direct messages / space filters like "Forward
/// to…", with the spaces of every account; All keeps the issue 794 order,
/// a filter lists its rooms newest first.
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
  static const _all = "all";
  static const _dms = "dms";

  /// Vommet issue 889: the filter used last ([_dms], or an account id then
  /// the open space chain), so the next share starts there. Kept until the
  /// app closes.
  static List<String> _lastFilter = const [];

  late final List<Room> targets;

  /// Accounts with rooms to share to, in the order their rooms first appear.
  late final List<Client> clients;

  /// Each account's top-level spaces, by account id; accounts without
  /// spaces are left out.
  late final Map<String, List<Space>> topSpaces;

  /// [_all], [_dms], or [spaceChipId] of a top-level space.
  String filter = _all;

  /// The open space and the subspaces opened inside it, top first.
  List<Space> spacePath = [];

  static String spaceChipId(Client client, Space space) =>
      "${client.identifier}/${space.identifier}";
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

  void tap(Room room) => selecting ? toggle(room) : finish([room]);

  void finish(List<Room> rooms) {
    rememberFilter();
    Navigator.of(context).pop(rooms);
  }

  bool isDirectMessage(Room r) =>
      r.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(r) ==
      true;

  Client? get spaceClient => spacePath.isEmpty
      ? null
      : clients.firstWhere(
          (c) => topSpaces[c.identifier]?.contains(spacePath.first) == true);

  void rememberFilter() {
    final client = spaceClient;
    _lastFilter = switch (filter) {
      _all => const [],
      _dms => const [_dms],
      _ => [
          if (client != null) client.identifier,
          ...spacePath.map((s) => s.identifier),
        ],
    };
  }

  void restoreFilter() {
    final last = _lastFilter;
    if (last.isEmpty || topSpaces.isEmpty) return;
    if (last.first == _dms) {
      filter = _dms;
      return;
    }
    var children = topSpaces[last.first] ?? const <Space>[];
    final restored = <Space>[];
    for (final id in last.skip(1)) {
      final space = children.where((s) => s.identifier == id).firstOrNull;
      if (space == null) break;
      restored.add(space);
      children = space.subspaces;
    }
    if (restored.isEmpty) return;
    filter = "${last.first}/${restored.first.identifier}";
    spacePath = restored;
  }

  void selectChip(String? id) {
    setState(() {
      filter = id ?? _all;
      spacePath = [];
      for (final client in clients) {
        for (final space in topSpaces[client.identifier] ?? const <Space>[]) {
          if (spaceChipId(client, space) == filter) spacePath = [space];
        }
      }
      results = filtered();
    });
  }

  void openSubspace(Space space) {
    setState(() {
      spacePath = [...spacePath, space];
      results = filtered();
    });
  }

  void backTo(int index) {
    setState(() {
      spacePath = spacePath.take(index + 1).toList();
      results = filtered();
    });
  }

  /// The rooms the filter allows: All in the issue 794 order, a filter
  /// newest first.
  List<Room> get pool {
    if (filter == _all) return targets;
    final Iterable<Room> rooms;
    if (filter == _dms) {
      rooms = targets.where(isDirectMessage);
    } else if (spacePath.isEmpty) {
      rooms = targets;
    } else {
      final client = spaceClient;
      final inSpace =
          spacePath.last.roomsWithChildren.map((r) => r.identifier).toSet();
      rooms = targets
          .where((r) => r.client == client && inSpace.contains(r.identifier));
    }
    return rooms.toList()
      ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
  }

  List<Room> filtered() => query.isEmpty
      ? pool
      : pool
          .where((r) =>
              r.displayName.toLowerCase().contains(query) ||
              r.identifier.toLowerCase().contains(query))
          .toList();

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
    final rooms = (clientManager?.rooms.toList() ?? <Room>[])
        .where((r) => r.permissions.canSendMessage)
        .toList();
    targets = orderShareTargets(
      rooms,
      lastActivity: (r) => r.lastEventTimestamp,
      isFavorite: (r) => r.isFavorite,
      isDirectMessage: isDirectMessage,
    );
    clients = [];
    for (final room in rooms) {
      if (!clients.contains(room.client)) clients.add(room.client);
    }
    topSpaces = {
      for (final client in clients)
        if (client.spaces.where((s) => s.isTopLevel).toList() case final spaces
            when spaces.isNotEmpty)
          client.identifier: spaces,
    };
    restoreFilter();
    results = filtered();
    super.initState();
  }

  String query = "";

  void setQuery(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      this.query = q;
      results = filtered();
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

  /// Vommet issue 889: the filter chips; empty until some account has a
  /// space, like "Forward to…".
  List<ForwardPickerChip> get chips => [
        if (topSpaces.isNotEmpty) ...[
          ForwardPickerChip(
              id: _all,
              name: ForwardMessageDialog.labelForwardFilterAll,
              icon: Icons.all_inclusive),
          if (targets.any(isDirectMessage))
            ForwardPickerChip(
                id: _dms,
                name: ForwardMessageDialog.labelForwardFilterDirectMessages,
                icon: Icons.person),
        ],
      ];

  /// The account a space chip belongs to, shown before that account's first
  /// space chip; only with more than one account.
  String? accountLabel(Client client) {
    if (clients.length < 2) return null;
    final self = client.self;
    return self == null
        ? client.identifier
        : RedactionScope.of(context).name(self.userName, self.identifier);
  }

  Widget accountTag(String label) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 6, end: 2),
        child: Center(child: tiamat.Text.tiny(label)),
      );

  /// Pills, or folder tabs while the chat list is one Telegram-style list,
  /// so the picker matches the layout style.
  Widget buildChips() {
    final redaction = RedactionScope.of(context);
    String spaceName(Space s) =>
        redaction.roomName(s.displayName, s.identifier);
    final accountStart = <String, String>{};
    for (final client in clients) {
      final spaces = topSpaces[client.identifier];
      final label = accountLabel(client);
      if (spaces == null || label == null) continue;
      accountStart[spaceChipId(client, spaces.first)] = label;
    }

    if (unifiedChatListEnabled) {
      final tabs = [
        for (final chip in chips)
          FolderTab(
              id: chip.id == _all ? null : chip.id,
              label: chip.name,
              icon: chip.icon),
        for (final client in clients)
          for (final space in topSpaces[client.identifier] ?? const <Space>[])
            FolderTab(id: spaceChipId(client, space), label: spaceName(space)),
      ];
      return FolderTabBar(
        tabs: tabs,
        selected: filter == _all ? null : filter,
        onSelect: selectChip,
        wrapTab: (tab, child) => accountStart[tab.id] == null
            ? child
            : Row(mainAxisSize: MainAxisSize.min, children: [
                accountTag(accountStart[tab.id]!),
                child,
              ]),
      );
    }

    Widget pill(String id, String name,
            {IconData? icon, ImageProvider? avatar, Color? color}) =>
        Center(
          child: ChoiceChip(
            mouseCursor: WidgetStateMouseCursor.clickable,
            selected: id == filter,
            showCheckmark: false,
            avatar: icon != null
                ? Icon(icon, size: 18)
                : tiamat.Avatar(
                    radius: 10,
                    image: avatar,
                    placeholderText: name,
                    placeholderColor: color),
            label: Text(name, overflow: TextOverflow.ellipsis),
            onSelected: (_) => selectChip(id),
          ),
        );

    final items = <Widget>[
      for (final chip in chips) pill(chip.id, chip.name, icon: chip.icon),
      for (final client in clients)
        for (final space
            in topSpaces[client.identifier] ?? const <Space>[]) ...[
          if (accountStart[spaceChipId(client, space)] case final label?)
            accountTag(label),
          pill(spaceChipId(client, space), spaceName(space),
              avatar: space.avatar, color: space.color),
        ],
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) => items[index],
      ),
    );
  }

  /// The open space chain; tap a step to go back up.
  Widget buildBreadcrumb() {
    final redaction = RedactionScope.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              for (var i = 0; i < spacePath.length; i++) ...[
                if (i > 0) Icon(Icons.chevron_right, size: 18, color: color),
                TextButton(
                  onPressed: i == spacePath.length - 1 ? null : () => backTo(i),
                  child: Text(redaction.roomName(
                      spacePath[i].displayName, spacePath[i].identifier)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget subspaceRow(Space space) => Padding(
        key: ValueKey("space/${space.identifier}"),
        padding: const EdgeInsets.all(2),
        child: Material(
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(8),
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () => openSubspace(space),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(children: [
                tiamat.Avatar(
                    radius: roomRowSize.shareAvatarRadius,
                    image: space.avatar,
                    placeholderText: space.displayName,
                    placeholderColor: space.color),
                const SizedBox(width: 10),
                Expanded(
                    child: tiamat.Text.label(
                        RedactionScope.of(context)
                            .roomName(space.displayName, space.identifier),
                        overflow: TextOverflow.ellipsis)),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
        ),
      );

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
      if (query.isEmpty && spacePath.isNotEmpty)
        for (final space in spacePath.last.subspaces) subspaceRow(space),
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
          if (topSpaces.isNotEmpty) buildChips(),
          if (spacePath.length > 1) buildBreadcrumb(),
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
                  onPressed: () => finish(selected.values.toList()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
