import 'dart:async';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/client/matrix/matrix_space_hierarchy.dart';
import 'package:commet/ui/organisms/invitation_view/direct_invite_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/space_invite_dialog.dart';
import 'package:commet/ui/organisms/share_history/share_history.dart';
import 'package:commet/ui/organisms/space_join_picker/leave_space_dialog.dart';
import 'package:commet/utils/invitations/invitation_batch.dart';
import 'package:commet/utils/space_hierarchy/invite_plan.dart';
import 'package:commet/utils/space_hierarchy/leave_plan.dart';
import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix.dart' show MatrixIdExtension;

class InvitePerson {
  const InvitePerson(
    this.id,
    this.name, {
    this.avatar,
    this.color = Colors.indigo,
  });
  factory InvitePerson.profile(Profile p) => InvitePerson(
        p.identifier,
        p.displayName,
        avatar: p.avatar,
        color: p.defaultColor,
      );
  final String id;
  final String name;
  final ImageProvider? avatar;
  final Color color;
}

class InvitePlace {
  const InvitePlace(
    this.id,
    this.name, {
    this.isSpace = false,
    this.ancestors = const [],
    this.path = '',
  });
  final String id;
  final String name;
  final bool isSpace;
  final List<String> ancestors;
  final String path;
}

class InviteAccess {
  const InviteAccess({
    this.membership,
    required this.history,
    required this.canInvite,
    this.canGrant = false,
  });
  final String? membership;
  final InviteHistory history;
  final bool canInvite;
  final bool canGrant;
  bool get existing => membership == 'join' || membership == 'invite';
  bool get invitable => canInvite && !existing && membership != 'ban';
  String get label => membership == 'join'
      ? 'Already joined'
      : membership == 'invite'
          ? 'Invite pending'
          : membership == 'ban'
              ? 'Banned'
              : !canInvite
                  ? 'Cannot invite'
                  : 'Will invite';
  static String historyLabel(InviteHistory h) => switch (h) {
        InviteHistory.included => 'History included',
        InviteHistory.newMessagesOnly => 'New messages only',
        InviteHistory.notEncrypted => 'Not encrypted',
        InviteHistory.space => 'Space',
        InviteHistory.cannotInvite => 'Cannot invite',
        InviteHistory.alreadyMember => 'Already joined or invited',
      };
}

/// UI boundary: tests and captures supply fakes without a Matrix connection.
abstract class BatchInviteSource {
  String get accountId;
  String get rootId;
  String get rootName;
  String? get selfId;
  bool get isSpace;
  bool get truncated => false;
  List<InvitePerson> get recommendations;
  InvitePerson person(String id);
  bool validId(String value) =>
      value.startsWith('@') &&
      value.indexOf(':') > 1 &&
      value.isValidMatrixId &&
      !RegExp(r'\s').hasMatch(value);
  Future<List<InvitePerson>> search(String value);
  Future<List<InvitePlace>> loadPlaces();
  InviteAccess access(String userId, String roomId);
  bool firstContact(String id);
  Future<void> refresh(
    List<String> users,
    List<String> rooms, {
    bool Function()? canceled,
  });
  InvitationBatchTask task(List<BatchInviteItem> items);
}

class HistoryShareNeedsAttention implements Exception {
  const HistoryShareNeedsAttention(this.message);
  final String message;
}

class ClientBatchInviteSource extends BatchInviteSource {
  ClientBatchInviteSource(
    this.client,
    this.component,
    this.rootId,
    this.rootName,
  );
  final Client client;
  final InvitationComponent component;
  @override
  final String rootId;
  @override
  final String rootName;
  @override
  String get accountId => client.identifier;
  @override
  String? get selfId => client.self?.identifier;
  @override
  bool get isSpace => client.getSpace(rootId) != null;
  @override
  bool truncated = false;
  final Map<String, InvitePerson> _people = {};
  final Map<(String, String), String?> _membership = {};
  @override
  InvitePerson person(String id) {
    final p = client.getComponent<UserProfileComponent>()?.cachedProfile(id);
    return _people.putIfAbsent(
      id,
      () => p == null
          ? InvitePerson(id, id, color: MatrixPeer.hashColor(id))
          : InvitePerson.profile(p),
    );
  }

  @override
  List<InvitePerson> get recommendations {
    final dms = client.getComponent<DirectMessagesComponent>();
    for (final room in dms?.directMessageRooms ?? <Room>[]) {
      final id = dms?.getDirectMessagePartnerId(room);
      if (id != null) {
        _people.putIfAbsent(
          id,
          () => InvitePerson(
            id,
            room.displayName,
            avatar: room.avatar,
            color: room.defaultColor,
          ),
        );
      }
    }
    return {
      for (final r in dms?.directMessageRooms ?? <Room>[])
        if (dms?.getDirectMessagePartnerId(r) case final String id)
          id: person(id),
    }.values.toList();
  }

  @override
  Future<List<InvitePerson>> search(String value) async {
    final results =
        await component.searchUsers(value).timeout(const Duration(seconds: 20));
    for (final p in results) {
      _people[p.identifier] = InvitePerson.profile(p);
    }
    return results.map((p) => _people[p.identifier]!).toList();
  }

  @override
  Future<List<InvitePlace>> loadPlaces() async {
    final space = client.getSpace(rootId);
    if (space == null) return [InvitePlace(rootId, rootName)];
    final index = LeaveSpaceDialog.indexOf(space);
    final tree = SpaceTree(
      spaceId: rootId,
      rootInfo: index.infos[rootId],
      fetch: index.fetcher,
      isJoined: (_) => false,
      selectionCap: SpaceTree.totalCap,
      depthLimit: 64,
    );
    await JoinedSpaceIndex.loadAll(tree);
    truncated = tree.hitTotalCap;
    return [
      InvitePlace(rootId, rootName, isSpace: true),
      for (final n in tree.descendants(tree.root))
        InvitePlace(
          n.roomId,
          n.name,
          isSpace: n.isSpace,
          ancestors: _ancestors(n),
          path: _path(n),
        ),
    ];
  }

  List<String> _ancestors(SpaceTreeNode n) {
    final ids = <String>[];
    for (var at = n.parent; at != null; at = at.parent) {
      ids.insert(0, at.roomId);
    }
    return ids;
  }

  String _path(SpaceTreeNode n) {
    final names = <String>[];
    for (var at = n.parent; at != null; at = at.parent) {
      if (at.depth > 0) names.insert(0, at.name);
    }
    return names.join(' / ');
  }

  matrix.Room? _mx(String id) {
    final space = client.getSpace(id);
    final room = client.getRoom(id);
    return space is MatrixSpace
        ? space.matrixRoom
        : room is MatrixRoom
            ? room.matrixRoom
            : null;
  }

  @override
  InviteAccess access(String userId, String roomId) {
    final mx = _mx(roomId);
    final room = client.getRoom(roomId);
    final space = client.getSpace(roomId);
    final membership = _membership.containsKey((userId, roomId))
        ? _membership[(userId, roomId)]
        : mx
            ?.getState(matrix.EventTypes.RoomMember, userId)
            ?.content
            .tryGet<String>('membership');
    final history = space != null
        ? InviteHistory.space
        : room?.isE2EE != true
            ? InviteHistory.notEncrypted
            : mx?.historyVisibility == matrix.HistoryVisibility.shared ||
                    mx?.historyVisibility ==
                        matrix.HistoryVisibility.worldReadable
                ? InviteHistory.included
                : InviteHistory.newMessagesOnly;
    return InviteAccess(
      membership: membership,
      history: history,
      canInvite: space?.permissions.canInviteUser ??
          room?.permissions.canInviteUser ??
          false,
      canGrant: membership == 'join' &&
          room is MatrixRoom &&
          ShareHistory.canShare(room, userId),
    );
  }

  @override
  bool firstContact(String id) => SpaceInviteDialog.isFirstContact(client, id);
  Future<InviteCheck> _check(BatchInviteItem item) async {
    if (client case final MatrixClient matrixClient) {
      try {
        final state = await matrixClient
            .getMatrixClient()
            .getRoomStateWithKey(
              item.roomId,
              matrix.EventTypes.RoomMember,
              item.userId,
            )
            .timeout(const Duration(seconds: 20));
        _membership[(item.userId, item.roomId)] =
            state['membership'] as String?;
      } on matrix.MatrixException catch (e) {
        if (e.error != matrix.MatrixError.M_NOT_FOUND) rethrow;
        _membership[(item.userId, item.roomId)] = null;
      }
    }
    final a = access(item.userId, item.roomId);
    if (item.operation == InviteOperation.history)
      return a.canGrant ? InviteCheck.send : InviteCheck.blocked;
    return a.membership == 'join'
        ? InviteCheck.joined
        : a.membership == 'invite'
            ? InviteCheck.invited
            : a.invitable
                ? InviteCheck.send
                : InviteCheck.blocked;
  }

  @override
  Future<void> refresh(
    List<String> users,
    List<String> rooms, {
    bool Function()? canceled,
  }) async {
    for (final id in users) {
      for (final room in rooms) {
        if (canceled?.call() == true) return;
        if (access(id, room).invitable)
          await _check(
            BatchInviteItem(userId: id, roomId: room, roomName: room),
          );
      }
    }
  }

  static void recordHistoryResult(BatchInviteItem item, String? result) {
    switch (result) {
      case null:
      case 'sent':
        item.reason =
            'History share recorded. Delivery to other devices may finish later.';
      case 'no_cross_signed_devices':
        item.reason =
            'History share recorded. This person has no cross-signed sessions yet; devices send it when they join.';
      case 'nothing_shareable':
        item.reason = 'History share recorded. No messages may be shared yet.';
      case 'identity_changed':
        throw const HistoryShareNeedsAttention(
          'This person’s identity changed. Verify them, then share history again. The history grant is recorded; check Encrypted history settings.',
        );
      default:
        throw const HistoryShareNeedsAttention(
          'History share recorded, but delivery needs attention. Check Encrypted history settings or retry this history share.',
        );
    }
  }

  @override
  InvitationBatchTask task(List<BatchInviteItem> items) => InvitationBatchTask(
        accountId: accountId,
        name: rootName,
        items: items,
        check: _check,
        send: (item) async {
          if (item.operation == InviteOperation.history) {
            final room = client.getRoom(item.roomId);
            final sharing = room == null ? null : ShareHistory.sharingOf(room);
            if (sharing == null)
              throw StateError('History sharing unavailable');
            final result = await sharing
                .grantHistory(
                    item.userId,
                    [
                      item.roomId,
                    ],
                    spaceId: isSpace ? rootId : null)
                .timeout(const Duration(seconds: 60));
            recordHistoryResult(item, result[item.roomId]);
            return;
          }
          if (!item.shareHistory && client is MatrixClient) {
            await DirectInviteDialog.inviteWithoutHistory(
              client as MatrixClient,
              item.roomId,
              item.userId,
            ).timeout(const Duration(seconds: 60));
          } else {
            await component
                .inviteUserToRoom(userId: item.userId, roomId: item.roomId)
                .timeout(const Duration(seconds: 60));
          }
        },
        retryAfter: MatrixSpaceHierarchy.retryAfter,
        uncertain: (e) =>
            e is! HistoryShareNeedsAttention &&
            (e is! matrix.MatrixException ||
                (e.response?.statusCode ?? 0) >= 500),
        reasonFor: (e) => e is HistoryShareNeedsAttention
            ? e.message
            : e is matrix.MatrixException
                ? switch (e.error) {
                    matrix.MatrixError.M_FORBIDDEN =>
                      'Not allowed. Check permissions or whether this person is banned.',
                    matrix.MatrixError.M_LIMIT_EXCEEDED =>
                      'Server busy. Try again later.',
                    matrix.MatrixError.M_NOT_FOUND =>
                      'The person or room could not be found.',
                    _ => 'The server could not complete this request.',
                  }
                : e is TimeoutException
                    ? 'Could not confirm the result. The server may still be processing it.'
                    : 'Could not confirm the result. Check your connection and membership before retrying.',
      );
}
