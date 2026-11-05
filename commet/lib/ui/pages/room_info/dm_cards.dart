import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/dm_shape_notifier.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/dm_shape.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet ("New room info page"): the Room info page's direct-chat cards.
/// [DmShapeCard] picks the right one for the room's shape right now (or
/// nothing) and follows it live. Experiment strings stay English.
class DmShapeCard extends StatelessWidget {
  const DmShapeCard(this.room, {super.key});
  final Room room;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DmShape>(
      valueListenable: DmShapeNotifier.of(room),
      builder: (context, shape, _) {
        if (shape.convertedFromDm) return DmStartedAsDirectChatCard(room);
        if (shape.partnerLeft) return DmPartnerLeftCard(room);
        return const SizedBox.shrink();
      },
    );
  }
}

/// "Started as a direct chat with Juniper": a direct chat that now has three
/// or more people. **Name this group** / **Move to Rooms** (clears m.direct).
class DmStartedAsDirectChatCard extends StatelessWidget {
  const DmStartedAsDirectChatCard(this.room, {super.key});
  final Room room;

  static String dmStartedAsDirectChat(String name) =>
      "Started as a direct chat with $name";
  static String get dmStartedAsDirectChatBody =>
      "More people joined, so it shows as a group. It stays in your direct "
      "chats until you move it.";
  static String get dmNameThisGroup => "Name this group";
  static String get dmMoveToRooms => "Move to Rooms";
  static String get dmMoveToRoomsPrompt =>
      "It will show with your rooms instead of your direct chats, in every "
      "app signed in to this account.";
  static String get dmGroupNameHint => "Group name";
  static String get dmSave => "Save";
  static String get dmMove => "Move";
  static String get dmCancel => "Cancel";

  static Future<void> nameThisGroup(BuildContext context, Room room) async {
    final name = await AdaptiveDialog.textPrompt(context,
        title: dmNameThisGroup, hintText: dmGroupNameHint, submitText: dmSave);
    if (name == null || name.trim().isEmpty) return;
    try {
      await DmShapes.nameGroup(room, name);
    } catch (e, s) {
      if (context.mounted) await AdaptiveDialog.showError(context, e, s);
    }
  }

  static Future<void> moveToRooms(BuildContext context, Room room) async {
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: dmMoveToRooms,
        prompt: dmMoveToRoomsPrompt,
        confirmationText: dmMove,
        cancelText: dmCancel);
    if (confirmed != true) return;
    try {
      await DmShapes.moveToRooms(room);
    } catch (e, s) {
      if (context.mounted) await AdaptiveDialog.showError(context, e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner = DmShapes.of(room).partnerId;
    final name = partner == null
        ? room.displayName
        : room.getMemberOrFallback(partner).displayName;
    return DmInfoCard(
      key: const ValueKey("dm-started-as-direct-chat-card"),
      leading: DmGroupAvatars(room),
      title: dmStartedAsDirectChat(name),
      body: dmStartedAsDirectChatBody,
      actions: [
        tiamat.Button(
            text: dmNameThisGroup, onTap: () => nameThisGroup(context, room)),
        tiamat.Button.secondary(
            text: dmMoveToRooms, onTap: () => moveToRooms(context, room)),
      ],
    );
  }
}

/// "Juniper left this chat": a direct chat whose other person left.
/// **Invite back** / **Leave chat**.
class DmPartnerLeftCard extends StatelessWidget {
  const DmPartnerLeftCard(this.room, {super.key});
  final Room room;

  static String dmPartnerLeft(String name) => "$name left this chat";
  static String get dmPartnerLeftBody =>
      "They won't see new messages unless you invite them back.";
  static String get dmInviteBack => "Invite back";
  static String get dmLeaveChat => "Leave chat";

  @override
  Widget build(BuildContext context) {
    final partner = DmShapes.of(room).partnerId;
    final member = partner == null ? null : room.getMemberOrFallback(partner);
    return DmInfoCard(
      key: const ValueKey("dm-partner-left-card"),
      leading: Opacity(
        opacity: 0.5,
        child: tiamat.Avatar(
          radius: 20,
          image: member?.avatar,
          placeholderText: member?.displayName ?? room.displayName,
          placeholderColor: member?.defaultColor ?? room.defaultColor,
        ),
      ),
      title: dmPartnerLeft(member?.displayName ?? room.displayName),
      body: dmPartnerLeftBody,
      actions: [
        if (room.permissions.canInviteUser)
          tiamat.Button(
              text: dmInviteBack,
              onTap: () async {
                try {
                  await DmShapes.inviteBack(room);
                } catch (e, s) {
                  if (context.mounted) {
                    await AdaptiveDialog.showError(context, e, s);
                  }
                }
              }),
        tiamat.Button.danger(
            text: dmLeaveChat, onTap: () => RoomMenu.leave(context, room)),
      ],
    );
  }
}

/// Up to three of a group's other members' pictures, overlapping.
class DmGroupAvatars extends StatelessWidget {
  const DmGroupAvatars(this.room, {this.radius = 16, super.key});
  final Room room;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final own = room.client.self?.identifier;
    final members = room.memberIds.where((id) => id != own).take(3).toList();
    if (members.isEmpty) {
      return tiamat.Avatar(
          radius: radius,
          image: room.avatar,
          placeholderText: room.displayName,
          placeholderColor: room.defaultColor);
    }
    final step = radius * 1.2;
    return SizedBox(
      width: radius * 2 + step * (members.length - 1),
      height: radius * 2,
      child: Stack(children: [
        for (final (i, id) in members.indexed)
          Positioned(
            left: step * i,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    width: 2),
              ),
              child: Builder(builder: (context) {
                final member = room.getMemberOrFallback(id);
                return tiamat.Avatar(
                    radius: radius - 2,
                    image: member.avatar,
                    placeholderText: member.displayName,
                    placeholderColor: member.defaultColor);
              }),
            ),
          ),
      ]),
    );
  }
}

/// The cards' shared look: picture, title, body, buttons.
class DmInfoCard extends StatelessWidget {
  const DmInfoCard(
      {required this.leading,
      required this.title,
      required this.body,
      required this.actions,
      super.key});
  final Widget leading;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: text.titleSmall?.copyWith(color: scheme.onSurface)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(body,
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}
