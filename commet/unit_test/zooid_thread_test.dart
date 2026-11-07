// Vommet issue 982: real conversion, bounded network previews and passive UI.
import 'dart:async';
import 'dart:convert';

import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/matrix/components/threads/matrix_threads_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_deleted_message.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_deleted.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/generated/intl/messages_all.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/thread_card.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_thread.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_view_single.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:commet/ui/organisms/room_threads_list/room_threads_list_widget.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart' as fixture;

const roomId = '!zooid:example.com';
const rootId = r'$root';
const sender = '@zooid:example.com';

Map<String, dynamic> raw(String id, String type,
        [Map<String, dynamic> fields = const {}]) =>
    {
      'type': type,
      'event_id': id,
      'room_id': roomId,
      'sender': sender,
      'origin_server_ts': 1700000000000,
      'content': {
        'session_id': 's1',
        'm.relates_to': {'rel_type': 'm.thread', 'event_id': rootId},
        ...fields
      },
    };

class _Timeline extends Fake implements MatrixTimeline {
  _Timeline(this.room, this.events);
  @override
  final MatrixRoom room;
  @override
  MatrixClient get client => room.client as MatrixClient;
  @override
  final List<TimelineEvent> events;
  @override
  bool isEventRedacted(TimelineEvent event) =>
      (event as MatrixTimelineEvent).event.redacted;
  @override
  String getDisplayId(TimelineEvent event) => event.eventId;
  @override
  TimelineEvent? tryGetEvent(String id) =>
      events.where((e) => e.eventId == id).firstOrNull;
  @override
  matrix.Timeline? get matrixTimeline => null;
  @override
  DeletedMessageInfo? deletedMessageInfo(TimelineEvent event) =>
      matrixDeletedMessageInfo((event as MatrixTimelineEvent).event);
  @override
  bool canDeleteEvent(TimelineEvent event) => false;
  @override
  final onChange = StreamController<int>.broadcast();
  @override
  final onEventAdded = StreamController<int>.broadcast(sync: true);
  @override
  final onRemove = StreamController<int>.broadcast(sync: true);
}

class _Threads extends MatrixThreadsComponent {
  _Threads(super.client, this.summary);
  final ThreadSummary summary;
  @override
  ThreadSummary? getThreadSummary(TimelineEvent root, Timeline timeline) =>
      summary;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeMessages('en');
    Intl.defaultLocale = 'en';
  });
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MatrixClient client;
  late MatrixRoom room;
  late List<Map<String, dynamic>> recent;
  late Map<String, dynamic> root;
  late List<Uri> requests;
  var failRoot = false;
  var missingCount = false;
  var sequence = 0;
  TimelineEvent convert(Map<String, dynamic> json) =>
      room.convertEvent(matrix.Event.fromJson(json, room.matrixRoom));

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await fixture.signedInClient('zooid-${sequence++}');
    await fixture.sync(client, join: {
      roomId: matrix.JoinedRoomUpdate(
        state: [
          ...fixture.roomState(roomId),
          fixture.stateEvent(
              'm.room.member', {'membership': 'join', 'displayname': 'Zooid'},
              stateKey: sender)
        ],
      )
    });
    room = client.getRoom(roomId)! as MatrixRoom;
    recent = [
      raw(r'$end', 'dev.zooid.turn.end', {
        'agent_id': 'zooid',
        'body': 'zooid finished',
        'produced_output': true
      }),
      for (var i = 0; i < 4; i++)
        raw('\$commands$i', 'dev.zooid.available_commands_update',
            {'available_commands': []}),
      raw(r'$notice', 'm.room.message',
          {'msgtype': 'm.notice', 'body': 'I reviewed the configuration.'}),
    ];
    root = raw(rootId, 'm.room.message',
        {'msgtype': 'm.text', 'body': 'Review the configuration.'});
    root['sender'] = fixture.me;
    (root['content'] as Map)
      ..remove('m.relates_to')
      ..remove('session_id');
    root['unsigned'] = {
      'm.relations': {
        'm.thread': {'count': 6, 'latest_event': recent.first}
      }
    };
    requests = [];
    failRoot = false;
    missingCount = false;
    fixture.stubResponse = (request) {
      final url = request.url;
      if (url.path.contains('/state/m.room.member/')) {
        return http.Response(
            jsonEncode({'membership': 'join', 'displayname': 'Zooid'}), 200);
      }
      if (url.path.endsWith('/threads')) {
        return http.Response(
            jsonEncode({
              'chunk': [root]
            }),
            200);
      }
      if (url.path.contains('/event/')) {
        if (failRoot) return http.Response('{}', 500);
        return http.Response(
            jsonEncode(missingCount ? {...root, 'unsigned': {}} : root), 200);
      }
      if (url.path.contains('/relations/')) {
        requests.add(url);
        return http.Response(
            jsonEncode({
              'chunk':
                  url.queryParameters['dir'] == 'f' ? [recent.last] : recent,
              'next_batch': 'older'
            }),
            200);
      }
      return null;
    };
    // Prime SDK participant caches outside the widget test's fake timer zone.
    await room.matrixRoom.requestUser(sender);
    await room.matrixRoom.requestUser(fixture.me);
  });
  tearDown(() async {
    fixture.stubResponse = null;
    await client.getMatrixClient().dispose(closeDatabase: true);
  });

  ThreadSummary summary() => ThreadSummary(
      root: convert(root), latestReply: convert(recent.first), replyCount: 6);

  test('unknown previews and quotes never invent a deletion', () {
    final unknown = convert(raw(r'$future', 'dev.example.future'));
    expect(ThreadListTile.bodyOf(unknown), 'Unsupported event');
    expect(TimelineEventViewReply.quotedText(unknown, _Timeline(room, [])),
        'Unsupported event');
    final deleted = raw(r'$deleted', 'm.room.message');
    deleted['unsigned'] = {
      'redacted_because': raw(r'$redaction', 'm.room.redaction')
    };
    expect(ThreadListTile.bodyOf(convert(deleted)), 'Message deleted');
  });

  test('reported event counts are not message reply counts', () {
    expect(ThreadCard.countLabel(6), '6 events reported');
  });

  test('the six-event report yields the notice without altering its total',
      () async {
    final extras = await MatrixThreadsComponent(client)
        .loadThreadPreviewExtras(room, summary(), withFirstReply: true);
    expect(extras.latestReply?.eventId, r'$notice');
    expect(extras.firstReply?.eventId, r'$notice');
    expect(extras.replyCount, 6);
    expect(extras.recentSenderIds, [sender]);
    expect(requests.map((u) => u.queryParameters['limit']), ['20', '1']);
  });

  test('twenty controls do not prove an empty thread or trigger backfill',
      () async {
    recent = [
      for (var i = 0; i < 20; i++)
        raw('\$control$i', 'dev.zooid.available_commands_update',
            {'available_commands': []})
    ];
    final extras = await MatrixThreadsComponent(client)
        .loadThreadPreviewExtras(room, summary(), withFirstReply: true);
    expect(extras.latestReply, isNull);
    expect(extras.firstReply, isNull);
    expect(extras.replyCount, 6);
    expect(extras.recentSenderIds, isEmpty);
    expect(requests, hasLength(2));
  });

  test('a root with no aggregate does not invent zero events', () async {
    missingCount = true;
    final extras = await MatrixThreadsComponent(client)
        .loadThreadPreviewExtras(room, summary());
    expect(extras.replyCount, isNull);
  });

  test('a failed root fetch still filters the available sample', () async {
    failRoot = true;
    final extras = await MatrixThreadsComponent(client)
        .loadThreadPreviewExtras(room, summary());
    expect(extras.latestReply?.eventId, r'$notice');
    expect(extras.replyCount, isNull);
  });

  testWidgets('a missing aggregate renders activity without a fabricated zero',
      (tester) async {
    root['unsigned'] = {
      'm.relations': {
        'm.thread': {'latest_event': recent.first}
      }
    };
    final page = await tester
        .runAsync(() => MatrixThreadsComponent(client).listThreads(room));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ThreadListTile(
                room: room, thread: page!.threads.single, unread: false))));
    await tester.pumpAndSettle();
    expect(find.text('Thread activity'), findsOneWidget);
    expect(find.text('0 events reported'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('First mode does not replace a control event with a later reply',
      (tester) async {
    await preferences.threadPreviewMode.set('first');
    recent = [recent.last, recent.first];
    final timeline = _Timeline(room, [convert(root)]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TimelineEventViewThread(
                initialIndex: 0,
                timeline: timeline,
                component: _Threads(client, summary())))));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('First reply preview unavailable'), findsOneWidget);
    expect(find.text('I reviewed the configuration.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await timeline.onChange.close();
    await timeline.onEventAdded.close();
    await timeline.onRemove.close();
  });

  for (final style in LayoutStyle.values) {
    for (final size in [const Size(360, 780), const Size(1280, 800)]) {
      testWidgets(
          'honest preview and passive activity in $style at ${size.width}',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        if (style == LayoutStyle.custom) {
          await LayoutOptions.discord.save();
          await preferences.chatBubbleLayout.set(true);
        }
        await pickLayoutStyle(style);
        await preferences.layoutOverride
            .set(size.width < 600 ? 'mobile' : 'desktop');
        final timeline = _Timeline(room, [convert(root)]);
        final component = _Threads(client, summary());
        await tester.pumpWidget(MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Column(children: [
              TimelineEventViewThread(
                  initialIndex: 0, timeline: timeline, component: component),
              TimelineEventViewSingle(
                  room: room,
                  event: convert(raw(r'$tool', 'dev.zooid.tool_call', {
                    'tool_call_id': 't1',
                    'title': 'Read configuration',
                    'status': 'in_progress'
                  }))),
              TimelineEventViewSingle(room: room, event: convert(recent.first)),
            ])))));
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(find.text('I reviewed the configuration.'), findsOneWidget);
        expect(find.text('6 events reported'), findsOneWidget);
        expect(find.textContaining('Working (reported)'), findsOneWidget);
        expect(find.text('Finished (turn ended)'), findsOneWidget);
        expect(find.text('Message deleted'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await timeline.onChange.close();
        await timeline.onEventAdded.close();
        await timeline.onRemove.close();
      });
    }
  }

  testWidgets(
      'read-only rows handle orphan, unknown status and empty text honestly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: Column(children: [
              TimelineEventViewSingle(
                  room: room,
                  event: convert(raw(r'$orphan', 'dev.zooid.tool_call_update',
                      {'tool_call_id': 'missing', 'status': 'future_status'}))),
              TimelineEventViewSingle(
                  room: room,
                  event: convert(raw(r'$empty', 'dev.zooid.turn.end', {
                    'produced_output': false,
                    'stop_reason': 'arbitrary',
                    'last_message': 'not a reply'
                  }))),
              TimelineEventViewSingle(
                  room: room,
                  event: convert(raw(r'$invalid', 'dev.zooid.tool_call',
                      {'tool_call_id': 'bad', 'title': 123}))),
            ]))))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tool activity · details unavailable'),
        findsOneWidget);
    expect(find.textContaining('Status unavailable'), findsOneWidget);
    expect(find.textContaining('No text reply reported'), findsOneWidget);
    expect(find.textContaining('not a reply'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'loaded tool updates fold, preserve omitted status and react to redaction',
      (tester) async {
    final call = convert(raw(r'$tool', 'dev.zooid.tool_call', {
      'tool_call_id': 't1',
      'title': 'Read configuration',
      'status': 'pending'
    }));
    final timeline = _Timeline(room, [
      convert(raw(
          r'$sparse', 'dev.zooid.tool_call_update', {'tool_call_id': 't1'})),
      convert(raw(r'$done', 'dev.zooid.tool_call_update',
          {'tool_call_id': 't1', 'status': 'completed'})),
      call,
    ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      for (var i = 0; i < timeline.events.length; i++)
        TimelineViewEntry(
            key: ValueKey(timeline.events[i].eventId),
            timeline: timeline,
            initialIndex: i,
            isThreadTimeline: true),
    ]))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Read configuration'), findsOneWidget);
    expect(find.textContaining('Completed (reported)'), findsOneWidget);
    timeline.events[1] = convert({
      ...raw(r'$done', 'dev.zooid.tool_call_update'),
      'unsigned': {'redacted_because': raw(r'$redact', 'm.room.redaction')}
    });
    timeline.onChange.add(1);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pending'), findsOneWidget);
    expect(find.textContaining('Completed (reported)'), findsNothing);
    timeline.events.insert(
        0,
        convert({
          ...raw(r'$foreign', 'dev.zooid.tool_call_update',
              {'tool_call_id': 't1', 'status': 'completed'}),
          'sender': '@other:example.com'
        }));
    timeline.onEventAdded.add(0);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pending'), findsOneWidget);
    expect(find.textContaining('Completed (reported)'), findsNothing);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await timeline.onChange.close();
    await timeline.onEventAdded.close();
    await timeline.onRemove.close();
  });

  testWidgets(
      'empty samples, unknown totals and both/divider modes stay honest',
      (tester) async {
    final original = recent;
    Future<void> show(String mode,
        {bool divider = false, int count = 6}) async {
      await preferences.threadPreviewMode.set(mode);
      final timeline = _Timeline(room, [convert(root)]);
      final component = _Threads(
          client,
          ThreadSummary(
              root: convert(root),
              latestReply: original.isEmpty ? null : convert(original.first),
              replyCount: count));
      await tester.runAsync(() => component.loadThreadPreviewExtras(
          room, component.summary,
          withFirstReply: !divider && mode != 'latest'));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TimelineEventViewThread(
                  key: UniqueKey(),
                  initialIndex: 0,
                  timeline: timeline,
                  inThread: divider,
                  component: component))));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      addTearDown(() async {
        await timeline.onChange.close();
        await timeline.onEventAdded.close();
        await timeline.onRemove.close();
      });
    }

    await show('both');
    expect(find.text('I reviewed the configuration.'), findsOneWidget);
    expect(find.text('6 events reported'), findsOneWidget);
    await show('latest', divider: true);
    expect(find.text('6 events reported'), findsOneWidget);
    expect(find.byType(ThreadCard), findsNothing);
    recent = [];
    (root['unsigned'] as Map)['m.relations']['m.thread']['count'] = 0;
    await show('latest', count: 0);
    expect(find.byType(ThreadCard), findsNothing);
    missingCount = true;
    await show('latest');
    expect(find.text('No reply preview in loaded activity'), findsOneWidget);
    expect(find.text('6 events reported'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'received status variants and malformed scoping do not invent actions',
      (tester) async {
    for (final pair in <(Object?, String)>[
      ('pending', 'Pending'),
      ('failed', 'Failed (reported)'),
      (null, 'Status unavailable'),
      ('future', 'Status unavailable')
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TimelineEventViewSingle(
                  room: room,
                  event: convert(raw(r'$status', 'dev.zooid.tool_call', {
                    'title': 'Inspect',
                    'tool_call_id': 't',
                    if (pair.$1 != null) 'status': pair.$1
                  }))))));
      await tester.pumpAndSettle();
      expect(find.textContaining(pair.$2), findsOneWidget);
    }
    for (final fields in <Map<String, dynamic>>[
      {'session_id': ''},
      {'tool_call_id': ''},
      {
        'm.relates_to': {'rel_type': 'm.reference', 'event_id': rootId}
      },
      {
        'm.relates_to': {'rel_type': 'm.thread', 'event_id': ''}
      },
    ]) {
      final event = convert(raw(r'$invalid-scope', 'dev.zooid.tool_call',
          {'title': 'Inspect', 'tool_call_id': 't', ...fields}));
      expect(ThreadListTile.bodyOf(event), 'Unsupported event');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'manual reload after SDK denial stays bounded and filters activity',
      (tester) async {
    final originalStub = fixture.stubResponse;
    for (final status in [429, 403]) {
      var calls = 0;
      fixture.stubResponse = (request) {
        if (request.url.path.contains('/relations/')) {
          calls++;
          return http.Response(
              jsonEncode({
                'errcode': status == 429 ? 'M_LIMIT_EXCEEDED' : 'M_FORBIDDEN',
                'error': 'unavailable',
                if (status == 429) 'retry_after_ms': 30000
              }),
              status);
        }
        return originalStub?.call(request);
      };
      final component = MatrixThreadsComponent(client);
      await tester.runAsync(() async {
        await expectLater(component.loadThreadPreviewExtras(room, summary()),
            throwsA(isA<matrix.MatrixException>()));
      });
      expect(calls, 1);
      await tester.pump(const Duration(minutes: 2));
      expect(calls, 1);
    }
    fixture.stubResponse = originalStub;
    final recovered = await tester.runAsync(() => MatrixThreadsComponent(client)
        .loadThreadPreviewExtras(room, summary()));
    expect(recovered!.latestReply?.eventId, r'$notice');
  });
}
