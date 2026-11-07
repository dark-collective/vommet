import 'dart:async';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_leave.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership_writer.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_screen_share.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_screen_share_publisher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as mx;

class _Database extends Fake implements mx.DatabaseApi {}

Map<String, dynamic> content({String device = 'DEVICE'}) => {
      'application': 'm.call',
      'scope': 'm.room',
      'call_id': '',
      'device_id': device,
      'expires': 4000,
      'foci_preferred': [
        {'type': 'livekit', 'unknown': 'kept'}
      ],
      'custom': {'nested': true},
    };
void main() {
  group('passive reports', () {
    const sender = '@alex:example.org';
    int? expiry(Map<String, dynamic> c,
            {String key = '_${sender}_DEVICE_m.call', int now = 2000}) =>
        MatrixRtcScreenShare.expiry(
            content: c,
            sender: sender,
            stateKey: key,
            originServerTs: 1000,
            nowMs: now);
    Map<String, dynamic> share() => content()
      ..[MatrixRtcScreenShare.field] = {'active': true, 'since': 1500};
    test("the sharer's or viewer's clock skew doesn't hide a report", () {
      expect(
          expiry(content()
            ..[MatrixRtcScreenShare.field] = {'active': true, 'since': 9999999}
            ..['created_ts'] = 999999),
          isNotNull);
    });
    test('requires a live own-device room-call report', () {
      expect(expiry(share()), 5000);
      expect(expiry(share(), now: 5000), isNull);
      expect(expiry(share(), key: '_@other:example.org_DEVICE_m.call'), isNull);
      for (final (key, value) in [
        ('application', 'm.game'),
        ('scope', 'm.user'),
        ('call_id', 'other'),
        ('expires', null),
        ('expires', -1),
        ('device_id', null),
        ('created_ts', 'not-a-timestamp')
      ]) {
        expect(expiry(share()..[key] = value), isNull, reason: key);
      }
      for (final value in [
        null,
        true,
        {'active': false, 'since': 1500},
        {'active': 'true', 'since': 1500},
        {'active': true},
        {'active': true, 'since': '1500'}
      ]) {
        expect(expiry(content()..[MatrixRtcScreenShare.field] = value), isNull);
      }
    });
    test('long-call membership expiry cannot keep a report fresh forever', () {
      final c = share()..['expires'] = 365 * 86400000;
      expect(expiry(c), 1000 + 4 * 3600000);
      expect(expiry(c, now: 1000 + 4 * 3600000), isNull);
      // Consumers remove it at that timestamp, even while membership is live.
    });
    test('known room departures suppress still-live call reports', () {
      final client = mx.Client('fixture', database: _Database());
      final room = mx.Room(
          id: '!r:example.org', client: client, membership: mx.Membership.join);
      final now = DateTime.now();
      room.setState(mx.Event(
          type: 'org.matrix.msc3401.call.member',
          content: content()
            ..[MatrixRtcScreenShare.field] = {
              'active': true,
              'since': now.millisecondsSinceEpoch
            },
          senderId: sender,
          stateKey: '_${sender}_DEVICE_m.call',
          eventId: 'call-fixture',
          room: room,
          originServerTs: now));
      expect(MatrixRtcScreenShare.reports(room).keys, contains(sender));
      room.setState(mx.Event(
          type: mx.EventTypes.RoomMember,
          content: {'membership': 'leave'},
          senderId: sender,
          stateKey: sender,
          eventId: 'leave-fixture',
          room: room,
          originServerTs: now));
      expect(MatrixRtcScreenShare.reports(room), isEmpty);
    });
    test('preserved created_ts controls expiry and devices count by sender',
        () {
      final room = mx.Room(
          id: '!r:example.org',
          client: mx.Client('fixture', database: _Database()));
      mx.Event event(String device, int created) => mx.Event(
          type: 'org.matrix.msc3401.call.member',
          content: (share()..['device_id'] = device)..['created_ts'] = created,
          senderId: sender,
          eventId: '\$$device',
          stateKey: '_${sender}_${device}_m.call',
          room: room,
          originServerTs: DateTime.fromMillisecondsSinceEpoch(3000));
      expect(
          MatrixRtcScreenShare.collect([event('A', 1000), event('B', 1500)],
              nowMs: 2000),
          {sender: 5500});
      expect(MatrixRtcScreenShare.collect([event('A', 1000)], nowMs: 5000),
          isEmpty);
    });
  });
  group('ordered own membership', () {
    late List<Map<String, dynamic>> sent;
    late MatrixRtcMembershipWriter writer;
    setUp(() {
      sent = [];
      writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          send: (c) async {
            sent.add(c);
          });
    });
    test(
        'share, refresh and focus updates preserve original and unknown fields',
        () async {
      await writer.update((c) =>
          c[MatrixRtcScreenShare.field] = {'active': true, 'since': 1500});
      await writer.update((c) => c['expires'] = 8000);
      await writer.update((c) => c['focus_active'] = {'type': 'livekit'});
      expect(sent.last['created_ts'], 1000);
      expect(sent.last['custom'], {'nested': true});
      expect(sent.last['foci_preferred'], content()['foci_preferred']);
      expect(sent.last['expires'], 8000);
      expect(sent.last[MatrixRtcScreenShare.field],
          {'active': true, 'since': 1500});
      await writer.update((c) => c.remove(MatrixRtcScreenShare.field));
      expect(sent.last.containsKey(MatrixRtcScreenShare.field), isFalse);
      expect(sent.last['focus_active'], {'type': 'livekit'});
    });
    test('explicit created_ts is never moved to the new event time', () async {
      writer = MatrixRtcMembershipWriter(
          readInitial: () async =>
              (content: content()..['created_ts'] = 42, originServerTs: 1000),
          send: (c) async {
            sent.add(c);
          });
      await writer.update((c) => c['expires'] = 8000);
      expect(sent.single['created_ts'], 42);
    });
    test('leave waits for an in-flight start and prevents queued/later updates',
        () async {
      final blocked = Completer<void>();
      final started = Completer<void>();
      writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          send: (c) async {
            if (c.isNotEmpty) {
              started.complete();
              await blocked.future;
            }
            sent.add(c);
          });
      final start = writer
          .update((c) => c[MatrixRtcScreenShare.field] = {'active': true});
      await started.future;
      final refresh = writer.update((c) => c['expires'] = 8000);
      final leave = writer.clear();
      blocked.complete();
      await Future.wait([start, refresh, leave]);
      await writer.update((c) => c['resurrect'] = true);
      expect(sent.length, 2);
      expect(sent.last, isEmpty);
    });
    test('recovery acknowledges a stale empty sync without moving created_ts',
        () async {
      var syncedTs = 2000;
      var lost = 0;
      writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          isCurrent: (watermark) => syncedTs <= watermark,
          currentOriginServerTs: () => syncedTs,
          send: (c) async => sent.add(c));
      writer.onMembershipLost = () => lost++;
      expect(await writer.update((c) => c['expires'] = 8000), isFalse);
      expect(lost, 1);
      expect(await writer.update((_) {}, recover: true), isTrue);
      expect(sent.single['created_ts'], 1000);
      expect(sent.single['expires'], 8000);
      // Sync still shows the same empty state, even though recovery succeeded.
      expect(await writer.update((c) => c['expires'] = 12000), isTrue);
      expect(sent.last['created_ts'], 1000);
      syncedTs = 3000;
      expect(await writer.update((_) {}), isFalse);
      expect(lost, 2);
      await writer.clear();
      expect(await writer.update((_) {}, recover: true), isFalse);
      expect(sent.last, isEmpty);
    });

    test('a newer synced leave closes membership instead of resurrecting it',
        () async {
      var present = true;
      writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          isCurrent: (created) {
            expect(created, 1000);
            return present;
          },
          send: (c) async {
            sent.add(c);
          });
      await writer.update((c) => c['expires'] = 8000);
      present = false;
      await writer.update((c) => c['expires'] = 12000);
      present = true;
      await writer.update((c) => c['expires'] = 16000);
      expect(sent.length, 1);
    });
    test('update reports a closed membership instead of writing', () async {
      writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          send: (c) async {
            sent.add(c);
          });
      expect(await writer.update((c) => c['expires'] = 8000), isTrue);
      await writer.clear();
      expect(await writer.update((c) => c['expires'] = 12000), isFalse);
      expect(sent.length, 2);
    });
    test('a leave settled by a rejoin is not sent after the queued write',
        () async {
      final blocked = Completer<void>();
      writer = MatrixRtcMembershipWriter(readInitial: () async {
        await blocked.future;
        return (content: content(), originServerTs: 1000);
      }, send: (c) async {
        sent.add(c);
      });
      final refresh = writer.update((c) => c['expires'] = 8000);
      final leave = MatrixRtcLeave.clear('!r', '_me_D_m.call',
          (cancelled) => writer.clear(cancelled: cancelled));
      final join = MatrixRtcLeave.settle('!r', '_me_D_m.call');
      blocked.complete();
      await Future.wait([refresh, leave, join]);
      expect(sent.where((c) => c.isEmpty), isEmpty);
    });
    test('a failed write does not poison later writes or lose prior fields',
        () async {
      var fail = true;
      writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          send: (c) async {
            if (fail) {
              fail = false;
              throw StateError('offline');
            }
            sent.add(c);
          });
      await expectLater(
          writer.update((c) => c['expires'] = 9999), throwsStateError);
      await writer.update((c) => c['focus_active'] = {'type': 'livekit'});
      expect(sent.single['expires'], 4000);
      expect(sent.single['custom'], {'nested': true});
    });
  });
  group('local publisher', () {
    test('start, quality refresh, stop/ended track and opt-out converge',
        () async {
      var sharing = false;
      var enabled = true;
      final changed = StreamController<bool>.broadcast();
      final sent = <Map<String, dynamic>>[];
      final writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          send: (c) async {
            sent.add(c);
          });
      final publisher = MatrixRtcScreenSharePublisher(
          writer: writer,
          isSharing: () => sharing,
          enabled: () => enabled,
          onEnabledChanged: changed.stream);
      await publisher.refresh();
      sharing = true;
      await publisher.refresh();
      final since = (sent.last[MatrixRtcScreenShare.field] as Map)['since'];
      await publisher.refresh(force: true);
      expect((sent.last[MatrixRtcScreenShare.field] as Map)['since'], since);
      sharing = false;
      await publisher.refresh();
      expect(sent.last.containsKey(MatrixRtcScreenShare.field), false);
      sharing = true;
      await publisher.refresh();
      enabled = false;
      changed.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(sent.last.containsKey(MatrixRtcScreenShare.field), false);
      enabled = true;
      changed.add(true);
      await Future<void>.delayed(Duration.zero);
      expect((sent.last[MatrixRtcScreenShare.field] as Map)['active'], true);
      publisher.close();
      await writer.clear();
      sharing = false;
      await publisher.refresh();
      expect(sent.last, isEmpty);
      await changed.close();
    });
    test('refresh cannot retain an advertisement after a failed stop write',
        () async {
      var sharing = true;
      var fail = false;
      final changed = StreamController<bool>.broadcast();
      final sent = <Map<String, dynamic>>[];
      final writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          send: (c) async {
            if (fail) {
              fail = false;
              throw StateError('offline');
            }
            sent.add(c);
          });
      final publisher = MatrixRtcScreenSharePublisher(
          writer: writer,
          isSharing: () => sharing,
          enabled: () => true,
          onEnabledChanged: changed.stream);
      await publisher.refresh();
      sharing = false;
      fail = true;
      await publisher.refresh();
      await writer.update((c) => c['expires'] = 8000);
      expect(sent.last.containsKey(MatrixRtcScreenShare.field), false);
      publisher.close();
      await changed.close();
    });
    test('queued start reads latest stop and never advertises a stopped track',
        () async {
      final block = Completer<void>();
      var sharing = true;
      final changed = StreamController<bool>.broadcast();
      final sent = <Map<String, dynamic>>[];
      final writer = MatrixRtcMembershipWriter(readInitial: () async {
        await block.future;
        return (content: content(), originServerTs: 1000);
      }, send: (c) async {
        sent.add(c);
      });
      final publisher = MatrixRtcScreenSharePublisher(
          writer: writer,
          isSharing: () => sharing,
          enabled: () => true,
          onEnabledChanged: changed.stream);
      final start = publisher.refresh();
      sharing = false;
      final stop = publisher.refresh();
      block.complete();
      await Future.wait([start, stop]);
      expect(
          sent.every((c) => !c.containsKey(MatrixRtcScreenShare.field)), true);
      publisher.close();
      await changed.close();
    });
    test('joining or toggling the experiment while not sharing writes nothing',
        () async {
      var enabled = true;
      final changed = StreamController<bool>.broadcast();
      final sent = <Map<String, dynamic>>[];
      final writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          send: (c) async {
            sent.add(c);
          });
      final publisher = MatrixRtcScreenSharePublisher(
          writer: writer,
          isSharing: () => false,
          enabled: () => enabled,
          onEnabledChanged: changed.stream);
      await publisher.refresh();
      enabled = false;
      changed.add(false);
      await Future<void>.delayed(Duration.zero);
      enabled = true;
      changed.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
      publisher.close();
      await changed.close();
    });
    testWidgets('failures retry at most three times and stop on close',
        (tester) async {
      final changed = StreamController<bool>.broadcast();
      var attempts = 0;
      final writer = MatrixRtcMembershipWriter(
          readInitial: () async => (content: content(), originServerTs: 1000),
          send: (c) async {
            attempts++;
            throw StateError('offline');
          });
      final publisher = MatrixRtcScreenSharePublisher(
          writer: writer,
          isSharing: () => true,
          enabled: () => true,
          onEnabledChanged: changed.stream);
      await publisher.refresh();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(attempts, 4);
      publisher.close();
      await changed.close();
    });
  });
}
