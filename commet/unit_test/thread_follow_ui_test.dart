import 'package:commet/client/components/component.dart';
import 'package:commet/client/matrix/components/threads/matrix_threads_component.dart';
import 'package:commet/client/matrix/components/threads/thread_follows.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/ui/molecules/thread_follow_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';

// Vommet issue 1077: the open thread's Follow button and the follow state
// it loads, with the SDK faked at the network boundary.

const _me = "@me:example.org";
const _roomId = "!room:example.org";
const _rootId = r"$root";

/// A thread root by someone else; [participated] is the server's
/// `current_user_participated` in its thread summary.
Map<String, Object?> _rootJson({required bool participated}) => {
      "type": "m.room.message",
      "event_id": _rootId,
      "room_id": _roomId,
      "sender": "@other:example.org",
      "origin_server_ts": 1000,
      "content": {"msgtype": "m.text", "body": "Movie night?"},
      "unsigned": {
        "m.relations": {
          "m.thread": {
            "count": 2,
            "current_user_participated": participated,
          },
        },
      },
    };

/// The homeserver: `/event` answers with the current thread summary (you
/// replied); room account data writes are recorded.
class _Sdk extends Fake implements matrix.Client {
  final List<Map<String, Object?>> writes = [];
  int eventRequests = 0;

  @override
  String? get userID => _me;

  @override
  matrix.PushRuleSet? get globalPushRules => null;

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  @override
  Future<matrix.MatrixEvent> getOneRoomEvent(
    String roomId,
    String eventId,
  ) async {
    eventRequests++;
    return matrix.MatrixEvent.fromJson(_rootJson(participated: true));
  }

  @override
  Future<void> setAccountDataPerRoom(
    String userId,
    String roomId,
    String type,
    Map<String, Object?> body,
  ) async {
    writes.add(body);
  }
}

/// The local store: it keeps the root as it first arrived, before you
/// replied, so its thread summary says you didn't take part.
class _StoredRoom extends matrix.Room {
  _StoredRoom(_Sdk client) : super(id: _roomId, client: client);

  @override
  Future<matrix.Event?> getEventById(String eventID) async =>
      matrix.Event.fromJson(_rootJson(participated: false), this);
}

class _Client extends Fake implements MatrixClient {
  _Client(this.sdk);
  final _Sdk sdk;
  late final MatrixThreadsComponent threads = MatrixThreadsComponent(this);

  @override
  String get identifier => "fixture";

  @override
  matrix.Client getMatrixClient() => sdk;

  @override
  T? getComponent<T extends Component>() => threads is T ? threads as T : null;
}

class _Room extends Fake implements MatrixRoom {
  _Room(this.client) : matrixRoom = _StoredRoom(client.sdk);

  @override
  final _Client client;

  @override
  final matrix.Room matrixRoom;

  @override
  String get identifier => _roomId;

  @override
  Timeline? get timeline => null;
}

void main() {
  test(
      "a thread you replied in counts as followed though the stored root "
      "is stale", () async {
    final room = _Room(_Client(_Sdk()));
    expect(
      await room.client.threads.loadThreadFollowed(room, _rootId),
      isTrue,
    );
    expect(room.client.sdk.eventRequests, 1);
  });

  testWidgets("the Follow button shows Following and unfollows on tap",
      (tester) async {
    final room = _Room(_Client(_Sdk()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ThreadFollowButton(room: room, rootId: _rootId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(ThreadFollowButton.labelFollowing), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("thread-follow-button")));
    await tester.pumpAndSettle();
    expect(find.text(ThreadFollowButton.labelFollow), findsOneWidget);
    expect(room.client.sdk.writes, hasLength(1));
    final entry = ThreadFollows.parse(room.client.sdk.writes.single)[_rootId];
    expect(entry?.follow, isFalse);
    expect(entry?.automatic, isNull);

    await tester.tap(find.byKey(const ValueKey("thread-follow-button")));
    await tester.pumpAndSettle();
    expect(find.text(ThreadFollowButton.labelFollowing), findsOneWidget);
    expect(
      ThreadFollows.parse(room.client.sdk.writes.last)[_rootId]?.follow,
      isTrue,
    );
  });
}
