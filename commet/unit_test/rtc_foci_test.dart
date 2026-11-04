import 'package:commet/client/matrix/components/voip_room/matrix_rtc_foci.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const now = 1800000000000;
  const room = "!room:a.example";

  Map<String, dynamic> content(String selection, String url,
          {int? created, int expires = 14400000}) =>
      {
        "application": "m.call",
        "call_id": "",
        "scope": "m.room",
        "device_id": "DEV",
        "expires": expires,
        if (created != null) "created_ts": created,
        "focus_active": {"type": "livekit", "focus_selection": selection},
        "foci_preferred": [
          {
            "type": "livekit",
            "livekit_alias": room,
            "livekit_service_url": url,
          }
        ],
      };

  RtcMember member(String key, int ts, String selection, String url,
          {int? created}) =>
      RtcMember.parse(
        stateKey: key,
        sender: key.split("_")[1],
        content: content(selection, url, created: created),
        originServerTs: ts,
        nowMs: now,
      )!;

  final a = Uri.parse("https://rtc.a.example");
  final b = Uri.parse("https://rtc.b.example");
  final c = Uri.parse("https://rtc.c.example");

  test('multi_sfu members publish on their own SFU', () {
    final members = [
      member("_@x:a.example_X_m.call", now - 3000, "multi_sfu", "$a"),
      member("_@y:b.example_Y_m.call", now - 2000, "multi_sfu", "$b"),
    ];
    expect(RtcFoci.transportOf(members[1], members), b);
    expect(RtcFoci.elected(members), a);
  });

  test('legacy members follow the oldest membership, even a multi_sfu one', () {
    final members = [
      member("_@x:b.example_X_m.call", now - 3000, "multi_sfu", "$b"),
      member("_@y:a.example_Y_m.call", now - 2000, "oldest_membership", "$a"),
    ];
    // Commet would skip the multi_sfu member and use its own SFU (a).
    expect(RtcFoci.transportOf(members[1], members), b);
    expect(RtcFoci.elected(members), b);
  });

  test('created_ts decides oldest, not origin_server_ts', () {
    final members = [
      // Re-posted recently, but created first.
      member("_@x:a.example_X_m.call", now - 100, "multi_sfu", "$a",
          created: now - 9000),
      member("_@y:b.example_Y_m.call", now - 5000, "multi_sfu", "$b"),
    ];
    expect(RtcFoci.elected(members), a);
  });

  test('remote transports: resolved ones plus everyone\'s own SFU', () {
    final members = [
      member("_@x:a.example_X_m.call", now - 3000, "oldest_membership", "$a"),
      member("_@y:b.example_Y_m.call", now - 2000, "multi_sfu", "$b"),
      // A Commet user who fell back to its own SFU.
      member("_@z:c.example_Z_m.call", now - 1000, "oldest_membership", "$c"),
      member("_@me:a.example_ME_m.call", now - 500, "oldest_membership", "$a"),
    ];
    final remote = RtcFoci.remoteTransports(
        members, (m) => m.stateKey == "_@me:a.example_ME_m.call");
    expect(remote, {a, b, c});
  });

  test('left, expired and other memberships are not members', () {
    expect(
        RtcMember.parse(
            stateKey: "k",
            sender: "@x:a",
            content: {},
            originServerTs: now,
            nowMs: now),
        isNull);
    expect(
        RtcMember.parse(
            stateKey: "k",
            sender: "@x:a",
            content: content("multi_sfu", "$a", expires: 1000),
            originServerTs: now - 5000,
            nowMs: now),
        isNull);
    expect(
        RtcMember.parse(
            stateKey: "k",
            sender: "@x:a",
            content: {...content("multi_sfu", "$a"), "application": "m.game"},
            originServerTs: now,
            nowMs: now),
        isNull);
  });

  test('unknown selection elects nothing; URLs are normalized', () {
    final odd = member("_@x:a.example_X_m.call", now - 3000, "whatever", "$a");
    expect(RtcFoci.elected([odd]), isNull);
    expect(RtcFoci.transportOf(odd, [odd]), isNull);
    expect(RtcMember.normalize(Uri.parse("HTTPS://RTC.A.example/")), a);
  });

  test('ties on created_ts break on state key', () {
    final members = [
      member("_@y:b.example_Y_m.call", now - 1000, "multi_sfu", "$b"),
      member("_@x:a.example_X_m.call", now - 1000, "multi_sfu", "$a"),
    ];
    expect(RtcFoci.elected(members), a);
  });
}
