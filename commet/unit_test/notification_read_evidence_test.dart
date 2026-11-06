import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/utils/notification_debug_collect.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'helpers/unread_fixtures.dart';

class _Sdk extends Fake implements matrix.Client {
  @override
  String get userID => '@me:example.org';
}

class _Event extends Fake implements MatrixTimelineEvent {
  _Event(this.event);
  @override
  final matrix.Event event;
  @override
  String get eventId => event.eventId;
}

class _Room extends Fake implements MatrixRoom {
  _Room(this.matrixRoom, this.lastEvent, this.lastMessage);
  @override
  final matrix.Room matrixRoom;
  @override
  final Client client = UnreadClient();
  @override
  TimelineEvent? lastEvent;
  @override
  TimelineEvent? lastMessage;
  @override
  Timeline? get timeline => null;
}

matrix.Event _event(matrix.Room room, String id,
        {String type = matrix.EventTypes.Message}) =>
    matrix.Event(
        type: type,
        eventId: id,
        senderId: '@them:example.org',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
        room: room,
        content: {'msgtype': 'm.text', 'body': 'fixture'});
matrix.Room _sdkRoom({String? receipt, String? fullyRead}) {
  final room = matrix.Room(id: '!evidence:example.org', client: _Sdk());
  room.receiptState = matrix.LatestReceiptState.fromJson({
    if (receipt != null)
      'global': {
        'public': {'e': receipt, 'ts': 999999}
      }
  });
  if (fullyRead != null)
    room.roomAccountData['m.fully_read'] = matrix.BasicEvent(
        type: 'm.fully_read', content: {'event_id': fullyRead});
  return room;
}

void main() {
  test('marker coverage is separate from a definitely older receipt', () {
    final sdk = _sdkRoom(receipt: r'$old', fullyRead: r'$new');
    final newest = _event(sdk, r'$new');
    sdk.lastEvent = newest;
    rememberUnreadOrder(sdk, [r'$new', r'$old']);
    final room = _Room(sdk, _Event(newest), _Event(newest));
    final evidence = notificationReadEvidence(room);
    expect(evidence.newestCoverage, isFalse);
    expect(evidence.visibleCoverage, isFalse);
    expect(evidence.fullyReadCoverage, isTrue);
    expect(evidence.visibleInOrder, isTrue);
    expect(roomHasUnreadActivity(room), isTrue);
  });
  test('absent receipts and absent positions remain unknown', () {
    for (final receipt in [null, r'$outside']) {
      final sdk = _sdkRoom(receipt: receipt, fullyRead: r'$new');
      final newest = _event(sdk, r'$new');
      sdk.lastEvent = newest;
      final evidence =
          notificationReadEvidence(_Room(sdk, _Event(newest), null));
      expect(evidence.visibleInOrder, isFalse);
      expect(evidence.newestCoverage, isNull);
      expect(evidence.visibleCoverage, isNull);
      expect(evidence.fullyReadCoverage, isTrue);
    }
  });
  test(
      'the debug candidate excludes a non-message newest event exactly like activity',
      () {
    final sdk = _sdkRoom(receipt: r'$message', fullyRead: r'$state');
    final state = _event(sdk, r'$state', type: matrix.EventTypes.RoomMember);
    final message = _event(sdk, r'$message');
    sdk.lastEvent = state;
    rememberUnreadOrder(sdk, [r'$state', r'$message']);
    final room = _Room(sdk, _Event(state), _Event(message));
    final evidence = notificationReadEvidence(room);
    expect(evidence.visibleDiffersFromNewest, isTrue);
    expect(evidence.newestCoverage, isFalse);
    expect(evidence.visibleCoverage, isTrue);
    expect(evidence.fullyReadCoverage, isTrue);
    expect(roomHasUnreadActivity(room), isFalse);
  });
  test('local receipt evidence is visible before its server echo', () {
    final sdk = _sdkRoom();
    final newest = _event(sdk, r'$new');
    sdk.lastEvent = newest;
    recordOwnReceipt(sdk, r'$new');
    final evidence = notificationReadEvidence(_Room(sdk, _Event(newest), null));
    expect(evidence.visibleInOrder, isFalse);
    expect(evidence.visibleCoverage, isTrue);
    expect(evidence.localReceipt, isTrue);
  });
}
