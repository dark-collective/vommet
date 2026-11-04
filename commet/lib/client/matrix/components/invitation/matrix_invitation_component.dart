import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/invitation/invite_grouping.dart';
import 'package:commet/client/components/invitation/join_confirmation.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/push_notification/invite_alerts.dart';
import 'package:commet/client/matrix/components/invitation/matrix_invite_preview.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/space_hierarchy/room_batch_task.dart';
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
    // Vommet issue 734: a grouped invite's own Accept takes everything in it.
    if (invitation.isGroup) {
      return acceptGroup(invitation,
          joinSpace: !invitation.spaceJoined,
          roomIds: {for (final r in invitation.groupedRooms) r.roomId});
    }
    await _join(invitation.roomId);
    invitations.remove(invitation);
    _all.remove(invitation.roomId);
    // Vommet: accepting a space's invite offers its rooms too.
    var mx = client.getMatrixClient();
    if (mx.getRoomById(invitation.roomId)?.isSpace ?? false) {
      unawaited(SpaceJoinPicker.offerAfterJoin(client, invitation.roomId));
    }
  }

  /// Vommet: join through the SDK's Room.join(), which marks the room as a
  /// DM (m.direct account data) when the invite says is_direct. The raw
  /// joinRoom call skipped that, so every DM accepted in Vommet showed up
  /// as "Group with <inviter>" instead of under Direct Messages.
  ///
  /// Vommet issue 799: bounded, so a join the server never confirms ends in
  /// [JoinNotConfirmed] instead of loading forever.
  Future<void> _join(String roomId) async {
    var mx = client.getMatrixClient();
    var room = mx.getRoomById(roomId);
    await joinWithConfirmation(
        request: () async {
          if (room != null) {
            await room.join();
          } else {
            await mx.joinRoom(roomId);
          }
        },
        joined: () =>
            mx.getRoomById(roomId)?.membership == matrix.Membership.join,
        syncs: mx.onSync.stream);
  }

  /// Vommet issue 734: accepts a grouped invite: the space (unless
  /// [joinSpace] is false or you're in it already), then the rooms in
  /// [roomIds] in the background with a progress card. Rooms left out stay
  /// pending invites, so the history their inviter sent along still arrives
  /// when they're joined later.
  Future<void> acceptGroup(Invitation head,
      {required bool joinSpace, required Set<String> roomIds}) async {
    final rooms =
        head.groupedRooms.where((r) => roomIds.contains(r.roomId)).toList();
    final spaceName = head.displayName ?? head.roomId;
    if (joinSpace && !head.spaceJoined) {
      await _join(head.roomId);
      _all.remove(head.roomId);
    }
    _busy.addAll(rooms.map((r) => r.roomId));
    _regroup();
    if (rooms.isNotEmpty) {
      startJoinTask(spaceName, [
        for (final r in rooms)
          RoomBatchItem(r.roomId, r.displayName ?? r.roomId)
      ], join: (item) async {
        try {
          await _join(item.roomId);
          _all.remove(item.roomId);
        } finally {
          _busy.remove(item.roomId);
          _regroup();
        }
      });
    }
    if (joinSpace && !head.spaceJoined) {
      unawaited(SpaceJoinPicker.offerAfterJoin(client, head.roomId));
    }
  }

  @override
  Future<void> rejectInvitation(Invitation invitation) async {
    var mx = client.getMatrixClient();
    if (!invitation.isGroup) {
      await mx.leaveRoom(invitation.roomId);
      invitations.remove(invitation);
      _all.remove(invitation.roomId);
      return;
    }
    // Vommet issue 734: "Decline all": the space's invite and its rooms'.
    final ids = [
      if (!invitation.spaceJoined) invitation.roomId,
      for (final r in invitation.groupedRooms) r.roomId,
    ];
    _busy.addAll(ids);
    _regroup();
    Object? firstError;
    StackTrace? firstStack;
    try {
      await _runFew(ids, (id) async {
        try {
          await mx.leaveRoom(id);
          _all.remove(id);
        } catch (e, s) {
          firstError ??= e;
          firstStack ??= s;
        }
      });
    } finally {
      _busy.removeAll(ids);
      _regroup();
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.current);
    }
  }

  /// Runs [action] on [ids], a few at a time.
  static Future<void> _runFew(
      List<String> ids, Future<void> Function(String id) action) async {
    var next = 0;
    Future<void> worker() async {
      while (next < ids.length) {
        await action(ids[next++]);
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
  }

  @override
  void postLoginInit() {
    Log.i("Loading invite list!");
    _updateInviteList();

    // Vommet issue 550: invites that arrive after the first sync alert;
    // the ones already waiting (or brought by a fresh login's first sync)
    // only show on Home and its badge.
    var synced = false;
    client.onSync.listen((_) {
      _updateInviteList(alert: synced);
      synced = true;
    });
  }

  /// Vommet issue 734: every pending invite, grouped or not, in arrival
  /// order. [invitations] shows them grouped.
  final Map<String, Invitation> _all = {};

  /// Invites being accepted or declined right now: hidden meanwhile.
  final Set<String> _busy = {};

  /// Synthetic group entries for spaces you're in, kept so an open invite
  /// page keeps its entry.
  final Map<String, Invitation> _joinedHeads = {};

  /// What the server's hierarchy says each invited space (and its
  /// subspaces) lists, and when we asked.
  final Map<String, Map<String, Set<String>>> _hierarchy = {};
  final Map<String, DateTime> _hierarchyAt = {};
  final Map<String, Future<void>> _hierarchyLoading = {};

  /// New invites waiting to alert, sent together a moment later so a space
  /// and its rooms make one notification.
  final List<String> _alertQueue = [];
  Timer? _alertTimer;

  static const _alertDelay = Duration(seconds: 3);
  static const _hierarchyMaxAge = Duration(seconds: 30);

  void _updateInviteList({bool alert = false}) async {
    var mx = client.getMatrixClient();
    var invitedRooms = mx.rooms.where((element) => element.membership.isInvite);

    // Vommet: drop invites answered elsewhere (another device, or the
    // inviter took it back), so Home and its badge don't keep them.
    final stillInvited = invitedRooms.map((r) => r.id).toSet();
    _all.removeWhere((id, _) => !stillInvited.contains(id));

    final added = <String>[];
    for (var room in invitedRooms) {
      if (_all.containsKey(room.id)) continue;

      var state = room.states[matrix.EventTypes.RoomMember]?[mx.userID];
      var sender = state?.senderId;

      var avatar =
          room.avatar != null ? MatrixMxcImage(room.avatar!, mx) : null;

      _all[room.id] = Invitation(
          roomId: room.id,
          avatar: avatar,
          senderId: sender,
          color: MatrixPeer.hashColor(room.id),
          // Vommet: DM invites read "wants to message you".
          isDirect: state?.content["is_direct"] == true,
          displayName: room.getLocalizedDisplayname());
      added.add(room.id);
    }

    // A new room invite may belong to an invited space we asked about a
    // while ago: ask again (rarely; the answer is cached).
    final newRoom = added.any((id) => !(mx.getRoomById(id)?.isSpace ?? false));
    for (final space in _invitedSpaces()) {
      final at = _hierarchyAt[space];
      if (at == null ||
          (newRoom && DateTime.now().difference(at) > _hierarchyMaxAge)) {
        unawaited(_loadHierarchy(space));
      }
    }
    _hierarchy.removeWhere((id, _) => !_all.containsKey(id));
    _hierarchyAt.removeWhere((id, _) => !_all.containsKey(id));

    _regroup();

    if (alert && added.isNotEmpty) {
      _alertQueue.addAll(added);
      _alertTimer?.cancel();
      _alertTimer = Timer(_alertDelay, _sendAlerts);
    }
  }

  Iterable<String> _invitedSpaces() sync* {
    var mx = client.getMatrixClient();
    for (final id in _all.keys) {
      if (mx.getRoomById(id)?.isSpace ?? false) yield id;
    }
  }

  Future<void> _loadHierarchy(String spaceId) =>
      _hierarchyLoading[spaceId] ??= () async {
        final mx = client.getMatrixClient();
        final children = <String, Set<String>>{};
        try {
          String? from;
          // A few pages are plenty to place the invites we have.
          for (var page = 0; page < 3; page++) {
            final response = await mx.getSpaceHierarchy(spaceId,
                from: from, limit: 100, maxDepth: 3);
            for (final chunk in response.rooms) {
              for (final state in chunk.childrenState) {
                final child = state.stateKey;
                final via = state.content["via"];
                if (state.type != matrix.EventTypes.SpaceChild ||
                    child == null ||
                    via is! List ||
                    via.isEmpty) {
                  continue;
                }
                children.putIfAbsent(chunk.roomId, () => {}).add(child);
              }
            }
            from = response.nextBatch;
            if (from == null) break;
          }
        } catch (e) {
          // The server won't list it for an invitee: group by what the
          // rooms' own invites say (m.space.parent), if anything.
          Log.w("Couldn't load the invited space's rooms: $e");
        } finally {
          _hierarchyAt[spaceId] = DateTime.now();
          _hierarchyLoading.remove(spaceId);
        }
        if (!_all.containsKey(spaceId)) return;
        _hierarchy[spaceId] = children;
        _regroup();
      }();

  /// Rebuilds [invitations] from [_all]: one entry per group, the rest as
  /// they are. Entries that stay keep their object (open pages watch it).
  void _regroup() {
    final mx = client.getMatrixClient();
    final pending = [
      for (final id in _all.keys)
        if (!_busy.contains(id)) id
    ];
    final spaceInvites = <String>{};
    final direct = <String>{};
    final childrenOf = <String, Set<String>>{};
    void link(String parent, String child) =>
        childrenOf.putIfAbsent(parent, () => {}).add(child);

    for (final id in pending) {
      final room = mx.getRoomById(id);
      if (_all[id]!.isDirect) direct.add(id);
      if (room == null) continue;
      if (room.isSpace) spaceInvites.add(id);
      // What the invite itself says about its space, if it says anything.
      for (final parent in room.spaceParents) {
        final parentId = parent.roomId;
        if (parentId != null) link(parentId, id);
      }
    }
    for (final tree in _hierarchy.values) {
      for (final MapEntry(key: parent, value: children) in tree.entries) {
        for (final child in children) {
          link(parent, child);
        }
      }
    }
    final joinedSpaces = <String>[];
    for (final room in mx.rooms) {
      if (room.membership != matrix.Membership.join || !room.isSpace) continue;
      joinedSpaces.add(room.id);
      for (final child in room.spaceChildren) {
        final childId = child.roomId;
        if (childId != null && child.via.isNotEmpty) link(room.id, childId);
      }
    }

    final groups = InviteGrouping.group(
        invites: pending,
        spaceInvites: spaceInvites,
        directInvites: direct,
        childrenOf: childrenOf,
        joinedSpaces: joinedSpaces);
    final member = {
      for (final entry in groups.entries)
        for (final id in entry.value) id: entry.key
    };

    final desired = <Invitation>[];
    final placed = <String>{};
    var changed = false;
    for (final id in pending) {
      final head = member[id] ?? id;
      if (!placed.add(head)) continue;
      final entry = _all[head] ?? _joinedHead(head);
      final rooms = [
        for (final r in groups[head] ?? const <String>[]) _all[r]!
      ];
      if (!_sameRooms(entry.groupedRooms, rooms)) {
        entry.groupedRooms = rooms;
        changed = true;
      }
      desired.add(entry);
    }
    _joinedHeads.removeWhere((id, _) => !placed.contains(id));

    final keep = {for (final e in desired) e.roomId};
    for (final stale
        in invitations.where((i) => !keep.contains(i.roomId)).toList()) {
      invitations.remove(stale);
    }
    for (final entry in desired) {
      if (!invitations.any((i) => identical(i, entry))) {
        invitations.removeWhere((i) => i.roomId == entry.roomId);
        invitations.add(entry);
      }
    }
    // Added and removed entries notify on their own; a group that only
    // gained or lost rooms needs telling.
    if (changed) invitations.update();
  }

  static bool _sameRooms(List<Invitation> a, List<Invitation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].roomId != b[i].roomId) return false;
    }
    return true;
  }

  Invitation _joinedHead(String spaceId) =>
      _joinedHeads.putIfAbsent(spaceId, () {
        final mx = client.getMatrixClient();
        final room = mx.getRoomById(spaceId);
        return Invitation(
            roomId: spaceId,
            spaceJoined: true,
            avatar:
                room?.avatar != null ? MatrixMxcImage(room!.avatar!, mx) : null,
            color: MatrixPeer.hashColor(spaceId),
            displayName: room?.getLocalizedDisplayname() ?? spaceId);
      });

  /// Alerts for the invites queued in [_alertQueue]: one per group (or
  /// plain invite) they landed in.
  Future<void> _sendAlerts() async {
    final ids = List.of(_alertQueue);
    _alertQueue.clear();
    // Wait (briefly) for the spaces' room lists, so the grouping is right.
    await Future.wait(_hierarchyLoading.values)
        .timeout(const Duration(seconds: 5), onTimeout: () => const []);
    _regroup();
    final mx = client.getMatrixClient();
    final fresh = ids.where(_all.containsKey).toSet();
    for (final entry in List.of(invitations)) {
      final newRooms =
          entry.groupedRooms.where((r) => fresh.contains(r.roomId)).toList();
      final headNew = fresh.contains(entry.roomId);
      if (!headNew && newRooms.isEmpty) continue;
      final sender = headNew ? entry.senderId : newRooms.first.senderId;
      if (sender == null) continue;
      final room =
          mx.getRoomById(headNew ? entry.roomId : newRooms.first.roomId);
      final inviterName =
          room?.unsafeGetUserFromMemoryOrFallback(sender).calcDisplayname() ??
              sender;
      final space = entry.displayName ?? entry.roomId;
      String? body;
      if (entry.isGroup) {
        body = headNew
            ? inviteAlertSpaceAndRooms(inviterName, space, newRooms.length)
            : inviteAlertRoomsInSpace(inviterName, space, newRooms.length);
      }
      InviteAlerts.alert(client, headNew ? entry : newRooms.first, inviterName,
          ignoredUsers: mx.ignoredUsers, body: body);
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
