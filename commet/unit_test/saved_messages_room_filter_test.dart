import 'package:commet/client/client.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Sdk extends Fake implements matrix.Client {
  @override
  final Map<String, matrix.BasicEvent> accountData = {};

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  @override
  String? get userID => '@me:example.org';

  var writes = 0;

  @override
  Future<void> setAccountData(
      String userId, String type, Map<String, Object?> body) async {
    writes++;
    accountData[type] = matrix.BasicEvent(type: type, content: body);
  }
}

class _Event extends Fake implements TimelineEvent {
  _Event(this.eventId);

  @override
  final String eventId;

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;
}

class _Room extends Fake implements Room {
  _Room(this.displayName);

  @override
  final String displayName;

  @override
  Future<TimelineEvent?> getEvent(String eventId) async => _Event(eventId);
}

class _Client extends Fake implements MatrixClient {
  _Client(this.matrixClient, this.byId);

  @override
  final matrix.Client matrixClient;
  final Map<String, Room> byId;

  @override
  Room? getRoom(String id) => byId[id];
}

/// Shared by these behavioral tests and the isolated Flutter review renders.
/// Events are stubs; sample content is represented by real bookmark notes.
class SavedMessagesFixture {
  SavedMessagesFixture(
      {List<Bookmark> saved = const [],
      Map<String, String> roomNames = const {}}) {
    _client = _Client(_sdk,
        {for (final entry in roomNames.entries) entry.key: _Room(entry.value)});
    update(saved, notify: false);
  }

  final _Sdk _sdk = _Sdk();
  late final _Client _client;

  MatrixClient get client => _client;
  int get writes => _sdk.writes;

  void update(List<Bookmark> saved, {bool notify = true}) {
    final event = matrix.BasicEvent(
        type: Bookmarks.type, content: Bookmarks.serialize(saved));
    _sdk.accountData[Bookmarks.type] = event;
    if (notify) {
      _sdk.onSync
          .add(matrix.SyncUpdate(nextBatch: 'saved', accountData: [event]));
    }
  }

  Future<void> dispose() async {
    await _sdk.onSync.close();
  }
}

const _alpha = '!alpha:example.org';
const _beta = '!beta:example.org';
const _left = '!left:example.org';
const _a1 = Bookmark(
    roomId: _alpha,
    eventId: 'a1',
    savedTs: 40,
    tags: ['work'],
    note: 'A text note');
const _a2 = Bookmark(
    roomId: _alpha,
    eventId: 'a2',
    savedTs: 30,
    tags: ['ideas'],
    note: 'A picture');
const _b1 = Bookmark(
    roomId: _beta,
    eventId: 'b1',
    savedTs: 20,
    tags: ['work'],
    note: 'Another note');
const _leftItem = Bookmark(roomId: _left, eventId: 'left', savedTs: 10);

Finder _entry(String id) => find.byKey(ValueKey('saved-$id'));
Finder _option(String room) => find.byKey(ValueKey('saved-room-option-$room'));
final _rooms = find.byKey(const ValueKey('saved-room-filter'));
final _active = find.byKey(const ValueKey('saved-room-active'));
final _clear = find.byKey(const ValueKey('saved-room-clear'));

Future<void> _open(WidgetTester tester, SavedMessagesFixture fixture,
    {Size size = const Size(900, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(fixture.dispose);
  await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
          body: Center(child: SavedMessages(client: fixture.client)))));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String room) async {
  await tester.tap(_rooms);
  await tester.pumpAndSettle();
  await tester.tap(_option(room));
  await tester.pumpAndSettle();
}

void main() {
  SavedMessagesFixture fixture(
          {List<Bookmark> saved = const [_a1, _a2, _b1]}) =>
      SavedMessagesFixture(
          saved: saved,
          roomNames: const {_alpha: 'Engineering', _beta: 'Social'});

  testWidgets('Rooms lists each saved room once and filters all its bookmarks',
      (tester) async {
    await _open(tester, fixture());
    await tester.tap(_rooms);
    await tester.pumpAndSettle();
    expect(_option(_alpha), findsOneWidget);
    expect(_option(_beta), findsOneWidget);
    expect(find.byType(CheckedPopupMenuItem<String>), findsNWidgets(2));
    await tester.tap(_option(_alpha));
    await tester.pumpAndSettle();
    expect(_entry('a1'), findsOneWidget);
    expect(_entry('a2'), findsOneWidget);
    expect(_entry('b1'), findsNothing);
    expect(tester.getTopLeft(_entry('a1')).dy,
        lessThan(tester.getTopLeft(_entry('a2')).dy));
    expect(_active, findsOneWidget);
    await tester.tap(_rooms);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckedPopupMenuItem<String>>(_option(_alpha)).checked,
        isTrue);
  });

  testWidgets('clearing room keeps the tag, and All clears only the tag',
      (tester) async {
    await _open(tester, fixture());
    await _choose(tester, _alpha);
    await tester.tap(find.byKey(const ValueKey('saved-tag-work')));
    await tester.pumpAndSettle();
    expect(_entry('a1'), findsOneWidget);
    expect(_entry('a2'), findsNothing);
    expect(_entry('b1'), findsNothing);
    await tester.tap(_clear);
    await tester.pumpAndSettle();
    expect(_entry('a1'), findsOneWidget);
    expect(_entry('b1'), findsOneWidget);
    expect(_entry('a2'), findsNothing);
    expect(_active, findsNothing);
    await _choose(tester, _alpha);
    await tester.tap(find.byKey(const ValueKey('saved-tag-all')));
    await tester.pumpAndSettle();
    expect(_entry('a1'), findsOneWidget);
    expect(_entry('a2'), findsOneWidget);
    expect(_entry('b1'), findsNothing);
    expect(_active, findsOneWidget);
  });

  testWidgets(
      'a room without the active tag shows a filter-specific empty state',
      (tester) async {
    await _open(tester, fixture(saved: const [_a2, _b1]));
    await tester.tap(find.byKey(const ValueKey('saved-tag-work')));
    await tester.pumpAndSettle();
    await _choose(tester, _alpha);
    expect(find.text(SavedMessages.labelNoMatchingSaved), findsOneWidget);
    expect(find.text(SavedMessages.labelNoSavedMessages), findsNothing);
    expect(_active, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('saved-tag-all')));
    await tester.pumpAndSettle();
    expect(_entry('a2'), findsOneWidget);
    expect(_entry('b1'), findsNothing);
  });

  testWidgets('removing one save keeps its room, removing the last clears it',
      (tester) async {
    final data = fixture();
    await _open(tester, data);
    await _choose(tester, _alpha);
    await tester.tap(find.byKey(const ValueKey('saved-remove-a1')));
    await tester.pumpAndSettle();
    expect(data.writes, 1);
    expect(_entry('a1'), findsNothing);
    expect(_entry('a2'), findsOneWidget);
    expect(_entry('b1'), findsNothing);
    expect(_active, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('saved-remove-a2')));
    await tester.pumpAndSettle();
    expect(data.writes, 2);
    expect(_active, findsNothing);
    expect(_entry('b1'), findsOneWidget);
  });

  testWidgets('a sync removing the selected room clears only its room filter',
      (tester) async {
    final data = fixture();
    await _open(tester, data);
    await tester.tap(find.byKey(const ValueKey('saved-tag-work')));
    await tester.pumpAndSettle();
    await _choose(tester, _alpha);
    data.update(const [_b1]);
    await tester.pumpAndSettle();
    expect(_active, findsNothing);
    expect(_entry('b1'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('saved-tag-work')))
            .selected,
        isTrue);
  });

  testWidgets('a stale menu choice cannot leave a removed room selected',
      (tester) async {
    final data = fixture();
    await _open(tester, data);
    await tester.tap(_rooms);
    await tester.pumpAndSettle();
    data.update(const [_b1]);
    await tester.pumpAndSettle();
    await tester.tap(_option(_alpha));
    await tester.pumpAndSettle();
    expect(_active, findsNothing);
    expect(_entry('b1'), findsOneWidget);
  });

  testWidgets('unknown and unnamed rooms use their room IDs consistently',
      (tester) async {
    final data = SavedMessagesFixture(
        saved: const [_a1, _leftItem], roomNames: const {_alpha: '   '});
    await _open(tester, data);
    await _choose(tester, _left);
    expect(_entry('left'), findsOneWidget);
    expect(_entry('a1'), findsNothing);
    expect(find.descendant(of: _active, matching: find.text(_left)),
        findsOneWidget);
    await _choose(tester, _alpha);
    expect(find.descendant(of: _active, matching: find.text(_alpha)),
        findsOneWidget);
    expect(find.descendant(of: _entry('a1'), matching: find.text(_alpha)),
        findsOneWidget);
  });

  testWidgets('rooms with identical names remain distinct choices',
      (tester) async {
    await _open(
        tester,
        SavedMessagesFixture(
            saved: const [_a1, _b1],
            roomNames: const {_alpha: 'Shared name', _beta: 'Shared name'}));
    await tester.tap(_rooms);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Tooltip>(find.descendant(
                of: _option(_beta), matching: find.byType(Tooltip)))
            .message,
        contains(_beta));
    await tester.tap(_option(_beta));
    await tester.pumpAndSettle();
    expect(_entry('b1'), findsOneWidget);
    expect(_entry('a1'), findsNothing);
  });

  testWidgets(
      'an empty library has its original empty state and no room picker',
      (tester) async {
    await _open(tester, fixture(saved: const []));
    expect(find.text(SavedMessages.labelNoSavedMessages), findsOneWidget);
    expect(_rooms, findsNothing);
  });

  for (final size in [const Size(360, 740), const Size(1200, 800)]) {
    testWidgets('long selected room names fit at ${size.width.toInt()}px',
        (tester) async {
      final data = SavedMessagesFixture(saved: const [
        _a1
      ], roomNames: {
        _alpha:
            'A long room name that must fit without hiding the clear button ' *
                3,
      });
      await _open(tester, data, size: size);
      await _choose(tester, _alpha);
      expect(tester.takeException(), isNull);
      await tester.tap(_clear);
      await tester.pumpAndSettle();
      expect(_active, findsNothing);
    });
  }
}
