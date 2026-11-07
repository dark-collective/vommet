import 'dart:async';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/unread_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class _Store extends Fake implements matrix.DatabaseApi {
  final events = <String, List<matrix.Event>>{};
  final requests = <(String, int, int)>[];
  final started = Completer<void>();
  final gate = Completer<void>();
  int active = 0, peak = 0, idCalls = 0;
  bool failFirstHead = false;
  void enter() {
    active++;
    if (active > peak) peak = active;
  }

  @override
  Future<List<String>> getEventIdList(matrix.Room room,
      {int start = 0, bool includeSending = false, int? limit}) async {
    idCalls++;
    enter();
    final snapshot = events[room.id]!.map((e) => e.eventId).toList();
    await Future<void>.value();
    active--;
    return snapshot;
  }

  Future<T> payload<T>(T snapshot, {bool fail = false}) async {
    enter();
    if (!started.isCompleted) started.complete();
    await gate.future;
    active--;
    if (fail) throw StateError('old wrapper read failed');
    return snapshot;
  }

  @override
  Future<matrix.Event?> getEventById(String id, matrix.Room room) {
    requests.add((room.id, 0, 1));
    final fail = failFirstHead;
    failFirstHead = false;
    return payload(events[room.id]!.where((e) => e.eventId == id).firstOrNull,
        fail: fail);
  }

  @override
  Future<List<matrix.Event>> getEventList(matrix.Room room,
      {int start = 0, bool onlySending = false, int? limit}) {
    // The real SDK prepends *all* pending sends at start0, regardless of
    // limit. Recovery must never ask for that unbounded payload path.
    if (start == 0) throw StateError('pending sends would be prepended');
    requests.add((room.id, start, limit!));
    return payload(events[room.id]!.skip(start).take(limit).toList());
  }
}

class _Sdk extends Fake implements matrix.Client {
  _Sdk(this.database);
  @override
  final _Store database;
  @override
  String get userID => '@me:example.org';
  @override
  final Map<String, matrix.BasicEvent> accountData = {};
}

class _Client extends Fake implements MatrixClient {
  _Client(_Store store) : matrixClient = _Sdk(store);
  @override
  final _Sdk matrixClient;
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
  T? getComponent<T extends Component>() => null;
  @override
  Room? getRoom(String id) =>
      rooms.where((r) => r.identifier == id).firstOrNull;
  Future<void> close() async {
    await UnreadIndex.disposeFor(this);
    if (!matrixClient.database.gate.isCompleted)
      matrixClient.database.gate.complete();
    await sync.close();
    for (final room in rooms.whereType<_Room>()) await room.updates.close();
  }
}

class _Room extends Fake implements MatrixRoom {
  _Room(this.client, this.matrixRoom);
  @override
  final _Client client;
  @override
  final matrix.Room matrixRoom;
  @override
  String get identifier => matrixRoom.id;
  @override
  String get localId => '${client.identifier}:$identifier';
  @override
  PushRule pushRule = PushRule.mentionsOnly;
  @override
  int get notificationCount => 0;
  final restored = <String>{};
  int restorations = 0;
  @override
  int get highlightedNotificationCount => restored.length;
  @override
  bool get messagesAreNoisy => false;
  @override
  TimelineEvent? get lastEvent => null;
  @override
  TimelineEvent? get lastMessage => null;
  @override
  Timeline? get timeline => null;
  final updates = StreamController<void>.broadcast();
  @override
  Stream<void> get onUpdate => updates.stream;
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  Future<bool> loadOwnMember() async => false;
  @override
  bool restoreCachedHighlights(Iterable<matrix.Event> events) {
    restorations++;
    final before = restored.length;
    restored.addAll(events.map((e) => e.eventId));
    return restored.length != before;
  }

  @override
  bool operator ==(Object other) =>
      other is _Room &&
      identical(client, other.client) &&
      identifier == other.identifier;
  @override
  int get hashCode => Object.hash(client, identifier);
}

_Room _add(_Client client, String id, int unread) {
  final sdk = matrix.Room(id: id, client: client.matrixClient);
  sdk.states[matrix.EventTypes.Encryption] = {
    '': matrix.StrippedStateEvent(
        type: matrix.EventTypes.Encryption,
        senderId: '@me:example.org',
        stateKey: '',
        content: {'algorithm': 'm.megolm.v1.aes-sha2'})
  };
  final events = [
    for (var i = 0; i <= unread; i++)
      matrix.Event(
          type: matrix.EventTypes.Message,
          eventId: '$id-$i',
          senderId: '@them:example.org',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
          room: sdk,
          content: {'msgtype': 'm.text', 'body': 'fixture'})
  ];
  client.matrixClient.database.events[id] = events;
  sdk.lastEvent = events.first;
  sdk.receiptState = matrix.LatestReceiptState.fromJson({
    'global': {
      'public': {'e': events.last.eventId, 'ts': 1}
    }
  });
  final room = _Room(client, sdk);
  client.rooms.add(room);
  return room;
}

void main() {
  test('muted encrypted rooms with no read state perform no storage work',
      () async {
    final store = _Store()..gate.complete();
    final client = _Client(store);
    addTearDown(client.close);
    final room = _add(client, '!muted-empty', 3)
      ..pushRule = PushRule.dontNotify;
    room.matrixRoom.receiptState = matrix.LatestReceiptState.empty();
    expect(room.matrixRoom.encrypted, isTrue);
    expect(room.matrixRoom.fullyRead, isEmpty);
    final index = UnreadIndex.of(client);
    await index.onChanged.first.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(store.idCalls, 0);
    expect(store.requests, isEmpty);
  });
  test('cached pages are bounded, fair and never load pending sends', () async {
    final store = _Store()..gate.complete();
    final client = _Client(store);
    addTearDown(client.close);
    final a = _add(client, '!a', 121);
    final b = _add(client, '!b', 1);
    final index = UnreadIndex.of(client);
    await index.onChanged
        .firstWhere((_) => a.restored.length == 121 && b.restored.length == 1)
        .timeout(const Duration(seconds: 5));
    expect(store.peak, lessThanOrEqualTo(2));
    expect(store.requests.every((r) => r.$3 <= 50), isTrue);
    expect(store.requests.indexWhere((r) => r.$1 == '!b'),
        lessThan(store.requests.indexWhere((r) => r.$1 == '!a' && r.$2 == 50)));
    expect(
        store.requests
            .where((r) => r.$1 == '!a')
            .fold(0, (sum, r) => sum + r.$3),
        121);
    expect(a.restored, isNot(contains('!a-121')));
  });
  for (final action in ['read', 'unknown receipt', 'mute', 'remove', 'close']) {
    // Discord's rule: a muted encrypted room still counts its mentions, so a
    // mute keeps the read's results.
    final keeps = action == 'mute';
    test(
        keeps
            ? 'a mute during a cached payload read keeps its mentions'
            : 'a $action during a cached payload read discards stale results',
        () async {
      final store = _Store();
      final client = _Client(store);
      addTearDown(client.close);
      final room = _add(client, '!race-$action', 3);
      final index = UnreadIndex.of(client);
      await store.started.future.timeout(const Duration(seconds: 5));
      final update = action == 'close' ? null : index.onChanged.first;
      switch (action) {
        case 'read':
          room.matrixRoom.receiptState = matrix.LatestReceiptState.fromJson({
            'global': {
              'public': {'e': room.matrixRoom.lastEvent!.eventId, 'ts': 1}
            }
          });
          client.sync.add(null);
        case 'unknown receipt':
          room.matrixRoom.receiptState = matrix.LatestReceiptState.fromJson({
            'global': {
              'public': {'e': 'outside-fragment', 'ts': 1}
            }
          });
          client.sync.add(null);
        case 'mute':
          room.pushRule = PushRule.dontNotify;
          room.updates.add(null);
        case 'remove':
          client.rooms.remove(room);
          addTearDown(room.updates.close);
        case 'close':
          await index.dispose();
      }
      if (update != null) await update.timeout(const Duration(seconds: 5));
      store.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(room.restorations, keeps ? 1 : 0);
    });
  }
  test('same-ID synchronous replacement ignores old results and old failures',
      () async {
    final store = _Store()..failFirstHead = true;
    final client = _Client(store);
    addTearDown(client.close);
    final old = _add(client, '!same', 2);
    final index = UnreadIndex.of(client);
    await store.started.future.timeout(const Duration(seconds: 5));
    final replacement = _Room(client, old.matrixRoom);
    client.rooms.remove(old);
    client.rooms.add(replacement);
    addTearDown(old.updates.close);
    final observed = index.onChanged.first;
    await observed.timeout(const Duration(seconds: 5));
    store.gate.complete();
    await index.onChanged
        .firstWhere((_) => replacement.restored.length == 2)
        .timeout(const Duration(seconds: 5));
    expect(old.restorations, 0);
    expect(replacement.restorations, 1);
    replacement.restored.add('live');
    final changed = index.onChanged.first;
    replacement.updates.add(null);
    await changed.timeout(const Duration(seconds: 5));
    expect(index.room(replacement).badge, 3);
  });
}
