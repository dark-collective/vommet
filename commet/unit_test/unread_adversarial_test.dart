import 'dart:async';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/unread_index.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:commet/ui/organisms/new_home/notifications_feed.dart';
import 'package:matrix/matrix.dart' as mx;
import 'helpers/unread_fixtures.dart';

class Sdk extends Fake implements mx.Client {
  bool serverRead = true;
  @override
  String? get userID => '@me:test';
  @override
  final Map<String, mx.BasicEvent> accountData = {
    'im.vommet.thread_read_state': mx.BasicEvent(
      type: 'im.vommet.thread_read_state',
      content: {'default': 'off'},
    ),
  };
  @override
  final List<mx.Room> rooms = [];
  @override
  final mx.DatabaseApi database = Db();
  @override
  Future<mx.GetNotificationsResponse> getNotifications({
    String? from,
    int? limit,
    String? only,
  }) async =>
      mx.GetNotificationsResponse.fromJson({
        'notifications': [
          {
            'actions': ['notify'],
            'read': serverRead,
            'room_id': '!r:test',
            'ts': DateTime.now().millisecondsSinceEpoch,
            'event': {
              'type': 'm.room.message',
              'event_id': r'$old',
              'sender': '@them:test',
              'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
              'content': {'msgtype': 'm.text', 'body': 'already read'},
            },
          },
        ],
      });
}

class Db extends Fake implements mx.DatabaseApi {
  int calls = 0, active = 0, peak = 0;
  final gate = Completer<void>();
  final twoStarted = Completer<void>();
  final hundredFinished = Completer<void>();
  int finished = 0;
  List<String> result = [];
  @override
  Future<List<String>> getEventIdList(
    mx.Room room, {
    int start = 0,
    bool includeSending = false,
    int? limit,
  }) async {
    calls++;
    if (calls == 2) twoStarted.complete();
    active++;
    if (active > peak) peak = active;
    await gate.future;
    active--;
    if (++finished == 100) hundredFinished.complete();
    return result;
  }
}

class AppClient extends Fake implements MatrixClient {
  AppClient(this.matrixClient);
  @override
  final mx.Client matrixClient;
  @override
  String get identifier => 'account';
  @override
  final rooms = NotifyingList<Room>.empty(growable: true);
  final sync = StreamController<void>.broadcast();
  @override
  Stream<void> get onSync => sync.stream;
  @override
  Stream<Room> get onRoomAdded => rooms.onAdd;
  @override
  Stream<Room> get onRoomRemoved => rooms.onRemove;
  @override
  List<Space> get spaces => [];
  @override
  T? getComponent<T extends Component>() => null;
  @override
  Room? getRoom(String id) =>
      rooms.where((r) => r.identifier == id).firstOrNull;

  Future<void> close() async {
    await UnreadIndex.disposeFor(this);
    final db = matrixClient.database as Db;
    if (!db.gate.isCompleted) db.gate.complete();
    await sync.close();
    for (final room in rooms.whereType<AppRoom>()) {
      await room.updates.close();
    }
  }
}

class EmptyReplacement extends Fake implements RoomReplacement {
  @override
  RoomTombstone? get tombstone => null;
}

class AppRoom extends Fake implements MatrixRoom {
  AppRoom(this.client, this.matrixRoom);
  @override
  final Client client;
  @override
  final mx.Room matrixRoom;
  @override
  RoomReplacement get replacement => EmptyReplacement();
  @override
  String get identifier => matrixRoom.id;
  @override
  String get localId => '${client.identifier}/${matrixRoom.id}';
  @override
  PushRule pushRule = PushRule.notify;
  @override
  int notificationCount = 0;
  @override
  int highlightedNotificationCount = 0;
  @override
  bool messagesAreNoisy = false;
  @override
  TimelineEvent? lastEvent;
  @override
  TimelineEvent? lastMessage;
  @override
  Timeline? get timeline => null;
  final updates = StreamController<void>.broadcast();
  @override
  Stream<void> get onUpdate => updates.stream;
  @override
  T? getComponent<T extends RoomComponent>() => null;
}

class Wrapped extends Fake implements MatrixTimelineEvent {
  Wrapped(this.event);
  @override
  final mx.Event event;
  @override
  String get eventId => event.eventId;
  @override
  String get senderId => event.senderId;
  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;
}

class SdkTimeline extends Fake implements mx.Timeline {
  SdkTimeline(this.room);
  @override
  final mx.Room room;
  @override
  final List<mx.Event> events = [];
  final gate = Completer<void>();
  String? sent;
  @override
  Future<void> setReadMarker({String? eventId, bool? public}) async {
    sent = eventId ?? events.firstWhere((e) => e.status.isSynced).eventId;
    await gate.future;
  }

  @override
  void cancelSubscriptions() {}
}

class Manager extends Fake implements ClientManager {
  Manager(Client client) : clients = NotifyingList.from([client]);
  @override
  final NotifyingList<Client> clients;
}

mx.Event event(mx.Room room, String id) => mx.Event(
      type: mx.EventTypes.Message,
      eventId: id,
      senderId: '@them:test',
      originServerTs: DateTime.now(),
      room: room,
      content: {'msgtype': 'm.text', 'body': 'message'},
    );
void main() {
  test(
    'pending read must not acknowledge a message arriving during the request',
    () async {
      final sdk = Sdk();
      final sdkRoom = mx.Room(id: '!race:test', client: sdk);
      final app = AppClient(sdk);
      final room = AppRoom(UnreadClient(), sdkRoom);
      final timeline = SdkTimeline(sdkRoom);
      final production = MatrixTimeline(
        app,
        room,
        sdkRoom,
        initialTimeline: timeline,
      );
      addTearDown(production.close);
      final old = event(sdkRoom, r'$seen');
      final fresh = event(sdkRoom, r'$arrived');
      timeline.events.add(old);
      production.markAsRead(Wrapped(old));
      await Future<void>.delayed(Duration.zero);
      expect(timeline.sent, r'$seen');
      timeline.events.insert(0, fresh);
      timeline.gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        readByOwnReceipts(sdkRoom, fresh),
        isFalse,
        reason: 'Only the older event was sent to the server',
      );
    },
  );
  test(
    'an uncached newest message must outrank an older cached read message',
    () {
      final sdkRoom = mx.Room(id: '!order:test', client: Sdk());
      sdkRoom.receiptState = mx.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': r'$old', 'ts': 1},
        },
      });
      final room = AppRoom(UnreadClient(), sdkRoom)
        ..lastEvent = Wrapped(event(sdkRoom, r'$new'))
        ..lastMessage = Wrapped(event(sdkRoom, r'$old'));
      rememberUnreadOrder(sdkRoom, [r'$old']);
      expect(roomHasUnreadActivity(room), isTrue);
    },
  );
  test(
    'a server-read notification outside cached history must stay read',
    () async {
      final sdk = Sdk();
      final client = AppClient(sdk);
      addTearDown(client.close);
      final sdkRoom = mx.Room(id: '!r:test', client: sdk);
      sdkRoom.receiptState = mx.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': r'$latest', 'ts': 1},
        },
      });
      rememberUnreadOrder(sdkRoom, [r'$latest', r'$recent']);
      client.rooms.add(AppRoom(client, sdkRoom));
      final feed = NotificationsFeed.of(Manager(client), null);
      await feed.load();
      expect(feed.entries, hasLength(1));
      expect(
        feed.entries.single.read,
        isTrue,
        reason:
            'The server marks this older notification read, but the event is outside local cached order',
      );
    },
  );
  test('the shared read helper skips pending outgoing events', () async {
    final sdkRoom = mx.Room(id: '!pending:test', client: Sdk());
    final timeline = SdkTimeline(sdkRoom);
    final pending = event(sdkRoom, r'$pending')
      ..status = mx.EventStatus.sending;
    timeline.events.addAll([pending, event(sdkRoom, r'$synced')]);
    final request = markTimelineRead(timeline, public: false);
    expect(timeline.sent, r'$synced');
    timeline.gate.complete();
    await request;
    expect(ownReceiptIds(sdkRoom), contains(r'$synced'));
    expect(ownReceiptIds(sdkRoom), isNot(contains(r'$pending')));
  });

  test('failed read requests do not create local read evidence', () async {
    final sdkRoom = mx.Room(id: '!failed:test', client: Sdk());
    final timeline = SdkTimeline(sdkRoom)..events.add(event(sdkRoom, r'$seen'));
    final request = markTimelineRead(timeline);
    final failed = expectLater(request, throwsStateError);
    timeline.gate.completeError(StateError('request failed'));
    await failed;
    expect(ownReceiptIds(sdkRoom), isEmpty);
  });

  test('unknown receipt order preserves read state across feed refreshes',
      () async {
    final sdk = Sdk();
    final client = AppClient(sdk);
    addTearDown(client.close);
    final sdkRoom = mx.Room(id: '!r:test', client: sdk);
    sdkRoom.receiptState = mx.LatestReceiptState.fromJson({
      'global': {
        'public': {'e': r'$latest', 'ts': 1}
      }
    });
    client.rooms.add(AppRoom(client, sdkRoom));
    final feed = NotificationsFeed.of(Manager(client), null);
    await feed.load();
    expect(feed.entries.single.read, isTrue);
    feed.signature = feed.countsSignature();
    feed.changed();
    expect(feed.entries.single.read, isTrue);
    rememberUnreadOrder(sdkRoom, [r'$old', r'$latest']);
    feed.changed();
    expect(feed.entries.single.read, isFalse);
    rememberUnreadOrder(sdkRoom, [r'$latest', r'$old']);
    feed.changed();
    expect(feed.entries.single.read, isTrue);
    rememberUnreadOrder(sdkRoom, []);
    feed.changed();
    expect(feed.entries.single.read, isTrue);
  });

  test('local read evidence overrides a stale unread server flag', () async {
    final sdk = Sdk()..serverRead = false;
    final client = AppClient(sdk);
    addTearDown(client.close);
    final sdkRoom = mx.Room(id: '!r:test', client: sdk);
    recordOwnReceipt(sdkRoom, r'$old');
    client.rooms.add(AppRoom(client, sdkRoom));
    final feed = NotificationsFeed.of(Manager(client), null);
    await feed.load();
    expect(feed.entries.single.read, isTrue);
  });

  test('receipt history queries are bounded and unchanged storage stays quiet',
      () async {
    final sdk = Sdk();
    final client = AppClient(sdk);
    addTearDown(client.close);
    final db = sdk.database as Db;
    for (var i = 0; i < 100; i++) {
      final room = mx.Room(id: '!$i:test', client: sdk);
      room.receiptState = mx.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': r'$old', 'ts': 1}
        }
      });
      client.rooms.add(AppRoom(client, room));
    }
    final index = UnreadIndex.of(client);
    var changes = 0;
    final sub = index.onChanged.listen((_) => changes++);
    addTearDown(sub.cancel);
    await db.twoStarted.future.timeout(const Duration(seconds: 5));
    expect(db.calls, 2);
    client.sync.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(db.calls, 2);
    final beforeStorage = changes;
    db.gate.complete();
    await db.hundredFinished.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(db.calls, 100);
    expect(db.peak, 2);
    expect(changes, beforeStorage);
    expect(changes, beforeStorage);
  });

  test('disposing an account discards queued and in-flight storage results',
      () async {
    final sdk = Sdk();
    final client = AppClient(sdk);
    addTearDown(client.close);
    for (var i = 0; i < 10; i++) {
      final room = mx.Room(id: '!$i:test', client: sdk);
      room.receiptState = mx.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': r'$old', 'ts': 1}
        }
      });
      client.rooms.add(AppRoom(client, room));
    }
    final index = UnreadIndex.of(client);
    final db = sdk.database as Db;
    await db.twoStarted.future.timeout(const Duration(seconds: 5));
    expect(db.calls, 2);
    await index.dispose();
    db.result = [r'$old'];
    db.gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(db.calls, 2);
    for (final room in client.rooms.whereType<AppRoom>()) {
      expect(unreadOrder(room.matrixRoom), isEmpty);
    }
  });

  test('changed storage completions publish one update per burst', () async {
    final sdk = Sdk();
    final client = AppClient(sdk);
    addTearDown(client.close);
    final db = sdk.database as Db;
    db.result = [r'$new', r'$old'];
    for (var i = 0; i < 2; i++) {
      final room = mx.Room(id: '!batch$i:test', client: sdk);
      room.receiptState = mx.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': r'$old', 'ts': 1}
        }
      });
      client.rooms.add(AppRoom(client, room));
    }
    final index = UnreadIndex.of(client);
    var changes = 0;
    final sub = index.onChanged.listen((_) => changes++);
    addTearDown(sub.cancel);
    await db.twoStarted.future.timeout(const Duration(seconds: 5));
    expect(changes, 1);
    final changed = index.onChanged.first;
    db.gate.complete();
    await changed.timeout(const Duration(seconds: 5));
    expect(changes, 2);
    expect(db.finished, 2);
  });

  test('muted rooms do not load receipt order or emit storage updates',
      () async {
    final sdk = Sdk();
    final client = AppClient(sdk);
    for (var i = 0; i < 100; i++)
      client.rooms.add(
        AppRoom(client, mx.Room(id: '!$i:test', client: sdk))
          ..pushRule = PushRule.dontNotify,
      );
    final index = UnreadIndex.of(client);
    var changes = 0;
    final sub = index.onChanged.listen((_) => changes++);
    await Future<void>.delayed(Duration.zero);
    final db = sdk.database as Db;
    expect(db.calls, 0);
    expect(db.peak, 0);
    db.gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    await sub.cancel();
    await index.dispose();
    await client.sync.close();
  });
}
