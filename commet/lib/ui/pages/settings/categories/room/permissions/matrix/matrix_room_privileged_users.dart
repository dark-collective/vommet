// Vommet: "Privileged users" section of the room/space Permissions page, like
// Element's Roles & Permissions: everyone with a non-default power level,
// change or reset their level, and add someone from the member list.
import 'dart:async';

import 'package:commet/client/matrix/matrix_member.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_power_levels.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_page.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart' show Panel, TileType;

/// One person shown in the privileged users list or the add dialog.
class PowerLevelPerson {
  const PowerLevelPerson({
    required this.userId,
    required this.displayName,
    required this.level,
    required this.color,
    this.avatar,
    this.isCreator = false,
  });
  final String userId;
  final String displayName;
  final int level;
  final Color color;
  final ImageProvider? avatar;
  final bool isCreator;
}

/// Name and icon for a level: an exact role match, else "Custom".
(String, IconData?) describePowerLevel(
    int level, bool isCreator, List<MatrixRoomRoleEntry> roles) {
  if (isCreator) return (PrivilegedUsersView.labelCreator, Icons.local_police);
  for (final r in roles) {
    if (r.powerlevel == level) return (r.name, r.icon);
  }
  return (PrivilegedUsersView.labelCustomLevel, Icons.tune);
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar(this.person);
  final PowerLevelPerson person;

  @override
  Widget build(BuildContext context) {
    final name = person.displayName.isNotEmpty
        ? person.displayName
        : person.userId.replaceFirst("@", "");
    return tiamat.Avatar.small(
      image: person.avatar,
      placeholderText: name.isNotEmpty ? name.characters.first : "?",
      placeholderColor: person.color,
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill(this.person, this.roles);
  final PowerLevelPerson person;
  final List<MatrixRoomRoleEntry> roles;

  @override
  Widget build(BuildContext context) {
    final (name, icon) =
        describePowerLevel(person.level, person.isCreator, roles);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 6, 0),
              child: Icon(icon, size: 16, color: cs.onSurface),
            ),
          tiamat.Text.labelEmphasised(name),
          if (!person.isCreator)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 0, 0),
              child: tiamat.Text.tiny("${person.level}", color: cs.onSurface),
            ),
        ],
      ),
    );
  }
}

/// The privileged users list. Pure view: fed with data and callbacks.
class PrivilegedUsersView extends StatelessWidget {
  const PrivilegedUsersView({
    super.key,
    required this.people,
    required this.roles,
    required this.ownUserId,
    required this.ownLevel,
    required this.canEdit,
    this.onEdit,
    this.onAdd,
  });

  final List<PowerLevelPerson> people;
  final List<MatrixRoomRoleEntry> roles;
  final String ownUserId;
  final int ownLevel;
  final bool canEdit;
  final void Function(PowerLevelPerson person)? onEdit;
  final void Function()? onAdd;

  static String get labelPrivilegedUsers => Intl.message(
        "Privileged users",
        name: "labelPrivilegedUsers",
        desc:
            "Header of the room permissions section listing people with a role above or below the default",
      );

  static String get labelPrivilegedUsersEmpty => Intl.message(
        "Everyone here has the default role.",
        name: "labelPrivilegedUsersEmpty",
        desc: "Shown in the privileged users section when nobody has a role",
      );

  static String get labelAddPrivilegedUser => Intl.message(
        "Add privileged user",
        name: "labelAddPrivilegedUser",
        desc: "Button to give a room member a role",
      );

  static String get labelCreator => Intl.message(
        "Creator",
        name: "labelPowerLevelCreator",
        desc:
            "Role shown for the creator of a room; creators always have full permissions",
      );

  static String get labelCustomLevel => Intl.message(
        "Custom",
        name: "labelPowerLevelCustom",
        desc:
            "Role shown for a power level that matches none of the named roles",
      );

  static String get labelYou => Intl.message(
        "You",
        name: "labelPrivilegedUserYou",
        desc: "Small tag next to your own name in the privileged users list",
      );

  static String get labelChangeRole => Intl.message(
        "Change role",
        name: "labelPrivilegedUserChangeRole",
        desc: "Tooltip of the button to change a privileged user's role",
      );

  bool _editable(PowerLevelPerson p) => canChangeUserLevel(
        canEditPowerLevels: canEdit,
        ownLevel: ownLevel,
        targetLevel: p.level,
        isSelf: p.userId == ownUserId,
        isTargetCreator: p.isCreator,
      );

  @override
  Widget build(BuildContext context) {
    return Panel(
      header: labelPrivilegedUsers,
      mode: TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: tiamat.Text.labelLow(labelPrivilegedUsersEmpty),
            ),
          for (final p in people) _row(context, p),
          if (canEdit && onAdd != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: tiamat.Button.secondary(
                  text: labelAddPrivilegedUser,
                  onTap: onAdd,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, PowerLevelPerson p) {
    final editable = _editable(p);
    final isSelf = p.userId == ownUserId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          _PersonAvatar(p),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: tiamat.Text.labelEmphasised(
                        p.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 0, 0),
                        child: tiamat.Text.tiny(labelYou,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                  ],
                ),
                tiamat.Text.labelLow(p.userId, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LevelPill(p, roles),
          SizedBox(
            width: 40,
            child: editable && onEdit != null
                ? tiamat.Tooltip(
                    text: labelChangeRole,
                    child: tiamat.IconButton(
                      icon: Icons.edit,
                      size: 18,
                      onPressed: () => onEdit!(p),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// Role list used both to change someone's level and in the add dialog.
/// Roles above [ownLevel] are shown but locked; a custom level can be typed.
class PowerLevelPickerView extends StatefulWidget {
  const PowerLevelPickerView({
    super.key,
    required this.roles,
    required this.ownLevel,
    required this.onPicked,
    this.currentLevel,
    this.allowReset = false,
    this.usersDefault = 0,
  });
  final List<MatrixRoomRoleEntry> roles;
  final int ownLevel;
  final int? currentLevel;
  final bool allowReset;
  final int usersDefault;

  /// null = reset to the room's default (remove from `users`).
  final void Function(int? level) onPicked;

  static String get labelAboveYourLevel => Intl.message(
        "Above your own role",
        name: "labelPowerLevelAboveYourLevel",
        desc:
            "Shown on a role you can't give because it is higher than your own",
      );

  static String get labelCustomLevelHint => Intl.message(
        "Custom level",
        name: "labelPowerLevelCustomHint",
        desc: "Placeholder of the field to type a custom power level number",
      );

  static String get labelSetCustom => Intl.message(
        "Set",
        name: "labelPowerLevelSetCustom",
        desc: "Button to apply a typed custom power level",
      );

  static String labelResetToDefault(int level) => Intl.message(
        "Reset to default ($level)",
        name: "labelResetToDefault",
        args: [level],
        desc:
            "Button to remove a user's role so they get the room's default power level",
      );

  @override
  State<PowerLevelPickerView> createState() => _PowerLevelPickerViewState();
}

class _PowerLevelPickerViewState extends State<PowerLevelPickerView> {
  final controller = TextEditingController();
  String? customError;

  static String customTooHigh(int level) => Intl.message(
        "You can't set a level above your own ($level)",
        name: "labelPowerLevelCustomTooHigh",
        args: [level],
        desc: "Error under the custom power level field",
      );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submitCustom() {
    final value = int.tryParse(controller.text.trim());
    if (value == null) return;
    if (!canAssignLevel(ownLevel: widget.ownLevel, newLevel: value)) {
      setState(() => customError = customTooHigh(widget.ownLevel));
      return;
    }
    widget.onPicked(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final role in widget.roles) _roleRow(context, role),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r"^-?\d*"))
                  ],
                  onSubmitted: (_) => submitCustom(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: PowerLevelPickerView.labelCustomLevelHint,
                    errorText: customError,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              tiamat.Button.secondary(
                text: PowerLevelPickerView.labelSetCustom,
                onTap: submitCustom,
              ),
            ],
          ),
        ),
        if (widget.allowReset)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: tiamat.TextButton(
                PowerLevelPickerView.labelResetToDefault(widget.usersDefault),
                icon: Icons.restart_alt,
                textColor: cs.error,
                iconColor: cs.error,
                onTap: () => widget.onPicked(null),
              ),
            ),
          ),
      ],
    );
  }

  Widget _roleRow(BuildContext context, MatrixRoomRoleEntry role) {
    final cs = Theme.of(context).colorScheme;
    final allowed =
        canAssignLevel(ownLevel: widget.ownLevel, newLevel: role.powerlevel);
    final current = role.powerlevel == widget.currentLevel;
    final fg = allowed ? cs.onSurface : cs.onSurface.withAlpha(110);
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(8),
      onTap:
          allowed && !current ? () => widget.onPicked(role.powerlevel) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: current ? cs.primary.withAlpha(40) : null,
        ),
        child: Row(
          children: [
            Icon(role.icon, color: fg, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelEmphasised(role.name, color: fg),
                  if (!allowed)
                    tiamat.Text.labelLow(
                        PowerLevelPickerView.labelAboveYourLevel),
                ],
              ),
            ),
            tiamat.Text.tiny("${role.powerlevel}", color: fg),
            SizedBox(
              width: 28,
              child: current
                  ? Icon(Icons.check, color: cs.primary, size: 18)
                  : (!allowed
                      ? Icon(Icons.lock_outline, color: fg, size: 16)
                      : null),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog body: pick a member, pick a role, add. Pure view.
class AddPrivilegedUserView extends StatefulWidget {
  const AddPrivilegedUserView({
    super.key,
    required this.candidates,
    required this.roles,
    required this.ownLevel,
    required this.onSubmit,
    this.initialSelection,
    this.initialLevel,
  });
  final List<PowerLevelPerson> candidates;
  final List<MatrixRoomRoleEntry> roles;
  final int ownLevel;
  final void Function(String userId, int level) onSubmit;
  final String? initialSelection;
  final int? initialLevel;

  static String get labelSearchMembers => Intl.message(
        "Search members",
        name: "labelAddPrivilegedUserSearch",
        desc:
            "Placeholder of the member search field in the add privileged user dialog",
      );

  static String get labelNoMembers => Intl.message(
        "No matching members without a role",
        name: "labelAddPrivilegedUserNoMembers",
        desc:
            "Shown when the member search in the add privileged user dialog finds nobody",
      );

  static String get labelRole => Intl.message(
        "Role",
        name: "labelAddPrivilegedUserRole",
        desc:
            "Heading above the role choices in the add privileged user dialog",
      );

  static String get labelAdd => Intl.message(
        "Add",
        name: "labelAddPrivilegedUserSubmit",
        desc: "Button that gives the chosen member the chosen role",
      );

  @override
  State<AddPrivilegedUserView> createState() => _AddPrivilegedUserViewState();
}

class _AddPrivilegedUserViewState extends State<AddPrivilegedUserView> {
  String query = "";
  String? selected;
  int? level;

  @override
  void initState() {
    super.initState();
    selected = widget.initialSelection;
    level = widget.initialLevel;
  }

  List<PowerLevelPerson> get filtered {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return widget.candidates;
    return widget.candidates
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            c.userId.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = filtered;
    final assignable = widget.roles
        .where((r) =>
            r.powerlevel > 0 &&
            canAssignLevel(ownLevel: widget.ownLevel, newLevel: r.powerlevel))
        .toList();
    return SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: AddPrivilegedUserView.labelSearchMembers,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                        child: tiamat.Text.labelLow(
                            AddPrivilegedUserView.labelNoMembers)),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in list)
                        InkWell(
                          mouseCursor: WidgetStateMouseCursor.clickable,
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => selected = c.userId),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: selected == c.userId
                                  ? cs.primary.withAlpha(40)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                _PersonAvatar(c),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      tiamat.Text.labelEmphasised(c.displayName,
                                          overflow: TextOverflow.ellipsis),
                                      tiamat.Text.labelLow(c.userId,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                if (selected == c.userId)
                                  Icon(Icons.check_circle,
                                      color: cs.primary, size: 20),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          tiamat.Text.labelLow(AddPrivilegedUserView.labelRole),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in assignable)
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  avatar: Icon(r.icon, size: 16),
                  label: Text("${r.name} · ${r.powerlevel}"),
                  selected: level == r.powerlevel,
                  onSelected: (_) => setState(() => level = r.powerlevel),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: tiamat.Button(
              text: AddPrivilegedUserView.labelAdd,
              onTap: selected != null && level != null
                  ? () => widget.onSubmit(selected!, level!)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live section: reads the room's power levels, opens the dialogs and sends
/// the changes.
class MatrixRoomPrivilegedUsers extends StatefulWidget {
  const MatrixRoomPrivilegedUsers(this.room, {super.key, required this.roles});
  final matrix.Room room;
  final List<MatrixRoomRoleEntry> roles;

  @override
  State<MatrixRoomPrivilegedUsers> createState() =>
      _MatrixRoomPrivilegedUsersState();
}

class _MatrixRoomPrivilegedUsersState extends State<MatrixRoomPrivilegedUsers> {
  StreamSubscription? sub;

  static String labelChangeRoleFor(String name) => Intl.message(
        "Role for $name",
        name: "labelPrivilegedUserRoleFor",
        args: [name],
        desc: "Title of the dialog to change a user's role",
      );

  static String get labelDemoteSelfTitle => Intl.message(
        "Lower your own role?",
        name: "labelDemoteSelfTitle",
        desc: "Title of the confirmation before lowering your own power level",
      );

  static String get labelDemoteSelfPrompt => Intl.message(
        "You won't be able to undo this. If you're the last person with this role, nobody will be able to get it back.",
        name: "labelDemoteSelfPrompt",
        desc: "Body of the confirmation before lowering your own power level",
      );

  static String get labelDemoteSelfConfirm => Intl.message(
        "Lower my role",
        name: "labelDemoteSelfConfirm",
        desc: "Confirm button for lowering your own power level",
      );

  @override
  void initState() {
    super.initState();
    sub = widget.room.onUpdate.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Map<String, Object?> get content =>
      widget.room.getState(matrix.EventTypes.RoomPowerLevels)?.content ?? {};

  Set<String> get creators {
    final version = int.tryParse(widget.room.roomVersion ?? "") ?? 0;
    return version >= 12 ? widget.room.creatorUserIds : {};
  }

  PowerLevelPerson person(String userId, int level, {bool isCreator = false}) {
    final user = widget.room.unsafeGetUserFromMemoryOrFallback(userId);
    final avatarUrl = user.avatarUrl;
    return PowerLevelPerson(
      userId: userId,
      displayName: user.calcDisplayname(),
      level: level,
      isCreator: isCreator,
      color: MatrixMember.hashColor(userId),
      avatar: avatarUrl == null
          ? null
          : MatrixMxcImage(avatarUrl, widget.room.client,
              doThumbnail: true,
              autoLoadFullRes: false,
              doFullres: false,
              thumbnailHeight: 86),
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = [
      for (final u in privilegedUsers(content, creators: creators))
        person(u.userId, u.level, isCreator: u.isCreator)
    ];
    return PrivilegedUsersView(
      people: people,
      roles: widget.roles,
      ownUserId: widget.room.client.userID ?? "",
      ownLevel: widget.room.ownPowerLevel,
      canEdit: widget.room.canChangePowerLevel,
      onEdit: edit,
      onAdd: add,
    );
  }

  Future<void> edit(PowerLevelPerson p) async {
    final usersDefault = resolvePermissionLevel(content, key: "users_default");
    final picked = await AdaptiveDialog.show<_Pick>(
      context,
      title: labelChangeRoleFor(p.displayName),
      builder: (dialogContext) => SizedBox(
        width: 400,
        child: PowerLevelPickerView(
          roles: widget.roles,
          ownLevel: widget.room.ownPowerLevel,
          currentLevel: p.level,
          allowReset: true,
          usersDefault: usersDefault,
          onPicked: (level) => Navigator.of(dialogContext).pop(_Pick(level)),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await setLevel(p.userId, picked.level, currentLevel: p.level);
  }

  Future<void> add() async {
    await ErrorUtils.tryRun(context, () async {
      await widget.room.requestParticipants([matrix.Membership.join], true);
    });
    if (!mounted) return;

    final own = widget.room.client.userID;
    final usersDefault = resolvePermissionLevel(content, key: "users_default");
    final privileged = {
      for (final u in privilegedUsers(content, creators: creators)) u.userId
    };
    final candidates = widget.room
        .getParticipants([matrix.Membership.join])
        .where((u) => u.id != own && !privileged.contains(u.id))
        .map((u) => person(u.id, usersDefault))
        .toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    final result = await AdaptiveDialog.show<(String, int)>(
      context,
      title: PrivilegedUsersView.labelAddPrivilegedUser,
      scrollable: false,
      builder: (dialogContext) => AddPrivilegedUserView(
        candidates: candidates,
        roles: widget.roles,
        ownLevel: widget.room.ownPowerLevel,
        onSubmit: (userId, level) =>
            Navigator.of(dialogContext).pop((userId, level)),
      ),
    );
    if (result == null || !mounted) return;
    await setLevel(result.$1, result.$2, currentLevel: usersDefault);
  }

  Future<void> setLevel(String userId, int? level,
      {required int currentLevel}) async {
    final room = widget.room;
    final isSelf = userId == room.client.userID;
    final newLevel =
        level ?? resolvePermissionLevel(content, key: "users_default");
    if (!canAssignLevel(ownLevel: room.ownPowerLevel, newLevel: newLevel)) {
      return;
    }
    if (isSelfDemotion(
        isSelf: isSelf, currentLevel: currentLevel, newLevel: newLevel)) {
      final ok = await AdaptiveDialog.confirmation(
        context,
        title: labelDemoteSelfTitle,
        prompt: labelDemoteSelfPrompt,
        confirmationText: labelDemoteSelfConfirm,
        dangerous: true,
      );
      if (ok != true || !mounted) return;
    }

    await ErrorUtils.tryRun(context, () async {
      await room.client.setRoomStateWithKey(
        room.id,
        matrix.EventTypes.RoomPowerLevels,
        "",
        powerLevelsWithUserLevel(content, userId, level),
      );
    });
  }
}

class _Pick {
  const _Pick(this.level);
  final int? level;
}
