import 'dart:async';

import 'package:commet/client/matrix/components/voip_room/call_presence_sounds.dart';
import 'package:commet/client/matrix/components/voip_room/livekit_identity.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    callback();
  }

  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled && !fired;
  @override
  int get tick => fired ? 1 : 0;
}

CallConnection member(String user, String device) =>
    (userId: user, deviceId: device, isMember: true);

void main() {
  late List<String> played;
  late List<_FakeTimer> timers;
  late CallPresenceSounds sounds;

  setUp(() {
    played = [];
    timers = [];
    sounds = CallPresenceSounds(
        playJoin: () => played.add("join"),
        playLeave: () => played.add("leave"),
        timer: (d, f) {
          final t = _FakeTimer(d, f);
          timers.add(t);
          return t;
        });
  });

  void fireAll() {
    for (final t in [...timers]) {
      t.fire();
    }
  }

  test("a member's first connection plays the join sound", () {
    sounds.connected("a1", member("@a:x", "A1"));
    expect(played, ["join"]);
  });

  test("a second device of the same person stays quiet", () {
    sounds.connected("a1", member("@a:x", "A1"));
    sounds.connected("a2", member("@a:x", "A2"));
    expect(played, ["join"]);
  });

  test("our own second device stays quiet", () {
    sounds.seed("me", member("@me:x", "ME1"));
    sounds.connected("me2", member("@me:x", "ME2"));
    expect(played, isEmpty);
  });

  test("bridge stream entries never make a sound", () {
    sounds.connected("s", member("@a:x", "SCREEN1"));
    sounds.disconnected("s");
    fireAll();
    expect(played, isEmpty);
    sounds.connected("a1", member("@a:x", "A1"));
    sounds.connected("s", member("@a:x", "SCREEN1"));
    sounds.disconnected("s");
    fireAll();
    expect(played, ["join"]);
  });

  test("a LiveKit-only participant stays quiet both ways", () {
    sounds.connected("x", (userId: "x", deviceId: null, isMember: false));
    sounds.disconnected("x");
    fireAll();
    expect(played, isEmpty);
  });

  test("a membership that syncs late still plays the join sound", () {
    var isMember = false;
    sounds.connected("b1", (userId: "@b:x", deviceId: "B1", isMember: false),
        recheck: () => (userId: "@b:x", deviceId: "B1", isMember: isMember));
    expect(played, isEmpty);
    isMember = true;
    fireAll();
    expect(played, ["join"]);
  });

  test("the leave sound plays 3 s after the last connection goes", () {
    sounds.connected("a1", member("@a:x", "A1"));
    sounds.connected("a2", member("@a:x", "A2"));
    sounds.disconnected("a1");
    expect(timers, isEmpty);
    sounds.disconnected("a2");
    expect(timers.single.duration, const Duration(seconds: 3));
    expect(played, ["join"]);
    fireAll();
    expect(played, ["join", "leave"]);
  });

  test("a rejoin within 3 s cancels the leave and plays nothing", () {
    sounds.connected("a1", member("@a:x", "A1"));
    sounds.disconnected("a1");
    sounds.connected("a1b", member("@a:x", "A1"));
    fireAll();
    expect(played, ["join"]);
    sounds.disconnected("a1b");
    fireAll();
    expect(played, ["join", "leave"]);
  });

  test("someone already in the call gets a leave sound but no join", () {
    sounds.seed("c1", member("@c:x", "C1"));
    expect(played, isEmpty);
    sounds.disconnected("c1");
    fireAll();
    expect(played, ["leave"]);
  });

  test("dispose cancels pending sounds", () {
    sounds.connected("a1", member("@a:x", "A1"));
    sounds.disconnected("a1");
    sounds.dispose();
    fireAll();
    expect(played, ["join"]);
  });

  test("pure rules", () {
    expect(CallPresenceSounds.isStreamEntry("SABC"), isTrue);
    expect(CallPresenceSounds.isStreamEntry("ABC"), isFalse);
    expect(CallPresenceSounds.isStreamEntry(null), isFalse);
    expect(
        CallPresenceSounds.shouldPlayJoin(
            member("@a:x", "A2"), [member("@a:x", "SX")]),
        isTrue);
    expect(
        CallPresenceSounds.shouldPlayJoin(member("@a:x", "A2"), [],
            leavePending: true),
        isFalse);
    expect(
        CallPresenceSounds.isLastConnection(
            member("@a:x", "A1"), [member("@a:x", "SX")]),
        isTrue);
  });

  test("identity device and membership lookup", () {
    final members = [
      (
        sender: "@a:x",
        content: <String, dynamic>{"device_id": "DEV", "membershipID": "m1"},
        stateKey: "_@a:x_DEV_m.call",
      ),
      (sender: "@gone:x", content: <String, dynamic>{}, stateKey: "@gone:x"),
    ];
    expect(LivekitIdentity.deviceId("@a:x:DEV", members), "DEV");
    expect(LivekitIdentity.membership("@a:x:DEV", members), isNotNull);
    expect(LivekitIdentity.membership("@a:x:OTHER", members), isNull);
    expect(LivekitIdentity.membership("@gone:x:G", members), isNull);
    final opaque = LivekitIdentity.hash(["@a:x", "m1"]);
    expect(LivekitIdentity.deviceId(opaque, members), "DEV");
    expect(LivekitIdentity.membership("nobody", members), isNull);
  });
}
