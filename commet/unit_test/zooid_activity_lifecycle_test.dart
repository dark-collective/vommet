// Vommet issue 982: real passive rows; only their timeline dependency is fake.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_zooid.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_zooid.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

import 'roomlist_fixture.dart' as fixture;

class _ActivityTimeline extends Fake implements Timeline {
  _ActivityTimeline(this.events);
  @override
  final List<TimelineEvent> events;
  @override
  final onChange = StreamController<int>.broadcast(sync: true);
  @override
  final onEventAdded = StreamController<int>.broadcast(sync: true);
  @override
  final onRemove = StreamController<int>.broadcast(sync: true);

  Future<void> close() async {
    await onChange.close();
    await onEventAdded.close();
    await onRemove.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MatrixClient client;
  late MatrixRoom room;
  var sequence = 0;
  MatrixTimelineEventZooid tool(String id,
          {String type = 'dev.zooid.tool_call', String status = 'pending'}) =>
      room.convertEvent(matrix.Event.fromJson({
        'event_id': id,
        'type': type,
        'sender': fixture.me,
        'origin_server_ts': 1700000000000,
        'content': {
          'session_id': 'session',
          'tool_call_id': 'tool',
          'title': 'Inspect configuration',
          'status': status,
          'm.relates_to': {'rel_type': 'm.thread', 'event_id': r'$root'}
        }
      }, room.matrixRoom)) as MatrixTimelineEventZooid;

  setUp(() async {
    client = await fixture.signedInClient('activity-${sequence++}',
        respond: (request) => request.url.path.contains('/state/m.room.member/')
            ? http.Response('{"membership":"join","displayname":"Me"}', 200)
            : null);
    await fixture.sync(client, join: {
      '!activity:example.com': matrix.JoinedRoomUpdate(
          state: fixture.roomState('!activity:example.com'))
    });
    room = client.getRoom('!activity:example.com')! as MatrixRoom;
    await room.matrixRoom.requestUser(fixture.me);
  });
  tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

  Widget row(MatrixTimelineEventZooid event, Timeline timeline) => MaterialApp(
      home: Scaffold(
          body: TimelineEventViewZooid(
              event: event, room: room, timeline: timeline)));

  testWidgets('the 200-event window preserves an older visible owner honestly',
      (tester) async {
    final parent = tool(r'$parent');
    final done =
        tool(r'$done', type: 'dev.zooid.tool_call_update', status: 'completed');
    final timeline = _ActivityTimeline(
        [done, for (var i = 0; i < 199; i++) tool('\$filler$i'), parent]);
    await tester.pumpWidget(row(parent, timeline));
    expect(find.textContaining('Status unavailable'), findsOneWidget);
    expect(find.textContaining('Completed (reported)'), findsNothing);
    timeline.onRemove.add(1);
    timeline.events.removeAt(1);
    // An unrelated removal need not recompute; rebuilding the received event
    // evaluates the current bounded window, now containing the parent.
    await tester.pumpWidget(row(tool(r'$parent'), timeline));
    expect(find.textContaining('Completed (reported)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await timeline.close();
  });

  testWidgets('removal, timeline replacement and disposal release old activity',
      (tester) async {
    final parent = tool(r'$parent');
    final done =
        tool(r'$done', type: 'dev.zooid.tool_call_update', status: 'completed');
    final old = _ActivityTimeline([done, parent]);
    await tester.pumpWidget(row(parent, old));
    expect(find.textContaining('Completed (reported)'), findsOneWidget);
    old.onRemove.add(0);
    old.events.removeAt(0);
    await tester.pump();
    expect(find.textContaining('Pending'), findsOneWidget);
    final next = _ActivityTimeline([tool(r'$next', status: 'failed')]);
    await tester
        .pumpWidget(row(next.events.single as MatrixTimelineEventZooid, next));
    expect(find.textContaining('Failed (reported)'), findsOneWidget);
    old.events.insert(0, done);
    old.onEventAdded.add(0);
    await tester.pump();
    expect(find.textContaining('Failed (reported)'), findsOneWidget);
    expect(old.onChange.hasListener, isFalse);
    expect(old.onRemove.hasListener, isFalse);
    expect(old.onEventAdded.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(next.onChange.hasListener, isFalse);
    next.onChange.add(0);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await old.close();
    await next.close();
  });
}
