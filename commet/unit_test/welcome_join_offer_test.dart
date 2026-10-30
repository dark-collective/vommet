// Vommet: the welcome screen's "Join #vommet:nether.im" offer only shows once
// the account is known not to be in the room, so it never flashes for members.
import 'dart:async';

import 'package:commet/ui/pages/setup/menus/welcome_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const roomId = "!vommet:nether.im";

  Future<FeedbackRoomMembership> check({
    Set<String?> local = const {},
    Future<String?> Function()? resolve,
    Future<List<String>> Function()? joined,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      checkFeedbackRoomMembership(
        locallyJoined: local.contains,
        resolveAlias: resolve ?? () async => roomId,
        joinedRoomIds: joined ?? () async => [],
        timeout: timeout,
      );

  test("already in the room locally: member, without asking the server",
      () async {
    var asked = false;
    final result = await check(
      local: {null},
      resolve: () async {
        asked = true;
        return roomId;
      },
    );
    expect(result, FeedbackRoomMembership.member);
    expect(asked, isFalse);
  });

  test("the server says joined (first sync not done yet): member", () async {
    expect(await check(joined: () async => ["!other:x", roomId]),
        FeedbackRoomMembership.member);
  });

  test("the resolved room id is known locally: member", () async {
    expect(await check(local: {roomId}), FeedbackRoomMembership.member);
  });

  test("the server says not joined: not a member", () async {
    expect(await check(joined: () async => ["!other:x"]),
        FeedbackRoomMembership.notMember);
  });

  test("the alias doesn't resolve: unknown", () async {
    expect(await check(resolve: () async => throw Exception("M_NOT_FOUND")),
        FeedbackRoomMembership.unknown);
    expect(
        await check(resolve: () async => null), FeedbackRoomMembership.unknown);
  });

  test("joined rooms can't be fetched (offline): unknown", () async {
    expect(await check(joined: () async => throw Exception("offline")),
        FeedbackRoomMembership.unknown);
  });

  test("no answer in time: unknown", () async {
    final never = Completer<List<String>>();
    expect(
        await check(
            joined: () => never.future,
            timeout: const Duration(milliseconds: 50)),
        FeedbackRoomMembership.unknown);
  });
}
