import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ClientManager implements ClientManager {
  @override
  StreamController<int> onClientAdded = StreamController.broadcast();
  @override
  StreamController<StalePeerInfo> onClientRemoved =
      StreamController.broadcast();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  Room? getRoom(String identifier) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records whether it was last told its call is deafened.
class _Stream implements VoipStream {
  _Stream([this.calls]);
  final CallManager? calls;
  bool? deafened;
  @override
  Future<void> applyPlaybackVolume() async =>
      deafened = calls?.isDeafenedFor(this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A connected call whose microphone follows setMicrophoneMute, like the
/// real sessions (and reports it through onStateChanged).
class _Call implements VoipSession {
  _Call(this.sessionId);
  @override
  final String sessionId;
  @override
  final Client client = _Client();
  @override
  VoipState state = VoipState.connected;
  @override
  bool isMicrophoneMuted = false;
  @override
  final List<VoipStream> streams = [_Stream()];
  final _changed = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get onStateChanged => _changed.stream;
  @override
  Stream<VoipState> get onConnectionStateChanged => const Stream.empty();
  @override
  Future<void> setMicrophoneMute(bool muted) async {
    isMicrophoneMuted = muted;
    _changed.add(null);
  }

  /// A new stream, as LiveKit adds them: its constructor applies the
  /// volume before it's in the list, then the session reports a change.
  void addStream(_Stream stream) {
    stream.applyPlaybackVolume();
    streams.add(stream);
    _changed.add(null);
  }

  /// The call view muting the session directly.
  void muteFromCallView(bool muted) => setMicrophoneMute(muted);

  @override
  String get roomId => "!$sessionId:example.org";
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late CallManager calls;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.experimentCallCards.set(true);
    calls = CallManager(_ClientManager())..playSounds = false;
  });

  _Call join(String id) {
    final call = _Call(id);
    calls.onClientSessionStarted(call);
    return call;
  }

  test("each call has its own mute", () async {
    final a = join("a"), b = join("b");
    calls.setMutedIn(a, true);
    await pumpEventQueue();
    expect(calls.isMutedIn(a), true);
    expect(a.isMicrophoneMuted, true);
    expect(calls.isMutedIn(b), false);
    expect(b.isMicrophoneMuted, false);
  });

  test("the panel and shortcuts act on the focused call", () async {
    final a = join("a"), b = join("b");
    expect(calls.focusedCall, b, reason: "a call you join comes forward");
    calls.mute();
    await pumpEventQueue();
    expect(calls.isMutedIn(b), true);
    expect(calls.isMutedIn(a), false);
    calls.focusCall(a);
    expect(calls.isMuted, false);
    calls.toggleMute();
    await pumpEventQueue();
    expect(calls.isMutedIn(a), true);
  });

  test("a new call starts the way you left the last one", () async {
    final a = join("a");
    calls.setMutedIn(a, true);
    await pumpEventQueue();
    expect(calls.nextCallMuted, true);
    final b = join("b");
    await pumpEventQueue();
    expect(calls.isMutedIn(b), true);
    expect(b.isMicrophoneMuted, true);
  });

  test("muted before joining: the call starts muted", () async {
    calls.mute();
    expect(calls.nextCallMuted, true);
    final a = join("a");
    await pumpEventQueue();
    expect(a.isMicrophoneMuted, true);
  });

  test("deafen remembers the mute; unmuting undeafens", () async {
    final a = join("a");
    calls.setMutedIn(a, true);
    calls.setDeafenedIn(a, true);
    calls.setDeafenedIn(a, false);
    await pumpEventQueue();
    expect(calls.isMutedIn(a), true, reason: "was muted before deafening");

    calls.setMutedIn(a, false);
    calls.setDeafenedIn(a, true);
    await pumpEventQueue();
    expect(calls.isMutedIn(a), true);
    expect(calls.isDeafenedFor(a.streams.first), true);
    calls.setMutedIn(a, false);
    await pumpEventQueue();
    expect(calls.isDeafenedIn(a), false, reason: "unmute undeafens");
    expect(a.isMicrophoneMuted, false);
  });

  test("deafen is per call too, and doesn't undo itself", () async {
    final a = join("a"), b = join("b");
    calls.setDeafenedIn(a, true);
    await pumpEventQueue();
    expect(calls.isDeafenedIn(a), true);
    expect(calls.isDeafenedFor(a.streams.first), true);
    expect(calls.isDeafenedFor(b.streams.first), false);
    expect(a.isMicrophoneMuted, true);
  });

  test("the call view's own mute is followed for that call only", () async {
    final a = join("a"), b = join("b");
    a.muteFromCallView(true);
    await pumpEventQueue();
    expect(calls.isMutedIn(a), true);
    expect(calls.isMutedIn(b), false);
  });

  test("without the experiment: one state for every call, as before", () async {
    await preferences.experimentCallCards.set(false);
    final a = join("a"), b = join("b");
    calls.mute();
    await pumpEventQueue();
    expect(a.isMicrophoneMuted, true);
    expect(b.isMicrophoneMuted, true);
    calls.setDeafened(true);
    await pumpEventQueue();
    expect(calls.isDeafenedFor(a.streams.first), true);
    expect(calls.isDeafenedFor(b.streams.first), true);
  });

  test("turning the experiment off evens the calls out", () async {
    final a = join("a"), b = join("b");
    calls.setMutedIn(b, true); // b is focused
    await pumpEventQueue();
    await preferences.experimentCallCards.set(false);
    calls.syncAudioMode();
    await pumpEventQueue();
    expect(calls.isMutedIn(a), true);
    expect(a.isMicrophoneMuted, true);
  });

  test("a new stream follows its own call's deafen, not the focused one's",
      () async {
    final a = join("a"), b = join("b"); // b is focused
    calls.setDeafenedIn(b, true);
    await pumpEventQueue();
    final newcomer = _Stream(calls);
    a.addStream(newcomer);
    await pumpEventQueue();
    expect(newcomer.deafened, false, reason: "a isn't deafened");

    final other = _Stream(calls);
    b.addStream(other);
    await pumpEventQueue();
    expect(other.deafened, true);
  });

  test("a stream replacing another between events is still re-applied",
      () async {
    final a = join("a"), b = join("b");
    calls.setDeafenedIn(b, true);
    await pumpEventQueue();
    a.streams.removeLast(); // one leaves...
    final newcomer = _Stream(calls);
    a.addStream(newcomer); // ...one joins: same count as before
    await pumpEventQueue();
    expect(newcomer.deafened, false);
  });

  test("unmuting while a call connects still opens the microphone", () async {
    calls.mute(); // the join opens no microphone
    final c = _Call("c")..isMicrophoneMuted = true;
    calls.unmute(); // changed your mind while it connects
    calls.onClientSessionStarted(c);
    await pumpEventQueue();
    expect(c.isMicrophoneMuted, false);
    expect(calls.isMutedIn(c), false);
  });

  test("a call that ends hands the focus back", () async {
    final a = join("a"), b = join("b");
    expect(calls.focusedCall, b);
    b.state = VoipState.ended;
    calls.onSessionEnded(b);
    expect(calls.focusedCall, a);
  });
}
