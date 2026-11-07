import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sent = 1800000000000;
  const fourHours = 14400000;

  Map<String, dynamic> content({int? created, int expires = fourHours}) => {
        "application": "m.call",
        "call_id": "",
        "scope": "m.room",
        "device_id": "DEV",
        "expires": expires,
        if (created != null) "created_ts": created,
        "focus_active": {
          "type": "livekit",
          "focus_selection": "oldest_membership"
        },
        "foci_preferred": [
          {
            "type": "livekit",
            "livekit_alias": "!room:a.example",
            "livekit_service_url": "https://sfu.a.example",
          }
        ],
      };

  group("createdTs", () {
    test("falls back to the event timestamp", () {
      expect(MatrixRtcMembership.createdTs(content(), sent), sent);
    });

    test("prefers created_ts", () {
      expect(MatrixRtcMembership.createdTs(content(created: 5), sent), 5);
    });
  });

  group("isLive", () {
    test("expiry counts from created_ts, not the latest post", () {
      // Re-posted an hour after joining, with created_ts kept and expires
      // grown: still valid at join + 7 h, gone at join + 8 h.
      final c = content(created: sent, expires: 2 * fourHours);
      const reposted = sent + 3600000;
      expect(MatrixRtcMembership.isLive(c, reposted, sent + 7 * 3600000), true);
      expect(
          MatrixRtcMembership.isLive(c, reposted, sent + 8 * 3600000), false);
    });

    test("a single post expires after one lifetime", () {
      expect(MatrixRtcMembership.isLive(content(), sent, sent + fourHours - 1),
          true);
      expect(
          MatrixRtcMembership.isLive(content(), sent, sent + fourHours), false);
    });

    test("left, foreign and non-room memberships are not live", () {
      expect(MatrixRtcMembership.isLive({}, sent, sent), false);
      expect(
          MatrixRtcMembership.isLive(
              {...content(), "application": "m.other"}, sent, sent),
          false);
      expect(
          MatrixRtcMembership.isLive(
              {...content(), "scope": "m.user"}, sent, sent),
          false);
    });

    test("no expires means never expires", () {
      final c = content()..remove("expires");
      expect(MatrixRtcMembership.isLive(c, sent, sent + 100 * fourHours), true);
    });
  });

  group("refreshed", () {
    test("first refresh pins created_ts to the first post and doubles expires",
        () {
      final r = MatrixRtcMembership.refreshed(content(), sent, 2);
      expect(r["created_ts"], sent);
      expect(r["expires"], 2 * fourHours);
      expect(r["foci_preferred"], content()["foci_preferred"]);
      expect(r["focus_active"], content()["focus_active"]);
    });

    test("later refreshes keep the original created_ts", () {
      final first = MatrixRtcMembership.refreshed(content(), sent, 2);
      final second = MatrixRtcMembership.refreshed(first, sent + 3600000, 3);
      expect(second["created_ts"], sent);
      expect(second["expires"], 3 * fourHours);
    });

    test("does not change the input", () {
      final c = content();
      MatrixRtcMembership.refreshed(c, sent, 2);
      expect(c.containsKey("created_ts"), false);
      expect(c["expires"], fourHours);
    });
  });

  test("refreshDueAt is hourly from the first post, with headroom", () {
    expect(MatrixRtcMembership.refreshDueAt(sent, 2), sent + 3600000 - 5000);
    expect(
        MatrixRtcMembership.refreshDueAt(sent, 3), sent + 2 * 3600000 - 5000);
  });
}
