import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/dm_shape_notifier.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/send_invitation.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

enum DmAddPeopleChoice { newGroup, addHere }

/// Vommet ("New room info page"): inviting someone into a direct chat asks
/// first: start a new group with the person and the new people (keeps this
/// chat private), or add them here, warning when they could read earlier
/// messages. Experiment strings stay English.
class DmAddPeopleSheet extends StatelessWidget {
  const DmAddPeopleSheet({required this.room, super.key});
  final Room room;

  static String get dmAddPeopleTitle => "Add people";
  static String get dmAddPeopleNewGroup => "Start a new group";
  static String get dmAddPeopleRecommended => "Recommended";
  static String dmAddPeopleNewGroupBody(String name) =>
      "Keeps this chat private. A new group with $name and the people you "
      "add.";
  static String get dmAddPeopleAddHere => "Add here";
  static String get dmAddPeopleAddHereBody => "Turns this chat into a group.";
  static String get dmAddPeopleHistoryWarning =>
      "People you add here can read earlier messages in this chat.";

  /// Invites into [room]: a direct chat shows the sheet first; any other
  /// room (or the experiment off) goes straight to [addHere].
  static Future<void> inviteOr(
      BuildContext context, Room room, void Function() addHere) async {
    if (!roomInfoPageEnabled || !DmShapes.of(room).isPerson) {
      addHere();
      return;
    }
    final choice = await AdaptiveDialog.show<DmAddPeopleChoice>(context,
        title: dmAddPeopleTitle, builder: (_) => DmAddPeopleSheet(room: room));
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case DmAddPeopleChoice.newGroup:
        await startNewGroup(context, room);
      case DmAddPeopleChoice.addHere:
        addHere();
    }
  }

  /// Whether people invited now could read the messages sent before they
  /// join (history visibility "shared" or "world_readable").
  static bool historyVisibleToNewPeople(Room room) {
    if (room is! MatrixRoom) return false;
    final visibility = room.matrixRoom.historyVisibility;
    return visibility == matrix.HistoryVisibility.shared ||
        visibility == matrix.HistoryVisibility.worldReadable;
  }

  /// Picks someone, then makes a new private group (encrypted like [room])
  /// with [room]'s partner and them, and opens it.
  static Future<void> startNewGroup(BuildContext context, Room room) async {
    final invitation = room.client.getComponent<InvitationComponent>();
    if (invitation == null) return;
    final partner = DmShapes.of(room).partnerId;
    final own = room.client.self?.identifier;
    String? picked;
    await AdaptiveDialog.show(context,
        title: dmAddPeopleNewGroup,
        builder: (_) => SendInvitationWidget(room.client, invitation,
            existingMembers: [
              if (partner != null) partner,
              if (own != null) own,
            ],
            onUserPicked: (userId) async => picked = userId));
    final person = picked;
    if (person == null || !context.mounted) return;
    try {
      final group = await room.client.createRoom(CreateRoomArgs(
          visibility: RoomVisibilityPrivate(), enableE2EE: room.isE2EE));
      for (final userId in {if (partner != null) partner, person}) {
        if (userId == own) continue;
        await invitation.inviteUserToRoom(
            userId: userId, roomId: group.identifier);
      }
      EventBus.doOpenRoom(group.identifier, clientId: room.client.identifier);
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
    final warn = historyVisibleToNewPeople(room);
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _option(context,
              key: const ValueKey("dm-add-people-new-group"),
              icon: Icons.group_add_outlined,
              title: dmAddPeopleNewGroup,
              badge: dmAddPeopleRecommended,
              body: dmAddPeopleNewGroupBody(name),
              choice: DmAddPeopleChoice.newGroup),
          const SizedBox(height: 8),
          _option(context,
              key: const ValueKey("dm-add-people-add-here"),
              icon: Icons.person_add_alt_1,
              title: dmAddPeopleAddHere,
              body: dmAddPeopleAddHereBody,
              warning: warn ? dmAddPeopleHistoryWarning : null,
              choice: DmAddPeopleChoice.addHere),
        ],
      ),
    );
  }

  Widget _option(BuildContext context,
      {required Key key,
      required IconData icon,
      required String title,
      required String body,
      required DmAddPeopleChoice choice,
      String? badge,
      String? warning}) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      key: key,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => Navigator.of(context).pop(choice),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 24, color: scheme.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(title,
                          style: text.titleSmall
                              ?.copyWith(color: scheme.onSurface)),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(badge,
                              style: text.labelSmall
                                  ?.copyWith(color: scheme.onPrimaryContainer)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(body,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  if (warning != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      key: const ValueKey("dm-add-people-history-warning"),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(warning,
                              style: text.bodySmall
                                  ?.copyWith(color: scheme.error)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
