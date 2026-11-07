import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as mx;

import 'support/room_page_fixtures.dart';

// Only the SDK transport boundary is faked; the entry, event and selection are real.
class _Transport extends mx.Room {
  _Transport(MatrixRoom room)
      : super(id: room.identifier, client: roomPageClient.matrixClient);
  final submitted = <String>[];
  @override
  bool get canSendDefaultMessages => true;
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
  }) async {
    submitted.add(txid!);
    return r'$retried';
  }
}

void main() {
  setUp(roomPageSetUp);
  tearDown(roomPageTearDown);
  testWidgets(
      'real selected entry keeps Save and routes restricted Retry/Cancel',
      (t) async {
    t.view.physicalSize = const Size(1100, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final room = roomFor(RoomCase.messages) as MatrixRoom;
    final timeline = await room.getTimeline() as MatrixTimeline;
    final original = timeline.events.first;
    final transport = _Transport(room);
    final local = MatrixTimelineEventMessage(
        mx.Event(
            room: transport,
            eventId: 'local',
            senderId: roomPageClient.matrixClient.userID!,
            type: mx.EventTypes.Message,
            status: mx.EventStatus.error,
            originServerTs: DateTime(2026),
            unsigned: {'transaction_id': 'local', 'status': -1},
            content: {'body': 'Local failed message', 'msgtype': 'm.text'}),
        client: roomPageClient);
    timeline.events.insert(0, local);
    timeline.notifyChanged(0);
    final selection = MessageSelection(room)..timeline = timeline;
    selection.start(['local', original.eventId]);
    try {
      await preferences.experimentSelectMessages.set(true);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MessageSelectionScope(
                  selection: selection,
                  child: TimelineViewEntry(
                      timeline: timeline, initialIndex: 0)))));
      await t.pump();
      expect(find.text('Local failed message'), findsWidgets);
      final entry =
          t.state<TimelineViewEntryState>(find.byType(TimelineViewEntry));
      final items = entry.selectionMenuItems()!;
      expect(items.map((i) => i.text),
          containsAll(['Save 1 message', 'Retry 1', 'Cancel sending 1']));
      // Open the real menu route; only SDK transport is controlled.
      t
          .widget<GestureDetector>(find
              .descendant(
                  of: find.byWidgetPredicate((w) =>
                      w is AdaptiveContextMenu &&
                      w.itemsBuilder?.call()?.any((i) => i.text == 'Retry 1') ==
                          true),
                  matching: find.byWidgetPredicate(
                      (w) => w is GestureDetector && w.onSecondaryTap != null))
              .first)
          .onSecondaryTap!();
      await t.pumpAndSettle();
      expect(find.text('Save 1 message'), findsOneWidget);
      expect(find.text('Retry 1'), findsOneWidget);
      await t.tap(find.text('Cancel sending 1'));
      await t.pumpAndSettle();
      expect(find.textContaining('may still be delivered'), findsOneWidget);
      await t.tap(find.text('Keep messages'));
      await t.pumpAndSettle();
      expect(selection.isTicked(['local']), isTrue);
      expect(items.singleWhere((i) => i.text == 'Save 1 message').onPressed,
          isNotNull);
      // The synced event must never become a retry/cancel target in a mixed selection.
      t
          .widget<GestureDetector>(find
              .descendant(
                  of: find.byWidgetPredicate((w) =>
                      w is AdaptiveContextMenu &&
                      w.itemsBuilder?.call()?.any((i) => i.text == 'Retry 1') ==
                          true),
                  matching: find.byWidgetPredicate(
                      (w) => w is GestureDetector && w.onSecondaryTap != null))
              .first)
          .onSecondaryTap!();
      await t.pumpAndSettle();
      await t.tap(find.text('Retry 1'));
      await t.pumpAndSettle();
      expect(transport.submitted, ['local']);
      expect(selection.isTicked([original.eventId]), isTrue);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox());
      selection.dispose();
      // The real sender-marker dependency owns a 10-second lookup deadline.
      await t.pump(const Duration(seconds: 11));
    }
    expect(t.takeException(), isNull);
  });
}
