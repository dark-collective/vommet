import 'package:commet/client/client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/get_or_create_room/room_creator.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: "Replace room": upgrade the room on the server, or point it at a
/// room that already exists, optionally swapping the new room into the
/// room's spaces and inviting its members.
class ReplaceRoomDialog extends StatefulWidget {
  const ReplaceRoomDialog(this.room, {required this.versions, super.key});

  final Room room;
  final Future<RoomVersionOptions?> versions;

  static String replaceRoomTitle(String room) => Intl.message("Replace $room",
      args: [room],
      name: "replaceRoomTitle",
      desc: "Title of the dialog for replacing a room");

  /// Opens the dialog; resolves to the replacement room's id once done.
  static Future<String?> show(BuildContext context, Room room,
      {required Future<RoomVersionOptions?> versions}) {
    return AdaptiveDialog.show<String>(context,
        title: replaceRoomTitle(room.displayName),
        builder: (context) => ReplaceRoomDialog(room, versions: versions));
  }

  @override
  State<ReplaceRoomDialog> createState() => _ReplaceRoomDialogState();
}

class _ReplaceRoomDialogState extends State<ReplaceRoomDialog> {
  RoomReplacementKind kind = RoomReplacementKind.upgrade;
  String? version;
  final List<String> coOwners = [];
  RoomVersionOptions? versionOptions;
  bool versionsLoaded = false;

  Room? target;
  final message = TextEditingController();

  late final List<Space> spaces;
  final Set<Space> swapInto = {};
  late bool inviteMembers;
  late final int otherMembers;

  bool busy = false;

  String replaceRoomExplanation(String room) => Intl.message(
      "$room becomes read-only and shows a link to its replacement. This "
      "can't be undone.",
      args: [room],
      name: "replaceRoomExplanation",
      desc: "Warning at the top of the Replace room dialog");

  String get labelUpgradeToNewRoom => Intl.message("Upgrade to a new room",
      name: "labelUpgradeToNewRoom",
      desc: "Replace room option: the server makes an upgraded copy");

  String get upgradeToNewRoomExplanation => Intl.message(
      "Your server makes a copy with the same name, topic, settings, and power "
      "levels.",
      name: "upgradeToNewRoomExplanation",
      desc: "Explains the 'Upgrade to a new room' option");

  String get labelMoveToExistingRoom =>
      Intl.message("Move to a room that already exists",
          name: "labelMoveToExistingRoom",
          desc: "Replace room option: point the room at another room");

  String get moveToExistingRoomExplanation =>
      Intl.message("Point everyone to another room you choose.",
          name: "moveToExistingRoomExplanation",
          desc: "Explains the 'Move to a room that already exists' option");

  String get labelReplacementRoomVersion => Intl.message("Room version",
      name: "labelReplacementRoomVersion",
      desc: "Label of the room version picker in the Replace room dialog");

  String roomVersionNewest(String version) => Intl.message("$version (newest)",
      args: [version],
      name: "roomVersionNewest",
      desc: "A room version in the picker, marked as the newest stable");

  String roomVersionServerDefault(String version) =>
      Intl.message("$version (server default)",
          args: [version],
          name: "roomVersionServerDefault",
          desc: "A room version in the picker, marked as the server's default");

  String roomVersionUnstable(String version) =>
      Intl.message("$version (unstable)",
          args: [version],
          name: "roomVersionUnstable",
          desc: "A room version in the picker that the server marks unstable");

  String get labelReplacementRoom => Intl.message("Room",
      name: "labelReplacementRoom",
      desc: "Label of the field picking the room that replaces this one");

  String get pickReplacementRoom => Intl.message("Choose a room",
      name: "pickReplacementRoom",
      desc: "Placeholder of the field picking the replacement room");

  String get labelReplacementMessage => Intl.message("Message",
      name: "labelReplacementMessage",
      desc: "Label of the message shown in the replaced room");

  String get replacementMessageHint =>
      Intl.message("This room has been replaced",
          name: "replacementMessageHint",
          desc: "Placeholder (and default) of the replaced room's message");

  String swapIntoSpace(String space, String room) =>
      Intl.message("Swap it into $space in place of $room",
          args: [space, room],
          name: "swapIntoSpace",
          desc: "Checkbox: list the new room in a space where the old one was");

  String inviteMembersToNewRoom(int count) => Intl.plural(count,
      one: "Invite the 1 member to the new room (needed for invite-only "
          "rooms)",
      other: "Invite the $count members to the new room (needed for "
          "invite-only rooms)",
      args: [count],
      name: "inviteMembersToNewRoom",
      desc: "Checkbox: invite the old room's members to the replacement");

  String get promptReplaceRoom => Intl.message("Replace room",
      name: "promptReplaceRoom",
      desc: "Confirm button of the Replace room dialog");

  String get errorReplacingRoom => Intl.message("Couldn't replace the room",
      name: "errorReplacingRoom",
      desc: "Title of the error when replacing a room failed");

  String get errorAfterReplacingRoom =>
      Intl.message("The room was replaced, but not everything worked",
          name: "errorAfterReplacingRoom",
          desc: "Title of the error when the room was replaced but swapping "
              "it into spaces or inviting members failed");

  String invitesFailed(int count) => Intl.plural(count,
      one: "1 member couldn't be invited.",
      other: "$count members couldn't be invited.",
      args: [count],
      name: "invitesFailed",
      desc: "After replacing a room: how many invites failed");

  String get searchReplacementRooms => Intl.message("Search rooms",
      name: "searchReplacementRooms",
      desc: "Search field of the replacement room picker");

  @override
  void initState() {
    final replacement = widget.room.replacement!;
    spaces = replacement.swappableSpaces;
    swapInto.addAll(spaces);
    otherMembers = replacement.otherMemberCount;
    inviteMembers = defaultInviteMembers(widget.room.visibility);
    widget.versions.then((options) {
      if (!mounted) return;
      setState(() {
        versionOptions = options;
        versionsLoaded = true;
        version ??= options?.initialChoice;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  void setKind(RoomReplacementKind? value) {
    if (value == null || busy) return;
    setState(() {
      kind = value;
      // The box starts ticked for an upgrade of a non-public room, and
      // unticked for a room that already exists (it has its own members).
      inviteMembers = value == RoomReplacementKind.upgrade &&
          defaultInviteMembers(widget.room.visibility);
    });
  }

  bool get canConfirm =>
      !busy &&
      switch (kind) {
        RoomReplacementKind.upgrade => version != null,
        RoomReplacementKind.existing => target != null,
      };

  Future<void> confirm() async {
    final replacement = widget.room.replacement!;
    setState(() => busy = true);

    final String newRoomId;
    try {
      if (kind == RoomReplacementKind.upgrade) {
        newRoomId = await replacement.upgrade(version!,
            additionalCreators: supportsCoOwners(version) ? coOwners : null);
      } else {
        newRoomId = target!.identifier;
        await replacement.replaceWith(newRoomId, body: message.text);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Replacing a room failed");
      if (!mounted) return;
      setState(() => busy = false);
      AdaptiveDialog.showError(context, e, s, title: errorReplacingRoom);
      return;
    }

    // The room is replaced now; what follows is best effort.
    final problems = <String>[];
    if (swapInto.isNotEmpty) {
      try {
        await replacement.swapInSpaces(newRoomId, swapInto.toList());
      } catch (e, s) {
        Log.onError(e, s, content: "Swapping a replaced room failed");
        problems.add(e.toString());
      }
    }
    if (inviteMembers && otherMembers > 0) {
      try {
        final failed = await replacement.inviteMembersTo(newRoomId);
        if (failed > 0) problems.add(invitesFailed(failed));
      } catch (e, s) {
        Log.onError(e, s, content: "Inviting to a replacement room failed");
        problems.add(e.toString());
      }
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final outer = navigator.context;
    navigator.pop(newRoomId);
    if (problems.isNotEmpty && outer.mounted) {
      AdaptiveDialog.showError(outer, problems.join("\n"), StackTrace.current,
          title: errorAfterReplacingRoom);
    }
  }

  Future<void> pickTarget() async {
    final picked = await AdaptiveDialog.show<Room>(context,
        title: labelReplacementRoom,
        scrollable: false,
        builder: (context) => _ReplacementRoomPicker(
            room: widget.room, searchHint: searchReplacementRooms));
    if (picked != null && mounted) setState(() => target = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.room.displayName;

    return SizedBox(
      width: 540,
      child: IgnorePointer(
        ignoring: busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(replaceRoomExplanation(name),
                  style: theme.textTheme.bodyMedium),
            ),
            RadioGroup<RoomReplacementKind>(
              groupValue: kind,
              onChanged: setKind,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  option(context, RoomReplacementKind.upgrade,
                      labelUpgradeToNewRoom, upgradeToNewRoomExplanation,
                      extra: versionPicker(context)),
                  option(context, RoomReplacementKind.existing,
                      labelMoveToExistingRoom, moveToExistingRoomExplanation,
                      extra: Column(children: [
                        roomField(context),
                        const SizedBox(height: 8),
                        messageField(context),
                      ])),
                ],
              ),
            ),
            for (final space in spaces)
              check(
                  swapInto.contains(space),
                  swapIntoSpace(space.displayName, name),
                  (value) => setState(() =>
                      value ? swapInto.add(space) : swapInto.remove(space))),
            if (otherMembers > 0)
              check(inviteMembers, inviteMembersToNewRoom(otherMembers),
                  (value) => setState(() => inviteMembers = value)),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: tiamat.Button.danger(
                text: promptReplaceRoom,
                isLoading: busy,
                onTap: canConfirm ? confirm : null,
              ),
            ),
            const SizedBox(height: 5),
            tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget option(BuildContext context, RoomReplacementKind value, String title,
      String subtitle,
      {required Widget extra}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = kind == value;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: selected ? null : () => setKind(value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Radio<RoomReplacementKind>(value: value),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(subtitle,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        if (selected) ...[const SizedBox(height: 8), extra],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget field(BuildContext context, String label, Widget child,
      {IconData? trailing, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Text("$label  ",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            Expanded(child: child),
            if (trailing != null)
              Icon(trailing, size: 18, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  Widget versionPicker(BuildContext context) {
    final options = versionOptions;
    if (!versionsLoaded) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    // No capabilities from the server: offer what it says it defaults to,
    // or the room's own version.
    final choices = options?.all ??
        [if (widget.room.replacement?.roomVersion case final v?) v];
    if (choices.isEmpty) return const SizedBox.shrink();

    String describe(String v) {
      if (options == null) return v;
      if (v == options.newestStable) return roomVersionNewest(v);
      if (v == options.defaultVersion) return roomVersionServerDefault(v);
      if (options.unstable.contains(v)) return roomVersionUnstable(v);
      return v;
    }

    version ??= choices.first;
    final picker = field(
      context,
      labelReplacementRoomVersion,
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: version,
          items: [
            for (final v in choices)
              DropdownMenuItem(value: v, child: Text(describe(v))),
          ],
          onChanged: (v) => setState(() => version = v),
        ),
      ),
    );
    if (!supportsCoOwners(version)) return picker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        picker,
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CoOwnersEditor(
              coOwners: coOwners, onChanged: () => setState(() {})),
        ),
      ],
    );
  }

  /// Room v12 and newer have co-owners (`additional_creators`).
  static bool supportsCoOwners(String? version) =>
      (int.tryParse(version ?? "") ?? 0) >= 12;

  Widget roomField(BuildContext context) {
    final theme = Theme.of(context);
    final picked = target;
    return field(
      context,
      labelReplacementRoom,
      Text(picked == null ? pickReplacementRoom : roomLabel(picked),
          overflow: TextOverflow.ellipsis,
          style: picked == null
              ? theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)
              : theme.textTheme.bodyMedium),
      trailing: Icons.search,
      onTap: pickTarget,
    );
  }

  Widget messageField(BuildContext context) {
    return field(
      context,
      labelReplacementMessage,
      TextField(
        controller: message,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: replacementMessageHint,
        ),
      ),
    );
  }

  Widget check(bool value, String text, void Function(bool value) onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Flexible(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

/// "#name · Space" for the picker and the picked room.
String roomLabel(Room room) {
  for (final space in room.client.spaces) {
    if (space.containsRoom(room.identifier)) {
      return "${room.displayName} · ${space.displayName}";
    }
  }
  return room.displayName;
}

/// Rooms the user is in that can take over: not this one, not replaced or
/// banned themselves.
class _ReplacementRoomPicker extends StatefulWidget {
  const _ReplacementRoomPicker({required this.room, required this.searchHint});

  final Room room;
  final String searchHint;

  @override
  State<_ReplacementRoomPicker> createState() => _ReplacementRoomPickerState();
}

class _ReplacementRoomPickerState extends State<_ReplacementRoomPicker> {
  late final List<Room> candidates;
  String query = "";

  @override
  void initState() {
    candidates = widget.room.client.rooms
        .where((r) =>
            r.identifier != widget.room.identifier &&
            !r.isBanned &&
            r.replacement?.tombstone == null)
        .toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final shown = candidates
        .where((r) => roomMatchesQuery(r.displayName, r.identifier, query))
        .toList();
    return SizedBox(
      width: 480,
      height: 420,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.searchHint,
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final room = shown[index];
                return ListTile(
                  leading: tiamat.Avatar(
                      radius: 16,
                      image: room.avatar,
                      placeholderText: room.displayName,
                      placeholderColor: room.defaultColor),
                  title: Text(roomLabel(room), overflow: TextOverflow.ellipsis),
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
