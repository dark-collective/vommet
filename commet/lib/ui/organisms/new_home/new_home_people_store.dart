// Vommet (New Home step 2): where the People page, the People row and the
// rail get their direct-message invites from. Reads the SDK's rooms on each
// sync, so the count is right before the People page has ever opened.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_model.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// A received invite and the account it came to.
class AccountInvite {
  AccountInvite(this.client, this.invite);
  final Client client;
  final ReceivedInvite invite;
}

/// A sent invite and the account it came from.
class AccountSentInvite {
  AccountSentInvite(this.client, this.invite);
  final Client client;
  final SentInvite invite;
}

class NewHomeInvites {
  NewHomeInvites._();
  static final NewHomeInvites instance = NewHomeInvites._();

  /// Received direct-message invites, newest first.
  final ValueNotifier<List<AccountInvite>> received = ValueNotifier(const []);

  /// Direct-message invites you sent that haven't been answered.
  final ValueNotifier<List<AccountSentInvite>> sent = ValueNotifier(const []);

  /// The badge: received invites only ([PeopleModel.badgeCount]).
  final ValueNotifier<int> count = ValueNotifier(0);

  ClientManager? _manager;
  final List<StreamSubscription> _subs = [];
  Timer? _pending;

  /// Follows [manager]; cheap to call again from every build.
  void attach(ClientManager manager) {
    if (identical(manager, _manager)) return;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _manager = manager;
    _subs.addAll([
      manager.onSync.stream.listen((_) => refreshSoon()),
      manager.onClientAdded.stream.listen((_) => _watchClients()),
      manager.onClientRemoved.stream.listen((_) => _watchClients()),
    ]);
    _watchClients();
  }

  final List<StreamSubscription> _clientSubs = [];

  void _watchClients() {
    for (final s in _clientSubs) {
      s.cancel();
    }
    _clientSubs.clear();
    for (final client in _manager?.clients ?? const <Client>[]) {
      final friends = client.getComponent<FriendsComponent>();
      if (friends != null) {
        _clientSubs.add(friends.onFriendsChanged.listen((_) => refreshSoon()));
      }
    }
    // Not straight away: attach runs from builds, and the badges listen.
    Future.microtask(refresh);
  }

  void refreshSoon() {
    _pending ??= Timer(const Duration(milliseconds: 400), () {
      _pending = null;
      refresh();
    });
  }

  void refresh() {
    final received = <AccountInvite>[];
    final sent = <AccountSentInvite>[];
    for (final client in _manager?.clients ?? const <Client>[]) {
      if (client is! MatrixClient || !client.isLoggedIn()) continue;
      try {
        final contacts =
            client.getComponent<FriendsComponent>()?.friends ?? const {};
        final mx = client.matrixClient;
        for (final invite in PeopleModel.receivedInvites(
            inviteFacts(client), contacts, mx.userID)) {
          received.add(AccountInvite(client, invite));
        }
        for (final invite
            in PeopleModel.sentInvites(sentFacts(client), mx.userID)) {
          sent.add(AccountSentInvite(client, invite));
        }
      } catch (e) {
        Log.w("New Home: couldn't read invites: $e");
      }
    }
    received.sort((a, b) =>
        _newestFirst(a.invite.facts.invitedAt, b.invite.facts.invitedAt));
    sent.sort((a, b) => _newestFirst(a.invite.invitedAt, b.invite.invitedAt));
    if (!_sameReceived(received, this.received.value)) {
      this.received.value = received;
    }
    if (!_sameSent(sent, this.sent.value)) this.sent.value = sent;
    count.value = PeopleModel.badgeCount([for (final r in received) r.invite]);
  }

  static int _newestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  static bool _sameReceived(List<AccountInvite> a, List<AccountInvite> b) =>
      listEquals([
        for (final i in a)
          "${i.client.identifier}|${i.invite.facts.roomId}|${i.invite.fromContact}"
      ], [
        for (final i in b)
          "${i.client.identifier}|${i.invite.facts.roomId}|${i.invite.fromContact}"
      ]);

  static bool _sameSent(List<AccountSentInvite> a, List<AccountSentInvite> b) =>
      listEquals([
        for (final i in a)
          "${i.client.identifier}|${i.invite.roomId}|${i.invite.userId}"
      ], [
        for (final i in b)
          "${i.client.identifier}|${i.invite.roomId}|${i.invite.userId}"
      ]);

  static DateTime? _time(matrix.StrippedStateEvent? state) =>
      state is matrix.Event ? state.originServerTs : null;

  static String? _roomName(matrix.Room room) {
    final name = room.getState(matrix.EventTypes.RoomName)?.content["name"];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  /// The SDK's invited rooms as [InviteFacts]. An invite counts as a direct
  /// message when its member event says `is_direct`, as the spec has it.
  static List<InviteFacts> inviteFacts(MatrixClient client) {
    final mx = client.matrixClient;
    final self = mx.userID;
    return [
      for (final room in mx.rooms)
        if (room.membership.isInvite)
          () {
            final member = self == null
                ? null
                : room.states[matrix.EventTypes.RoomMember]?[self];
            return InviteFacts(
              clientKey: client.identifier,
              roomId: room.id,
              inviterId: member?.senderId,
              isDirect: member?.content["is_direct"] == true,
              groupName: _roomName(room),
              invitedAt: _time(member),
            );
          }()
    ];
  }

  /// Your joined direct messages with their members, for the sent invites.
  static List<DmMembershipFacts> sentFacts(MatrixClient client) {
    final dms = client.getComponent<DirectMessagesComponent>();
    if (dms == null) return const [];
    final result = <DmMembershipFacts>[];
    for (final room in dms.directMessageRooms) {
      if (room is! MatrixRoom) continue;
      final mxRoom = room.matrixRoom;
      final members = mxRoom.states[matrix.EventTypes.RoomMember] ?? const {};
      result.add(DmMembershipFacts(
        roomId: mxRoom.id,
        selfJoined: mxRoom.membership == matrix.Membership.join,
        groupName: _roomName(mxRoom),
        members: [
          for (final entry in members.entries)
            MemberFacts(
              entry.key,
              entry.value.content["membership"] as String? ?? "leave",
              invitedBy: entry.value.senderId,
              at: _time(entry.value),
            )
        ],
      ));
    }
    return result;
  }

  // Actions. Each refreshes straight after, so the lists and badges follow.

  static Future<void> accept(AccountInvite invite) async {
    await invite.client
        .getComponent<InvitationComponent>()
        ?.acceptInvitation(Invitation(roomId: invite.invite.facts.roomId));
    instance.refresh();
  }

  static Future<void> decline(AccountInvite invite) async {
    await invite.client
        .getComponent<InvitationComponent>()
        ?.rejectInvitation(Invitation(roomId: invite.invite.facts.roomId));
    instance.refresh();
  }

  /// Blocks the inviter (their invites and messages stop reaching you) and
  /// declines the invite.
  static Future<void> blockAndDecline(AccountInvite invite) async {
    final inviter = invite.invite.facts.inviterId;
    if (inviter != null) {
      await invite.client.getComponent<UserBlockingComponent>()?.block(inviter);
    }
    await decline(invite);
  }

  /// Cancels a sent invite. Matrix can't take an invite back as such; the
  /// way to revoke one is to kick the invited user (allowed for whoever sent
  /// it). When nobody else is in the room or invited, the DM would stay
  /// empty, so you also leave and forget it.
  static Future<void> cancel(AccountSentInvite sent) async {
    final room = sent.client.getRoom(sent.invite.roomId);
    if (room is! MatrixRoom) return;
    final mxRoom = room.matrixRoom;
    await mxRoom.kick(sent.invite.userId);
    if (sent.invite.leaveOnCancel) {
      await mxRoom.leave();
      try {
        await mxRoom.forget();
      } catch (_) {
        // Already gone; nothing to forget.
      }
    }
    instance.refresh();
  }
}
