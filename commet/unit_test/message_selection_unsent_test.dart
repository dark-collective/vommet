import 'dart:async';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_bar.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as mx;
import 'package:shared_preferences/shared_preferences.dart';

import 'message_selection_download_test.dart'
    show SelectionRoom, SelectionTimeline;

class _Db extends Fake implements mx.DatabaseApi {
  final removed = <String>[];
  @override
  Future<void> removeEvent(String eventId, String roomId) async {
    removed.add(eventId);
  }
}

class _Sdk extends mx.Client {
  _Sdk(super.clientName, {required super.database});
  @override
  String get userID => '@me:test';
  final writes = <Map<String, Object?>>[];
  @override
  Future<void> setAccountData(
      String userId, String type, Map<String, Object?> data) async {
    writes.add(data);
  }
}

class _SdkRoom extends mx.Room {
  _SdkRoom(mx.Client client) : super(id: '!room:test', client: client);
  final submitted = <String>[];
  final pending = <Completer<String?>>[];
  Map<String, dynamic>? fileMetadata;
  @override
  Future<String?> sendFileEvent(mx.MatrixFile file,
      {String? txid,
      mx.Event? inReplyTo,
      String? editEventId,
      int? shrinkImageMaxDimension,
      mx.MatrixImageFile? thumbnail,
      Map<String, dynamic>? extraContent,
      String? threadRootEventId,
      String? threadLastEventId,
      bool displayPendingEvent = true}) async {
    submitted.add(txid!);
    fileMetadata = extraContent;
    return 'remote-file';
  }

  bool allowed = true;
  @override
  bool get canSendDefaultMessages => allowed;
  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = mx.EventTypes.Message,
    String? txid,
    mx.Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) {
    submitted.add(txid!);
    final gate = Completer<String?>();
    pending.add(gate);
    return gate.future;
  }
}

class _Client extends Fake implements MatrixClient {
  _Client(this.matrixClient);
  @override
  final mx.Client matrixClient;
  @override
  String get identifier => 'selected';
  @override
  T? getComponent<T extends Component>() => null;
}

class _Message extends MatrixTimelineEvent implements TimelineEventMessage {
  _Message(mx.Event event) : super(event, client: _Client(event.room.client));
  @override
  List<Attachment> get attachments => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room extends SelectionRoom {
  _Room(this.client);
  @override
  final _Client client;
  bool failCancel = false;
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  Future<void> cancelSend(TimelineEvent event) async {
    if (failCancel && event.eventId == 'b') throw StateError('fixture');
    await (event as MatrixTimelineEvent).event.cancelSend();
  }
}

void main() {
  late _Sdk sdk;
  late _SdkRoom sdkRoom;
  late _Db db;
  late _Room room;
  late SelectionTimeline timeline;
  late MessageSelection selection;
  _Message message(String id, int status,
          {String? tx,
          String type = 'm.room.message',
          String msgtype = 'm.text',
          String sender = '@me:test'}) =>
      _Message(mx.Event(
          room: sdkRoom,
          status: {
            -1: mx.EventStatus.error,
            0: mx.EventStatus.sending,
            1: mx.EventStatus.sent,
            2: mx.EventStatus.synced
          }[status]!,
          eventId: id,
          type: type,
          senderId: sender,
          originServerTs: DateTime(2026),
          content: {'msgtype': msgtype, 'body': id},
          unsigned: {'status': status, if (tx != null) 'transaction_id': tx}));
  void select(List<TimelineEvent> newestFirst) {
    timeline = SelectionTimeline(room, newestFirst);
    selection = MessageSelection(room)..timeline = timeline;
    selection.start(newestFirst.map((e) => e.eventId).toList());
  }

  Future<void> harness(WidgetTester t,
      {double width = 1100, double scale = 1}) async {
    t.view.physicalSize = Size(width, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 800), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
                body: Column(children: [MessageSelectionBar(selection)])))));
    await t.pump();
  }

  Future<void> confirm(WidgetTester t) async {
    await t.tap(find.text('Cancel sending 2').first);
    await t.pumpAndSettle();
    expect(find.textContaining('may still be delivered'), findsOneWidget);
    await t.tap(find.text('Cancel sending 2').last);
    await t.pumpAndSettle();
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.experimentSelectMessages.set(true);
    db = _Db();
    sdk = _Sdk('selected', database: db);
    sdkRoom = _SdkRoom(sdk);
    room = _Room(_Client(sdk));
    selection = MessageSelection(room);
  });
  tearDown(() async {
    selection.dispose();
    for (final gate in sdkRoom.pending) {
      if (!gate.isCompleted) gate.complete(null);
    }
    await sdk.dispose(closeDatabase: false);
  });
  test('own failed and sending echoes can be ticked, other senders cannot', () {
    select([]);
    expect(MessageSelection.canTick(message('a', -1), timeline), isTrue);
    expect(MessageSelection.canTick(message('b', 0), timeline), isTrue);
    expect(
        MessageSelection.canTick(
            message('c', -1, sender: '@other:test'), timeline),
        isFalse);
  });
  test(
      'selection and range anchor survive replacement and lost transaction metadata',
      () async {
    select([message('older', 2), message('txn', -1, tx: 'txn')]);
    selection.start(['txn']);
    timeline.events[1] = message(r'$remote', 1, tx: 'txn');
    timeline.onChange.add(1);
    await Future<void>.delayed(Duration.zero);
    timeline.events[1] = message(r'$remote', 2);
    timeline.onChange.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(selection.isTicked([r'$remote']), isTrue);
    expect(selection.ticked.length, 1);
    selection.tickRangeTo(['older']);
    expect(
        selection.tickedEvents().map((e) => e.eventId), [r'$remote', 'older']);
  });
  test(
      'drag snapshots and duplicate echo/remote entries retain one logical tick',
      () async {
    select([message('next', 2), message('txn', -1, tx: 'txn')]);
    selection.start(['next']);
    selection.dragStart(['txn']);
    timeline.events[1] = message(r'$remote', 1, tx: 'txn');
    timeline.onChange.add(1);
    await Future<void>.delayed(Duration.zero);
    timeline.events.add(message('txn', -1, tx: 'txn'));
    expect(selection.isAnyTicked([r'$remote']), isTrue);
    expect(selection.tickedEvents().length, 2);
    selection.dragEnd();
    selection.toggle([r'$remote']);
    expect(selection.isAnyTicked(['txn', r'$remote']), isFalse);
  });
  testWidgets(
      'mixed counts and retry handoff never wait for delivery or submit twice',
      (t) async {
    select([
      message('sending', 0),
      message('b', -1),
      message('a', -1),
      message('synced', 2),
      message('sent', 1)
    ]);
    await harness(t);
    expect(find.text('Retry 2'), findsOneWidget);
    expect(find.text('Cancel sending 3'), findsOneWidget);
    expect(find.text('Sent actions (1)'), findsOneWidget);
    await t.tap(find.text('Retry 2'));
    await t.pump();
    expect(sdkRoom.submitted, ['a', 'b']);
    expect(find.text('Retry 0'), findsOneWidget);
    sdkRoom.pending[0].complete(null);
    await t.pump();
    expect(find.textContaining('Retry failed'), findsOneWidget);
    expect(find.text('Retry 1'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('missing file remains and Done only closes selection', (t) async {
    select([message('file', -1, msgtype: 'm.file')]);
    await harness(t);
    expect(find.text('Retry 0'), findsOneWidget);
    expect(find.textContaining('File unavailable; attach it again.'),
        findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pump();
    expect(db.removed, isEmpty);
    expect(sdkRoom.submitted, isEmpty);
    expect(selection.active, isFalse);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets(
      'cached attachment retry preserves fallback txid and thread relation',
      (t) async {
    final file = message('file', -1, msgtype: 'm.file');
    file.event.unsigned!['extra_content'] = {
      'm.relates_to': {'rel_type': 'm.thread', 'event_id': r'$root'}
    };
    sdkRoom.sendingFilePlaceholders['file'] =
        mx.MatrixFile(bytes: Uint8List.fromList([1]), name: 'file');
    select([file]);
    await harness(t);
    await t.tap(find.text('Retry 1'));
    await t.pump();
    expect(sdkRoom.submitted, ['file']);
    expect(sdkRoom.fileMetadata?['m.relates_to'],
        {'rel_type': 'm.thread', 'event_id': r'$root'});
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('lost permission never becomes a Retry target', (t) async {
    select([message('text', -1)]);
    sdkRoom.allowed = false;
    await harness(t);
    expect(find.text('Retry 0'), findsOneWidget);
    expect(
        find.textContaining('You cannot send to this room.'), findsOneWidget);
    expect(sdkRoom.submitted, isEmpty);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('unsupported sticker is not retried as an ordinary message',
      (t) async {
    select([message('sticker', -1, type: 'm.sticker')]);
    await harness(t);
    expect(find.text('Retry 0'), findsOneWidget);
    expect(
        find.textContaining('This message cannot be retried.'), findsOneWidget);
    expect(sdkRoom.submitted, isEmpty);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('mixed sent menu filters Copy and Download to synced items',
      (t) async {
    select([message('failed', -1), message('synced', 2)]);
    await harness(t);
    await t.tap(find.text('Sent actions (1)'));
    await t.pumpAndSettle();
    expect(find.text('Copy 1'), findsOneWidget);
    expect(find.text('Download 0'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('Cancel continues after failure and retains unsuccessful ticks',
      (t) async {
    select([message('b', -1), message('a', -1)]);
    room.failCancel = true;
    await harness(t);
    await confirm(t);
    expect(db.removed, ['a']);
    expect(selection.ticked.ids, ['b']);
    expect(find.textContaining('Could not remove'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('Cancel rechecks a message that becomes sent during confirmation',
      (t) async {
    select([message('b', -1), message('a', 0)]);
    await harness(t);
    await t.tap(find.text('Cancel sending 2'));
    await t.pumpAndSettle();
    timeline.events[1] = message(r'$sent', 1, tx: 'a');
    timeline.onChange.add(1);
    await t.pump();
    await t.tap(find.text('Cancel sending 2').last);
    await t.pumpAndSettle();
    expect(db.removed, ['b']);
    expect(selection.isTicked([r'$sent']), isTrue);
    expect(find.textContaining('1 unavailable or already sent'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('late success after local removal stays unselected', (t) async {
    select([message('b', 0), message('a', -1)]);
    await harness(t);
    await confirm(t);
    expect(db.removed, ['a', 'b']);
    expect(selection.active, isFalse);
    timeline.events.add(message(r'$late', 2, tx: 'b'));
    timeline.onEventAdded.add(2);
    await t.pump();
    expect(selection.isAnyTicked([r'$late']), isFalse);
    expect(find.textContaining('may still arrive'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('closing a retry cannot mutate a new selection', (t) async {
    select([message('a', -1)]);
    await harness(t);
    await t.tap(find.text('Retry 1'));
    await t.pump();
    selection.exit();
    selection.start(['other']);
    sdkRoom.pending.single.complete(null);
    await t.pump();
    expect(selection.ticked.ids, ['other']);
    expect(find.textContaining('Retry failed'), findsNothing);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('320 px at 200% text wraps labels without overflow', (t) async {
    select([message('a', -1), message('sent', 2)]);
    await harness(t, width: 320, scale: 2);
    expect(find.text('Cancel sending 1'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('mixed Save writes synced IDs only and keeps unsent ticks',
      (t) async {
    select([message('failed', -1), message('synced', 2)]);
    await harness(t);
    await t.tap(find.text('Sent actions (1)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save 1 message'));
    await t.pumpAndSettle();
    expect(
        Bookmarks.parse(sdk.writes.single).map((b) => b.eventId), ['synced']);
    expect(selection.ticked.ids, ['failed']);
    expect(find.text('Retry 1'), findsOneWidget);
    expect(find.text('Cancel sending 1'), findsOneWidget);
  });
  testWidgets('newly synced Save unticks the original local token', (t) async {
    select([message('txn', -1, tx: 'txn')]);
    await harness(t);
    timeline.events[0] = message(r'$remote', 1, tx: 'txn');
    timeline.onChange.add(0);
    await t.pumpAndSettle();
    expect(find.text('Retry 0'), findsOneWidget);
    expect(find.text('Cancel sending 0'), findsOneWidget);
    timeline.events[0] = message(r'$remote', 2);
    timeline.onChange.add(0);
    await t.pumpAndSettle();
    expect(selection.isTicked([r'$remote']), isTrue);
    await t.tap(find.text('Sent actions (1)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save 1 message'));
    await t.pumpAndSettle();
    expect(
        Bookmarks.parse(sdk.writes.single).map((b) => b.eventId), [r'$remote']);
    expect(selection.ticked.isEmpty, isTrue);
    expect(selection.active, isFalse);
    expect(sdkRoom.submitted, isEmpty);
    expect(db.removed, isEmpty);
  });
  for (final dismiss in [false, true]) {
    testWidgets(
        'cancel ${dismiss ? 'dismiss' : 'Keep messages'} keeps local sends',
        (t) async {
      select([message('a', -1)]);
      await harness(t);
      await t.tap(find.text('Cancel sending 1'));
      await t.pumpAndSettle();
      if (dismiss) {
        Navigator.of(t.element(find.text('Keep messages'))).pop();
      } else {
        await t.tap(find.text('Keep messages'));
      }
      await t.pumpAndSettle();
      expect(selection.isTicked(['a']), isTrue);
      expect(selection.busy, isFalse);
      expect(db.removed, isEmpty);
      expect(sdkRoom.submitted, isEmpty);
      expect(find.text('Retry 1'), findsOneWidget);
    });
  }
  testWidgets('unavailable local send remains selected and cannot run actions',
      (t) async {
    select([message('a', -1)]);
    await harness(t);
    timeline.onRemove.add(0);
    timeline.events.clear();
    await t.pumpAndSettle();
    expect(find.text('1 unavailable'), findsOneWidget);
    expect(find.text('Retry 0'), findsOneWidget);
    expect(find.text('Cancel sending 0'), findsOneWidget);
    expect(selection.ticked.ids, ['a']);
    expect(db.removed, isEmpty);
  });
  for (final error in [
    StateError('transport'),
    mx.MatrixException(http.Response(
        '{"errcode":"M_LIMIT_EXCEEDED","retry_after_ms":60000}', 429)),
    mx.MatrixException(http.Response('{"errcode":"M_FORBIDDEN"}', 403)),
  ]) {
    testWidgets(
        'SDK $error stops after one handoff and shared room selections cannot duplicate',
        (t) async {
      select([message('a', -1)]);
      final other = MessageSelection(room)..timeline = timeline;
      other.start(['a']);
      addTearDown(other.dispose);
      await harness(t);
      await t.tap(find.text('Retry 1'));
      other.retrySelected();
      expect(sdkRoom.submitted, ['a']);
      sdkRoom.pending.single.completeError(error);
      await t.pump();
      expect(find.textContaining('Retry failed'), findsOneWidget);
      await t.pump(const Duration(minutes: 10));
      expect(sdkRoom.submitted, ['a']);
      expect(find.text('Retry 1'), findsOneWidget);
      expect(selection.isTicked(['a']), isTrue);
    });
  }
  for (final style in LayoutStyle.values) {
    for (final width in [320.0, 1100.0]) {
      testWidgets(
          'real header $style $width grows, restores and replaces timeline',
          (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await pickLayoutStyle(style);
        if (style == LayoutStyle.custom)
          await preferences.chatBubbleLayout.set(true);
        select([message('failed', -1), message('synced', 2)]);
        final replacement =
            SelectionTimeline(room, [message('replacement', 2)]);
        late MessageSelection hosted;
        final header = find.byKey(const ValueKey('actual-header'));
        Future<void> pump(SelectionTimeline source) async {
          t.view.physicalSize = Size(width, 800);
          t.view.devicePixelRatio = 1;
          await t.pumpWidget(MaterialApp(
              home: MediaQuery(
                  data: MediaQueryData(
                      size: Size(width, 800),
                      textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
                  child: Scaffold(
                      body: MessageSelectionHost(
                          room: room,
                          timeline: source,
                          child: Builder(builder: (context) {
                            hosted = MessageSelectionScope.maybeOf(context)!;
                            return Column(children: [
                              MessageSelectionBar.sizedHeader(room,
                                  child: KeyedSubtree(
                                      key: const ValueKey('actual-header'),
                                      child: MessageSelectionBar.orHeader(room,
                                          (_) => const Text('Room header'))))
                            ]);
                          }))))));
          await t.pumpAndSettle();
        }

        await pump(timeline);
        expect(find.text('Room header'), findsOneWidget);
        hosted.start(['synced']);
        await t.pumpAndSettle();
        expect(t.getSize(header).height, 50);
        // Existing accepted normal Save is still reachable before adding a local send.
        if (find
            .byKey(const ValueKey('message-selection-more'))
            .evaluate()
            .isNotEmpty) {
          await t.tap(find.byKey(const ValueKey('message-selection-more')));
          await t.pumpAndSettle();
        }
        await t.tap(find.text('Save 1 message'));
        await t.pumpAndSettle();
        expect(Bookmarks.parse(sdk.writes.single).single.eventId, 'synced');
        expect(hosted.active, isFalse);
        hosted.start(['synced']);
        await t.pumpAndSettle();
        hosted.toggle(['failed']);
        await t.pumpAndSettle();
        expect(find.text('Retry 1'), findsOneWidget);
        expect(t.getSize(header).height, greaterThan(50));
        await t.tap(find.text('Done'));
        await t.pumpAndSettle();
        expect(find.text('Room header'), findsOneWidget);
        hosted.start(['failed']);
        await t.pumpAndSettle();
        await pump(replacement);
        expect(find.text('Room header'), findsOneWidget);
        expect(timeline.onChange.hasListener,
            isTrue); // direct fixture selection remains
        await t.pumpWidget(const SizedBox());
        timeline.onChange.add(0);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        t.view.reset();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
