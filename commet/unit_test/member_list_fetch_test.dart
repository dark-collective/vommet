// Vommet issue 583: the member panel downloaded a room's whole member list
// (everyone who ever left included) every time it was built while the
// room's list counted as incomplete, and a room with a pending invite never
// became complete. Megabytes per room open in big public rooms.
import 'dart:convert';

import 'package:commet/client/matrix/matrix_member_list_fetch.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const roomId = "!big:example.com";

Map<String, Object?> _member(String user, String membership) => {
      "type": "m.room.member",
      "state_key": user,
      "sender": user,
      "event_id": "\$$membership-$user",
      "origin_server_ts": 1,
      "content": {"membership": membership},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Client client;
  late List<Uri> memberRequests;
  var failMembers = false;

  setUp(() async {
    memberRequests = [];
    failMembers = false;
    final http = MockClient((request) async {
      if (request.url.path.endsWith("/members")) {
        memberRequests.add(request.url);
        // Let concurrent callers pile up before answering.
        await Future.delayed(const Duration(milliseconds: 20));
        if (failMembers) {
          return _json({"errcode": "M_UNKNOWN", "error": "boom"}, 500);
        }
        final skipLeave =
            request.url.queryParameters["not_membership"] == "leave";
        return _json({
          "chunk": [
            _member("@me:example.com", "join"),
            _member("@a:example.com", "join"),
            _member("@b:example.com", "join"),
            _member("@c:example.com", "invite"),
            if (!skipLeave) ...[
              _member("@d:example.com", "leave"),
              _member("@e:example.com", "leave"),
            ],
          ]
        });
      }
      if (request.url.path.endsWith("/sync")) {
        await Future.delayed(const Duration(seconds: 5));
        return _json({"next_batch": "s1"});
      }
      if (request.url.path.endsWith("/filter")) {
        return _json({"filter_id": "f"});
      }
      if (request.url.path.endsWith("/versions")) {
        return _json({
          "versions": ["v1.11"]
        });
      }
      return _json({});
    });
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), "member list fetch test");
    client =
        Client("member-list-fetch-test", database: database, httpClient: http);
    await client.init(
      newToken: "token",
      newHomeserver: Uri.parse("https://example.com"),
      newUserID: "@me:example.com",
      newDeviceID: "DEVICE",
      newDeviceName: "test",
      waitForFirstSync: false,
    );
    // A lazily loaded room: 3 joined, 1 invited, only our own member event.
    await client.handleSync(SyncUpdate(
      nextBatch: "s0",
      rooms: RoomsUpdate(join: {
        roomId: JoinedRoomUpdate(
          summary: RoomSummary.fromJson({
            "m.joined_member_count": 3,
            "m.invited_member_count": 1,
          }),
          state: [
            MatrixEvent.fromJson(_member("@me:example.com", "join")),
          ],
        ),
      }),
    ));
  });

  tearDown(() => client.dispose(closeDatabase: true));

  Room room() => client.getRoomById(roomId)!;

  test("fetches the joined members once, without departed members", () async {
    final fetch = MatrixMemberListFetch(room());

    final members = await fetch.joinedMembers();

    expect(members.map((u) => u.id).toSet(),
        {"@me:example.com", "@a:example.com", "@b:example.com"});
    expect(memberRequests, hasLength(1));
    expect(memberRequests.single.queryParameters["not_membership"], "leave");
    expect(fetch.recentlyFetched, isTrue);

    // Reopening the room / switching tabs: no new download.
    final again = await fetch.joinedMembers();
    expect(again.map((u) => u.id).toSet(), members.map((u) => u.id).toSet());
    expect(memberRequests, hasLength(1));
  });

  test("the SDK's completeness check stays false with a pending invite",
      () async {
    // Why the panel can't rely on participantListComplete alone: the panel
    // keeps only joined members, so the invited count never matches and
    // every panel build used to fetch again.
    final fetch = MatrixMemberListFetch(room());
    await fetch.joinedMembers();

    expect(room().participantListComplete, isFalse);
    expect(fetch.recentlyFetched, isTrue);
  });

  test("concurrent callers share one request", () async {
    final fetch = MatrixMemberListFetch(room());

    final results = await Future.wait(
        [fetch.joinedMembers(), fetch.joinedMembers(), fetch.joinedMembers()]);

    expect(memberRequests, hasLength(1));
    for (final members in results) {
      expect(members, hasLength(3));
    }
  });

  test("fetches again once the result is older than maxAge", () async {
    var now = DateTime(2026, 10, 22, 12);
    final fetch = MatrixMemberListFetch(room(),
        maxAge: const Duration(minutes: 30), now: () => now);

    await fetch.joinedMembers();
    now = now.add(const Duration(minutes: 29));
    await fetch.joinedMembers();
    expect(memberRequests, hasLength(1));

    now = now.add(const Duration(minutes: 2));
    expect(fetch.recentlyFetched, isFalse);
    await fetch.joinedMembers();
    expect(memberRequests, hasLength(2));
  });

  test("a failed fetch isn't remembered", () async {
    final fetch = MatrixMemberListFetch(room());
    failMembers = true;

    await expectLater(fetch.joinedMembers(), throwsA(isA<MatrixException>()));
    expect(fetch.recentlyFetched, isFalse);

    failMembers = false;
    final members = await fetch.joinedMembers();
    expect(members, hasLength(3));
    expect(memberRequests, hasLength(2));
  });

  test("no request when the stored list is already complete", () async {
    await client.handleSync(SyncUpdate(
      nextBatch: "s2",
      rooms: RoomsUpdate(join: {
        roomId: JoinedRoomUpdate(
          summary: RoomSummary.fromJson({
            "m.joined_member_count": 1,
            "m.invited_member_count": 0,
          }),
        ),
      }),
    ));
    final fetch = MatrixMemberListFetch(room());

    final members = await fetch.joinedMembers();

    expect(members.map((u) => u.id), ["@me:example.com"]);
    expect(memberRequests, isEmpty);
  });
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});
