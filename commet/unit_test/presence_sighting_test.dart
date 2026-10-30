import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

// Vommet issue 907: someone on a server that doesn't share presence stayed
// "Offline" right after sending a message, because the SDK keeps the first
// "offline, last active N ago" answer forever.

CachedPresence _offline({DateTime? lastActive, String? status}) =>
    CachedPresence.fromJson({
      'user_id': '@someone:example.org',
      'presence': 'offline',
      if (lastActive != null)
        'last_active_timestamp': lastActive.millisecondsSinceEpoch,
      if (status != null) 'status_msg': status,
    });

UserPresenceStatus? _status(
        CachedPresence? presence, DateTime? seen, DateTime now,
        {required bool liveServer}) =>
    MatrixUserPresenceComponent.recentlyActive(presence, seen, now,
            liveServer: liveServer)
        ?.status;

void main() {
  final lastActive = DateTime(2026, 10, 1, 12);
  final seen = DateTime(2026, 10, 29, 20);

  group('server without live presence', () {
    test('stale offline + last active, then a message: online for 2 minutes',
        () {
      final presence = _offline(lastActive: lastActive);
      expect(
          _status(presence, seen, seen.add(const Duration(seconds: 5)),
              liveServer: false),
          UserPresenceStatus.online);
      expect(
          _status(
              presence, seen, seen.add(const Duration(minutes: 1, seconds: 59)),
              liveServer: false),
          UserPresenceStatus.online);
      expect(
          _status(presence, seen, seen.add(const Duration(minutes: 2)),
              liveServer: false),
          isNull);
    });

    test('a sighting older than the last-active time does not count', () {
      final presence = _offline(lastActive: seen.add(const Duration(hours: 1)));
      expect(
          MatrixUserPresenceComponent.sightingCounts(presence, seen,
              liveServer: false),
          isFalse);
    });

    test('no sighting: no override', () {
      expect(
          _status(_offline(lastActive: lastActive), null, seen,
              liveServer: false),
          isNull);
    });
  });

  group('server with live presence', () {
    test('offline + last active stays offline (Invisible mode)', () {
      expect(
          _status(_offline(lastActive: lastActive), seen,
              seen.add(const Duration(seconds: 5)),
              liveServer: true),
          isNull);
    });

    test('offline with a status stays offline', () {
      expect(
          MatrixUserPresenceComponent.sightingCounts(
              _offline(status: 'away'), seen,
              liveServer: false),
          isFalse);
    });
  });

  test('bare offline or no presence: a sighting counts as before', () {
    for (final liveServer in [false, true]) {
      expect(
          _status(_offline(), seen, seen.add(const Duration(seconds: 5)),
              liveServer: liveServer),
          UserPresenceStatus.online);
      expect(
          _status(null, seen, seen.add(const Duration(seconds: 5)),
              liveServer: liveServer),
          UserPresenceStatus.online);
    }
  });
}
