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

/// A connected call whose microphone follows setMicrophoneMute and reports
/// it asynchronously, like MatrixLivekitVoipSession's onStateChanged.
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
  final List<VoipStream> streams = [];
  final _changed = StreamController<void>.broadcast();
  @override
  Stream<void> get onStateChanged => _changed.stream;
  @override
  Stream<VoipState> get onConnectionStateChanged => const Stream.empty();
  @override
  Future<void> setMicrophoneMute(bool muted) async {
    isMicrophoneMuted = muted;
    _changed.add(null);
  }

  @override
  String get roomId => "!$sessionId:example.org";
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late CallManager calls;
  const key = "key", button = "button";

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.useVoipOverlay.set(false);
    await preferences.voipPushToTalkReleaseDelay.set(0);
    calls = CallManager(_ClientManager())..playSounds = false;
    await preferences.voipPushToTalk.set(true);
    await pumpEventQueue();
  });

  _Call join(String id) {
    final call = _Call(id);
    calls.onClientSessionStarted(call);
    return call;
  }

  test("the microphone only sends while held", () async {
    final call = join("a");
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, true);
    expect(calls.isMutedIn(call), false, reason: "not muted, just not held");

    calls.pushToTalk.press(key);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, false);
    expect(calls.isTalkingIn(call), true);

    calls.pushToTalk.release(key);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, true);
    expect(calls.isMutedIn(call), false);
  });

  test("the release delay keeps sending a moment", () async {
    await preferences.voipPushToTalkReleaseDelay.set(0.1);
    final call = join("a");
    calls.pushToTalk.press(key);
    calls.pushToTalk.release(key);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, false);
    await Future.delayed(const Duration(milliseconds: 150));
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, true);
  });

  test("pressing again within the delay keeps sending", () async {
    await preferences.voipPushToTalkReleaseDelay.set(0.1);
    final call = join("a");
    calls.pushToTalk.press(key);
    calls.pushToTalk.release(key);
    await Future.delayed(const Duration(milliseconds: 50));
    calls.pushToTalk.press(key);
    await Future.delayed(const Duration(milliseconds: 100));
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, false);
  });

  test("the key and the talk button hold separately", () async {
    final call = join("a");
    calls.pushToTalk.press(key);
    calls.pushToTalk.press(button);
    calls.pushToTalk.release(key);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, false);
    calls.pushToTalk.release(button);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, true);
  });

  test("mute wins over push to talk", () async {
    final call = join("a");
    calls.setMutedIn(call, true);
    calls.pushToTalk.press(key);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, true);
    expect(calls.isTalkingIn(call), false);

    calls.setMutedIn(call, false);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, false, reason: "the key is still held");
  });

  test("a mic button that unmutes the session doesn't bypass it", () async {
    final call = join("a");
    await pumpEventQueue();
    await call.setMicrophoneMute(false);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, true);
    expect(calls.isMutedIn(call), false);
  });

  test("a mic button that mutes the session mutes", () async {
    final call = join("a");
    calls.pushToTalk.press(key);
    await pumpEventQueue();
    await call.setMicrophoneMute(true);
    await pumpEventQueue();
    expect(calls.isMutedIn(call), true);
    expect(call.isMicrophoneMuted, true);
  });

  test("turning push to talk off opens the microphone again", () async {
    final call = join("a");
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, true);
    await preferences.voipPushToTalk.set(false);
    await pumpEventQueue();
    expect(call.isMicrophoneMuted, false);
    calls.pushToTalk.press(key);
    expect(calls.pushToTalk.talking, false,
        reason: "presses do nothing in voice activity mode");
  });
}
