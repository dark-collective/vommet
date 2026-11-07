// Vommet: window-local navigation prerequisite (Vommet issue 1068).
import 'package:commet/utils/chat_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending jumps address account, room, thread and workspace', () {
    final first = ChatNavigation();
    final second = ChatNavigation();
    first.setPendingThread('room', 'root',
        clientId: 'account', eventId: 'reply');
    expect(second.takePendingThread('room', clientId: 'account'), isNull);
    expect(first.takePendingThread('room', clientId: 'other'), isNull);
    expect(first.takePendingThread('other', clientId: 'account'), isNull);
    expect(first.takePendingThread('room', clientId: 'account'), 'root');
    expect(first.takePendingThread('room', clientId: 'account'), isNull);
    expect(
        first.takePendingThreadJump('room',
            clientId: 'account', threadId: 'other'),
        isNull);
    expect(
        first.takePendingThreadJump('room',
            clientId: 'account', threadId: 'root'),
        'reply');
    first.setPendingJump('room', 'event', clientId: 'account');
    expect(first.takePendingJump('room', clientId: 'other'), isNull);
    expect(first.takePendingJump('room', clientId: 'account'), 'event');
    first.dispose();
    second.dispose();
  });

  test('pending replacement and expiry stay in their workspace', () {
    var now = DateTime.utc(2026);
    final navigation = ChatNavigation(now: () => now);
    final other = ChatNavigation(now: () => now);
    navigation.setPendingThread('room', 'old', eventId: 'old reply');
    other.setPendingThread('room', 'other', eventId: 'other reply');
    navigation.setPendingThread('room', 'new');
    expect(other.takePendingThreadJump('room'), 'other reply');
    other.dispose();
    expect(navigation.takePendingThreadJump('room'), isNull);
    expect(navigation.takePendingThread('room'), 'new');
    navigation.setPendingThread('room', 'root', eventId: 'reply');
    navigation.setPendingJump('room', 'event');
    now = now.add(const Duration(minutes: 1, seconds: 1));
    expect(navigation.takePendingThread('room'), isNull);
    expect(navigation.takePendingThreadJump('room'), isNull);
    expect(navigation.takePendingJump('room'), isNull);
    navigation.dispose();
  });

  test('queued room entry is delivered once, only to its live workspace',
      () async {
    final navigation = ChatNavigation();
    final entries = <RoomOpenArgs>[];
    navigation.doOpenRoom('old', clientId: 'account');
    navigation.doOpenRoom('latest', clientId: 'account', threadId: 'root');
    final subscription = navigation.openRoom.stream.listen(entries.add);
    await Future<void>.delayed(Duration.zero);
    expect(entries.single.roomId, 'latest');
    expect(entries.single.threadId, 'root');
    await subscription.cancel();
    final again = navigation.openRoom.stream.listen(entries.add);
    await Future<void>.delayed(Duration.zero);
    expect(entries, hasLength(1));
    await again.cancel();
    navigation.doOpenRoom('discarded');
    final cancelled = navigation.openRoom.stream.listen(entries.add);
    navigation.dispose();
    navigation.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(entries, hasLength(1));
    await cancelled.cancel();
    navigation.doOpenRoom('after disposal');
    navigation.openThreadFor(('account', 'room', 'root'));
  });
}
