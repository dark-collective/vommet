import 'dart:async';
import 'package:commet/ui/organisms/invitation_view/batch_invite_source.dart';
import 'package:commet/utils/invitations/invitation_batch.dart';
import 'package:commet/utils/space_hierarchy/invite_plan.dart';
import 'package:flutter/material.dart';

class FakeBatchInviteSource extends BatchInviteSource {
  FakeBatchInviteSource({this.isSpace = true});
  @override
  final bool isSpace;
  @override
  String get accountId => 'fixture';
  @override
  String get rootId => '!space:example.org';
  @override
  String get rootName => isSpace ? 'Community space' : 'Design room';
  @override
  String get selfId => '@self:example.org';
  final people = const [
    InvitePerson('@alex:example.org', 'Alex Rivera', color: Colors.indigo),
    InvitePerson('@sam:example.org', 'Sam Chen', color: Colors.teal),
    InvitePerson('@jordan:example.org', 'Jordan Lee', color: Colors.deepOrange),
  ];
  @override
  List<InvitePerson> get recommendations => people;
  @override
  InvitePerson person(String id) =>
      people.where((p) => p.id == id).firstOrNull ?? InvitePerson(id, id);
  Future<List<InvitePerson>> Function(String)? searcher;
  Future<void> Function(BatchInviteItem)? onSend;
  bool failLoad = false, failRefresh = false, failVoice = false;
  final sent = <(String, String, InviteOperation)>[];
  @override
  Future<List<InvitePerson>> search(String value) =>
      searcher?.call(value) ??
      Future.value(
        people
            .where((p) => p.name.toLowerCase().contains(value.toLowerCase()))
            .toList(),
      );
  @override
  Future<List<InvitePlace>> loadPlaces() async {
    if (failLoad) throw StateError('load');
    return [
      InvitePlace(rootId, rootName, isSpace: isSpace),
      if (isSpace) ...[
        InvitePlace('!general', 'General', ancestors: [rootId]),
        InvitePlace('!game', 'Game night', ancestors: [rootId]),
        InvitePlace('!voice', 'Voice lobby', ancestors: [rootId]),
        InvitePlace('!mods', 'Moderators', ancestors: [rootId]),
      ],
    ];
  }

  @override
  InviteAccess access(String userId, String roomId) {
    final membership = isSpace
        ? roomId == rootId
            ? (userId == people[0].id
                ? 'join'
                : userId == people[1].id
                    ? 'invite'
                    : null)
            : roomId == '!general' && userId == people[0].id
                ? 'join'
                : roomId == '!voice' && userId == people[1].id
                    ? 'invite'
                    : null
        : null;
    return InviteAccess(
      membership: membership,
      history: roomId == rootId && isSpace
          ? InviteHistory.space
          : roomId == '!general' || !isSpace
              ? InviteHistory.included
              : roomId == '!game'
                  ? InviteHistory.newMessagesOnly
                  : InviteHistory.notEncrypted,
      canInvite: roomId != '!mods',
      canGrant: roomId == '!general' && membership == 'join',
    );
  }

  @override
  bool firstContact(String id) => id == people.last.id;
  @override
  Future<void> refresh(
    List<String> users,
    List<String> rooms, {
    bool Function()? canceled,
  }) async {
    if (failRefresh) throw StateError('refresh');
  }

  @override
  InvitationBatchTask task(List<BatchInviteItem> items) => InvitationBatchTask(
        accountId: accountId,
        name: rootName,
        items: items,
        check: (i) async {
          final a = access(i.userId, i.roomId);
          if (i.operation == InviteOperation.history) return InviteCheck.send;
          return a.membership == 'join'
              ? InviteCheck.joined
              : a.membership == 'invite'
                  ? InviteCheck.invited
                  : a.invitable
                      ? InviteCheck.send
                      : InviteCheck.blocked;
        },
        send: (i) async {
          sent.add(i.key);
          await onSend?.call(i);
          if (failVoice && i.roomId == '!voice' && i.userId == people.last.id)
            throw StateError('failed');
        },
        reasonFor: (_) => 'The server could not send this invitation.',
        uncertain: (_) => false,
      );
}
