// MatrixRtcMultiSfu (MSC4195 multi-SFU): which SFUs we listen on, where we
// publish, and the membership we re-post after following the election.
//
// The memberships are `org.matrix.msc3401.call.member` state events in an SDK
// room, shaped as the senders post them (fields parsed by RtcMember.parse,
// matrix_rtc_foci.dart):
// * Element Call >= 0.21: `focus_active: {type: livekit, focus_selection:
//   multi_sfu}`, `foci_preferred[0]` its own homeserver's lk-jwt service;
// * Commet and legacy clients: `focus_selection: oldest_membership`.
// Both carry `application: m.call`, `scope: m.room`, `device_id`, `expires`
// and, after their first refresh, `created_ts` (matrix_rtc_membership.dart).
// The SDK client is a Fake: membersOf reads only room.states.
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_foci.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership_writer.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_multi_sfu.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as mx;

class _FakeSdkClient extends Fake implements mx.Client {}

const _now = 1800000000000;
const _roomId = "!call:a.example";
final _sfuA = Uri.parse("https://rtc.a.example");
final _sfuB = Uri.parse("https://rtc.b.example");
final _sfuC = Uri.parse("https://rtc.c.example");

const _selfKey = "_@me:a.example_MYDEV_m.call";

Map<String, dynamic> _content(String selection, Uri sfu,
        {String device = "DEV",
        int? created,
        int expires = 14400000,
        Map<String, dynamic>? focusActive}) =>
    {
      "application": "m.call",
      "call_id": "",
      "scope": "m.room",
      "device_id": device,
      "expires": expires,
      // [created] orders members: milliseconds after a post an hour ago.
      if (created != null) "created_ts": _now - 3600000 + created,
      "focus_active":
          focusActive ?? {"type": "livekit", "focus_selection": selection},
      "foci_preferred": [
        {
          "type": "livekit",
          "livekit_alias": _roomId,
          "livekit_service_url": sfu.toString(),
        }
      ],
    };

class _M {
  _M(this.key, this.content);
  final String key;
  final Map<String, dynamic> content;
  // Posted a minute ago.
  final int ts = _now - 60000;
}

mx.Room _room(List<_M> members) {
  final room = mx.Room(id: _roomId, client: _FakeSdkClient());
  room.states[MatrixVoipRoomComponent.callMemberStateEvent] = {
    for (final m in members)
      m.key: mx.Event(
        type: MatrixVoipRoomComponent.callMemberStateEvent,
        content: m.content,
        senderId: m.key.split("_")[1],
        stateKey: m.key,
        eventId: "\$${m.key}",
        originServerTs: DateTime.fromMillisecondsSinceEpoch(m.ts),
        room: room,
      ),
  };
  return room;
}

({Uri? migrateTo, Set<Uri> listen}) _plan(List<_M> members,
        {Uri? primary, bool pinned = false, Set<Uri> listenOnly = const {}}) =>
    MatrixRtcMultiSfu.plan(
        MatrixRtcMultiSfu.membersOf(_room(members), nowMs: _now),
        selfKey: _selfKey,
        primary: primary ?? _sfuA,
        pinned: pinned,
        listenOnly: listenOnly);

void main() {
  final me = _M(_selfKey,
      _content(RtcFocusSelection.multiSfu, _sfuA, device: "MYDEV", created: 1));

  group('listening', () {
    test('everyone on our homeserver: only our SFU, nothing extra', () {
      final p = _plan([
        me,
        _M("_@ann:a.example_X_m.call",
            _content(RtcFocusSelection.multiSfu, _sfuA, created: 2)),
        _M("_@bo:a.example_Y_m.call",
            _content(RtcFocusSelection.oldestMembership, _sfuA, created: 3)),
      ]);
      expect(p.listen, isEmpty);
      expect(p.migrateTo, isNull);
    });

    test(
        'a multi_sfu member on another homeserver adds their SFU, '
        'and it is dropped when they leave', () {
      final remote = _M("_@cy:b.example_Z_m.call",
          _content(RtcFocusSelection.multiSfu, _sfuB, created: 5));
      expect(_plan([me, remote]).listen, {_sfuB});
      // Leaving posts empty content (MatrixRtcMembershipWriter.clear).
      expect(_plan([me, _M(remote.key, {})]).listen, isEmpty);
    });

    test('our own membership never adds an SFU to listen on', () {
      // Our own membership names C; nobody else is in the call.
      final self =
          _M(_selfKey, _content(RtcFocusSelection.multiSfu, _sfuC, created: 1));
      expect(_plan([self]).listen, isEmpty);
    });

    test('a member with an unknown focus type is ignored, not crashed on', () {
      final odd = _M(
          "_@dee:c.example_W_m.call",
          _content("x", _sfuC,
              created: 0, focusActive: {"type": "full_mesh", "x": 1}))
        ..content["foci_preferred"] = [
          {"type": "mesh", "url": "nope"}
        ];
      final p = _plan([me, odd]);
      expect(p.listen, isEmpty);
      expect(p.migrateTo, isNull);
    });
  });

  group('election', () {
    test('a legacy oldest member elects their SFU: we migrate there', () {
      final p = _plan([
        me,
        _M("_@old:b.example_O_m.call",
            _content(RtcFocusSelection.oldestMembership, _sfuB, created: 0)),
      ]);
      expect(p.migrateTo, _sfuB);
    });

    test('pinned or listen-only: we never migrate', () {
      final members = [
        me,
        _M("_@old:b.example_O_m.call",
            _content(RtcFocusSelection.oldestMembership, _sfuB, created: 0)),
      ];
      expect(_plan(members, pinned: true).migrateTo, isNull);
      expect(_plan(members, listenOnly: {_sfuB}).migrateTo, isNull);
      // Still heard there.
      expect(_plan(members, pinned: true).listen, contains(_sfuB));
    });

    test('expired memberships never elect', () {
      final p = _plan([
        me,
        _M(
            "_@ghost:b.example_G_m.call",
            _content(RtcFocusSelection.oldestMembership, _sfuB,
                created: 0, expires: 1000)),
      ]);
      expect(p.migrateTo, isNull);
      expect(p.listen, isEmpty);
    });

    test('ties on created_ts break on the state key, in any order', () {
      final x = _M("_@a:c.example_A_m.call",
          _content(RtcFocusSelection.oldestMembership, _sfuC, created: 0));
      final y = _M("_@b:b.example_B_m.call",
          _content(RtcFocusSelection.oldestMembership, _sfuB, created: 0));
      expect(_plan([me, x, y]).migrateTo, _sfuC);
      expect(_plan([y, me, x]).migrateTo, _sfuC);
    });

    test('excluding our own stale membership changes who is oldest', () {
      final room = _room([
        me,
        _M("_@old:b.example_O_m.call",
            _content(RtcFocusSelection.oldestMembership, _sfuB, created: 2)),
      ]);
      expect(RtcFoci.elected(MatrixRtcMultiSfu.membersOf(room, nowMs: _now)),
          _sfuA);
      expect(
          RtcFoci.elected(MatrixRtcMultiSfu.membersOf(room,
              excludeKey: _selfKey, nowMs: _now)),
          _sfuB);
    });
  });

  group('re-posted membership after migrating', () {
    test('names the new SFU first and keeps created_ts', () async {
      // Our first post carried no created_ts; the server stamped it.
      const firstPostTs = _now - 3600000;
      final first =
          _content(RtcFocusSelection.oldestMembership, _sfuA, device: "MYDEV");
      final sent = <Map<String, dynamic>>[];
      final writer = MatrixRtcMembershipWriter(
          readInitial: () async =>
              (content: first, originServerTs: firstPostTs),
          send: (c) async => sent.add(c));
      await writer
          .update((c) => MatrixRtcMultiSfu.preferFocus(c, _sfuB, _roomId));

      final posted = sent.single;
      expect(posted["created_ts"], firstPostTs);
      final foci = posted["foci_preferred"] as List;
      expect(foci.first["livekit_service_url"], _sfuB.toString());
      expect(foci.where((f) => f["livekit_service_url"] == _sfuB.toString()),
          hasLength(1));
      // Everyone else now elects B from it.
      final m = RtcMember.parse(
          stateKey: _selfKey,
          sender: "@me:a.example",
          content: posted,
          originServerTs: _now,
          nowMs: _now)!;
      expect(m.preferred, _sfuB);
      expect(m.createdTs, firstPostTs);
    });
  });
}
