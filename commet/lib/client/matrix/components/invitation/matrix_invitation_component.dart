import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/components/invitation/matrix_invite_preview.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/ui/organisms/space_join_picker/space_join_picker.dart';
import 'dart:async';
import 'package:matrix/matrix.dart' as matrix;

class MatrixInvitationComponent
    implements InvitationComponent<MatrixClient>, NeedsPostLoginInit {
  @override
  final MatrixClient client;

  @override
  NotifyingList<Invitation> invitations = NotifyingList.empty(growable: true);

  MatrixInvitationComponent(this.client);

  @override
  Future<void> acceptInvitation(Invitation invitation) async {
    var mx = client.getMatrixClient();
    // Vommet: join through the SDK's Room.join(), which marks the room as a
    // DM (m.direct account data) when the invite says is_direct. The raw
    // joinRoom call skipped that, so every DM accepted in Vommet showed up
    // as "Group with <inviter>" instead of under Direct Messages.
    var room = mx.getRoomById(invitation.roomId);
    if (room != null) {
      await room.join();
    } else {
      await mx.joinRoom(invitation.roomId);
    }
    invitations.remove(invitation);
    // Vommet: accepting a space's invite offers its rooms too.
    if (mx.getRoomById(invitation.roomId)?.isSpace ?? false) {
      unawaited(SpaceJoinPicker.offerAfterJoin(client, invitation.roomId));
    }
  }

  @override
  Future<void> rejectInvitation(Invitation invitation) async {
    var mx = client.getMatrixClient();
    await mx.leaveRoom(invitation.roomId);
    invitations.remove(invitation);
  }

  @override
  void postLoginInit() {
    Log.i("Loading invite list!");
    _updateInviteList();

    client.onSync.listen((_) => _updateInviteList());
  }

  void _updateInviteList() async {
    var mx = client.getMatrixClient();
    var invitedRooms = mx.rooms.where((element) => element.membership.isInvite);

    for (var room in invitedRooms) {
      if (invitations
          .where((element) => element.roomId == room.id)
          .isNotEmpty) {
        continue;
      }

      var state = room.states[matrix.EventTypes.RoomMember]?[mx.userID];
      var sender = state?.senderId;

      var avatar =
          room.avatar != null ? MatrixMxcImage(room.avatar!, mx) : null;

      var entry = Invitation(
          roomId: room.id,
          avatar: avatar,
          senderId: sender,
          color: MatrixPeer.hashColor(room.id),
          // Vommet: DM invites read "wants to message you".
          isDirect: state?.content["is_direct"] == true,
          displayName: room.getLocalizedDisplayname());

      invitations.add(entry);
    }
  }

  @override
  Future<void> inviteUserToRoom(
      {required String userId, required String roomId}) {
    var mx = client.getMatrixClient();
    return mx.inviteUser(roomId, userId);
  }

  @override
  Future<List<Profile>> searchUsers(String term) async {
    var mx = client.getMatrixClient();
    var result = await mx.searchUserDirectory(term);

    var finalResult =
        result.results.map((e) => MatrixProfile(client, e)).toList();
    if (term.isValidMatrixId && !finalResult.any((i) => i.identifier == term)) {
      finalResult = [
        MatrixProfile(
            client, matrix.Profile(userId: term, displayName: term.localpart)),
        ...finalResult
      ];
    }

    return finalResult;
  }

  // Vommet: read every invite-permission slot the server honours, and keep
  // other apps' rules when writing (InvitePermissionConfig).
  @override
  bool get allowInvitations => !MatrixInvitePreview(client).config.blocksAll;

  @override
  Future<void> setInvitationsAllowed(bool allowed) =>
      MatrixInvitePreview(client).setBlocksAll(!allowed);
}
