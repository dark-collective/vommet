import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';
import 'package:commet/utils/call_duration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallDuration.format', () {
    test('minutes and seconds under an hour', () {
      expect(CallDuration.format(Duration.zero), "0:00");
      expect(CallDuration.format(const Duration(seconds: 5)), "0:05");
      expect(CallDuration.format(const Duration(minutes: 41, seconds: 5)),
          "41:05");
    });

    test('hours once past an hour', () {
      expect(
          CallDuration.format(const Duration(hours: 1, minutes: 2, seconds: 9)),
          "1:02:09");
      expect(CallDuration.format(const Duration(hours: 12)), "12:00:00");
    });

    test('a clock ahead of the call start shows zero', () {
      expect(CallDuration.format(const Duration(seconds: -30)), "0:00");
    });
  });

  group('MatrixRtcMembership.callStartedMs', () {
    const now = 1793000000000;
    Map<String, dynamic> membership({int? created}) => {
          "application": "m.call",
          "scope": "m.room",
          "expires": MatrixRtcMembership.expiresMs,
          if (created != null) "created_ts": created,
        };

    test('nobody in the call', () {
      expect(MatrixRtcMembership.callStartedMs([], now), isNull);
      expect(
          MatrixRtcMembership.callStartedMs([(<String, dynamic>{}, now)], now),
          isNull);
    });

    test('the oldest live membership counts', () {
      expect(
          MatrixRtcMembership.callStartedMs([
            (membership(created: now - 60000), now - 1000),
            (membership(created: now - 600000), now - 2000),
            (membership(), now - 30000),
          ], now),
          now - 600000);
    });

    test('expired and left memberships are ignored', () {
      expect(
          MatrixRtcMembership.callStartedMs([
            (membership(created: now - MatrixRtcMembership.expiresMs - 1), now),
            (<String, dynamic>{}, now - 900000),
            (membership(), now - 5000),
          ], now),
          now - 5000);
    });
  });
}
