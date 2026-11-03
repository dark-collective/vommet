import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:commet/client/room.dart';
import 'package:commet/utils/unread_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/unread_fixtures.dart';

class FailingRoom extends UnreadRoom {
  FailingRoom(super.client, super.identifier, {super.notificationCount});
  bool fail = false;
  @override
  int get notificationCount =>
      fail ? throw StateError('broken room') : super.notificationCount;
}

void main() {
  RoomUnread value(
          {bool muted = false,
          bool notify = true,
          int n = 0,
          int h = 0,
          bool marked = false,
          bool event = false}) =>
      RoomUnread.compute(
          muted: muted,
          notify: notify,
          notifications: n,
          highlights: h,
          messagesAreNoisy: false,
          markedUnread: marked,
          unreadEvent: event);

  test('a person sums room badges, including an older encrypted mention', () {
    final person = PersonUnread.of([value(n: 2), value(h: 3)]);
    expect(person.badge, 5); // max(sum(notifications), sum(highlights)) was 3.
    expect(person.noisy, isTrue);
  });
  test('muted rooms contribute neither numbers nor activity', () {
    final muted = value(muted: true, n: 3, h: 2, marked: true, event: true);
    expect((muted.badge, muted.highlights, muted.activity, muted.noisy),
        (0, 0, false, false));
  });
  test('marked unread is an unnumbered activity mark', () {
    expect(value(marked: true).activity, isTrue);
    expect(value(n: 1, marked: true).activity, isFalse);
  });
  test('mentions-only suppresses plain messages but keeps manual marks', () {
    expect(value(notify: false, n: 4, event: true).unread, isFalse);
    expect(value(notify: false, event: true, marked: true).activity, isTrue);
    expect(value(notify: false, h: 1, event: true).badge, 1);
  });
  test('receipt order uses IDs, independent of clock skew', () {
    const order = ['later', 'newest-visible', 'older'];
    expect(receiptCovers('newest-visible', ['later'], order), isTrue);
    expect(receiptCovers('newest-visible', ['newest-visible'], []), isTrue);
    expect(receiptCovers('newest-visible', ['older'], order), isFalse);
    expect(receiptCovers('newest-visible', ['unknown'], order), isFalse);
  });
  test('receipt coverage distinguishes missing evidence from an older receipt',
      () {
    const order = ['new', 'old'];
    expect(receiptCoverage('new', ['old'], order), isFalse);
    expect(receiptCoverage('old', ['new'], order), isTrue);
    expect(receiptCoverage('outside', ['new'], order), isNull);
    expect(receiptCoverage('new', ['outside'], order), isNull);
    expect(receiptCoverage('new', ['old', 'outside'], order), isNull);
    expect(receiptCoverage('old', ['new', 'outside'], order), isTrue);
    expect(receiptCoverage('new', [], order), isNull);
    expect(receiptCoverage('outside', ['outside'], []), isTrue);
  });
  test('two spaces in a folder count a shared room once per account', () {
    final room = value(n: 2);
    expect(UnreadTotals.rooms([('a/r', room), ('a/r', room)]).badge, 2);
    expect(UnreadTotals.rooms([('a/r', room), ('b/r', room)]).badge, 4);
  });
  test('Home and People honor the account filter', () {
    final people = [
      ('a', PersonUnread.of([value(n: 2)])),
      ('b', PersonUnread.of([value(h: 3)]))
    ];
    expect(UnreadTotals.home(invites: 1, people: people, account: 'a'), 3);
    expect(UnreadTotals.home(invites: 1, people: people), 6);
    expect(UnreadTotals.home(invites: 1, people: people, countDms: false), 1);
  });
  test('a muted newest DM cannot hide an older unmuted room', () {
    final client = UnreadClient();
    addTearDown(client.close);
    final latest = UnreadRoom(client, 'latest', pushRule: PushRule.dontNotify);
    final older = UnreadRoom(client, 'older', notificationCount: 3);
    client.dms.groups['person'] = [latest, older];
    final person = UnreadIndex.rowOf(latest);
    expect(person.badge, 3);
    expect(person.muted, isFalse);
    expect(
        NotificationUtils.countNotifications([(latest, true), (older, true)]),
        (3, 1));
  });
  test('a pinned DM expands before folder deduplication across spaces', () {
    final client = UnreadClient();
    addTearDown(client.close);
    final latest = UnreadRoom(client, 'latest');
    final older = UnreadRoom(client, 'older', notificationCount: 3);
    final shared = UnreadRoom(client, 'shared', notificationCount: 4);
    client.dms.groups['person'] = [latest, older];
    final index = UnreadIndex.of(client);
    final rooms = [...index.roomsForRow(latest), shared, shared, older];
    expect(index.sum(rooms).badge, 7);
    expect(
        index.sum(index.roomsForRow(latest)).badge, index.person(latest).badge);
  });
  test('Recent activity keeps a DM whose older unmuted room is unread', () {
    final client = UnreadClient();
    addTearDown(client.close);
    final latest = UnreadRoom(client, 'latest', pushRule: PushRule.dontNotify);
    final older = UnreadRoom(client, 'older', notificationCount: 3);
    client.dms.groups['person'] = [latest, older];
    final index = UnreadIndex.of(client);
    final recent = recentActivity<UnreadRoom>([latest],
        const HomeCard(HomeLayout.recent, muted: false, unreadOnly: true),
        lastEvent: (_) => DateTime(2026),
        isDirectMessage: client.dms.isRoomDirectMessage,
        isMuted: (room) => index.person(room).muted,
        isUnread: (room) => index.person(room).unread);
    expect(recent, [latest]);
  });
  test('the index updates after local reads, push rules, and DM regrouping',
      () async {
    final client = UnreadClient();
    addTearDown(client.close);
    final latest = UnreadRoom(client, 'latest', isFavorite: true);
    final older = UnreadRoom(client, 'older', notificationCount: 2);
    client.dms.groups['person'] = [latest, older];
    final index = UnreadIndex.of(client);
    expect(index.person(latest).badge, 2);
    expect(UnreadIndex.rowOf(older).badge, UnreadIndex.rowOf(latest).badge);
    expect(
        NotificationUtils.countNotifications([(latest, true), (older, true)]),
        (2, 1));
    await Future<void>.delayed(Duration.zero);
    older.notificationCount = 0;
    final updated = index.onChanged.first;
    older.updates.add(null);
    await updated;
    expect(index.person(latest).badge, 0);
    older.notificationCount = 3;
    older.pushRule = PushRule.dontNotify;
    final muted = index.onChanged.first;
    client.sync.add(null);
    await muted;
    expect(index.person(latest).badge, 0);
    older.pushRule = PushRule.notify;
    client.dms.groups.clear();
    final regrouped = index.onChanged.first;
    client.sync.add(null);
    await regrouped;
    expect(index.person(latest).badge, 0);
    expect(index.room(older).badge, 3);
  });

  test('an update that changes no unread value publishes nothing', () async {
    final client = UnreadClient();
    addTearDown(client.close);
    final room = UnreadRoom(client, 'room', notificationCount: 1);
    final index = UnreadIndex.of(client);
    await Future<void>.delayed(Duration.zero);
    var changes = 0;
    final sub = index.onChanged.listen((_) => changes++);
    addTearDown(sub.cancel);
    client.sync.add(null);
    room.updates.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(changes, 0);
    room.notificationCount = 2;
    client.sync.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    expect(index.room(room).badge, 2);
  });

  test('a room outside the account list is never served a stale value', () {
    final client = UnreadClient();
    addTearDown(client.close);
    final room = UnreadRoom(client, 'left', notificationCount: 1);
    client.rooms.remove(room);
    final index = UnreadIndex.of(client);
    expect(index.room(room).badge, 1);
    room.notificationCount = 4;
    expect(index.room(room).badge, 4);
  });

  test('an older DM room listed on its own shows only its own count', () {
    final client = UnreadClient();
    addTearDown(client.close);
    final latest = UnreadRoom(client, 'latest', notificationCount: 2);
    final older = UnreadRoom(client, 'older');
    client.dms.groups['person'] = [latest, older];
    final index = UnreadIndex.of(client);
    expect(index.roomsForRow(older), [older]);
    expect(UnreadIndex.rowOf(older).badge, 0);
    expect(UnreadIndex.rowOf(latest).badge, 2);
  });

  test('a person counts all their DM rooms whichever is listed first', () {
    final client = UnreadClient();
    addTearDown(client.close);
    final older = UnreadRoom(client, 'older', notificationCount: 1);
    final latest = UnreadRoom(client, 'latest', notificationCount: 3);
    client.dms.groups['person'] = [latest, older];
    final people = UnreadIndex.of(client).people.toList();
    expect(people.map((p) => p.$1), ['person']);
    expect(people.single.$2.badge, 4);
  });

  test('a room that fails to compute keeps its value, others still update',
      () async {
    final client = UnreadClient();
    addTearDown(client.close);
    final broken = FailingRoom(client, 'broken', notificationCount: 1);
    final other = UnreadRoom(client, 'other', notificationCount: 1);
    final index = UnreadIndex.of(client);
    await Future<void>.delayed(Duration.zero);
    expect(index.room(broken).badge, 1);
    broken.fail = true;
    other.notificationCount = 5;
    final changed = index.onChanged.first;
    client.sync.add(null);
    await changed;
    expect(index.room(other).badge, 5);
    expect(index.room(broken).badge, 1);
  });
}
