import 'dart:async';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/utils/dm_shape.dart';
import 'package:flutter/foundation.dart';

/// Vommet ("New room info page"): a room's [DmShape], and the actions that
/// change it. With the experiment off, [of] answers as before: m.direct
/// alone decides.
class DmShapes {
  /// The room's shape now.
  static DmShape of(Room room) {
    if (roomInfoPageEnabled && room is MatrixRoom) return room.dmShape;
    final direct = room.client.getComponent<DirectMessagesComponent>();
    if (direct?.isRoomDirectMessage(room) != true) return DmShape.room;
    return DmShape(DmShapeKind.person,
        partnerId: direct!.getDirectMessagePartnerId(room));
  }

  /// Whether the room is shown as a person (profile tab, presence, call
  /// partner): a direct chat that is still between two people. With the
  /// experiment off, any room in m.direct.
  static bool showsPerson(Room room) => of(room).isPerson;

  /// "Move to Rooms": stop treating [room] as a direct chat (clears it from
  /// m.direct, for every app on the account). The only action besides the
  /// Organize switch that edits m.direct.
  static Future<void> moveToRooms(Room room) async {
    await room.client
        .getComponent<DirectMessagesComponent>()
        ?.setDirectMessage(room, false);
  }

  /// "Name this group": gives a direct chat that became a group its own name
  /// (it then keeps it, even when it's back to two people).
  static Future<void> nameGroup(Room room, String name) =>
      room.setDisplayName(name.trim());

  /// "Invite back": invites the partner who left [room] again.
  static Future<void> inviteBack(Room room) async {
    final partner = of(room).partnerId;
    final invitation = room.client.getComponent<InvitationComponent>();
    if (partner == null || invitation == null) return;
    await invitation.inviteUserToRoom(userId: partner, roomId: room.identifier);
  }
}

/// Vommet ("New room info page"): a room's [DmShape] that follows the room
/// live: members joining and leaving, m.direct changes, the experiment
/// switch. One shared notifier per room ([of]); it listens to the room only
/// while something listens to it. Don't dispose it.
///
/// ```dart
/// ValueListenableBuilder<DmShape>(
///   valueListenable: DmShapeNotifier.of(room),
///   builder: (context, shape, _) => shape.isPerson ? ... : ...,
/// )
/// ```
class DmShapeNotifier extends ChangeNotifier
    implements ValueListenable<DmShape> {
  DmShapeNotifier._(this.room) : _value = DmShapes.of(room);

  static final Expando<DmShapeNotifier> _notifiers = Expando();

  static DmShapeNotifier of(Room room) =>
      _notifiers[room] ??= DmShapeNotifier._(room);

  final Room room;
  DmShape _value;
  final List<StreamSubscription> _subs = [];

  @override
  DmShape get value => _value;

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) _attach();
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _detach();
  }

  @override
  // ignore: must_call_super
  void dispose() {
    // Shared per room: listeners come and go, the notifier stays.
  }

  void _attach() {
    _subs.addAll([
      room.onUpdate.listen((_) => _check()),
      room.onMembersChanged.listen((_) => _check()),
      experimentRoomInfoPage.onChanged.listen((_) => _check()),
    ]);
    _value = DmShapes.of(room);
  }

  void _detach() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  void _check() {
    final next = DmShapes.of(room);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }
}
