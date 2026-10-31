import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/utils/android_call_task.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements VoipSession {
  _FakeSession(this.state, [this.roomName = "Room"]);

  @override
  VoipState state;

  @override
  final String roomName;

  int hangUps = 0;

  final _states = StreamController<VoipState>.broadcast();

  @override
  Stream<VoipState> get onConnectionStateChanged => _states.stream;

  void moveTo(VoipState next) {
    state = next;
    _states.add(next);
  }

  @override
  Future<void> hangUpCall() async {
    hangUps++;
    state = VoipState.ended;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late List<Object?> arguments;
  setUp(() {
    calls = [];
    arguments = [];
    messenger.setMockMethodCallHandler(AndroidCallTask.channel, (call) async {
      calls.add(call.method);
      arguments.add(call.arguments);
      return true;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(AndroidCallTask.channel, null),
  );

  test('the service runs while there is a call', () async {
    final sessions = NotifyingList<VoipSession>.empty(growable: true);
    AndroidCallTask.attach(sessions, android: true);

    final call = _FakeSession(VoipState.connected, "Alice");
    sessions.add(call);
    await pumpEventQueue();
    sessions.add(_FakeSession(VoipState.incoming, "Bob"));
    await pumpEventQueue();
    expect(calls, ["start"]);
    expect((arguments.single as Map)["roomName"], "Alice");
    expect((arguments.single as Map)["title"], "Call in progress");

    sessions.clear();
    await pumpEventQueue();
    expect(calls, ["start", "stop"]);
  });

  test('a ringing call starts the service only once answered', () async {
    final sessions = NotifyingList<VoipSession>.empty(growable: true);
    AndroidCallTask.attach(sessions, android: true);

    final call = _FakeSession(VoipState.incoming, "Alice");
    sessions.add(call);
    await pumpEventQueue();
    expect(calls, isEmpty);

    call.moveTo(VoipState.connecting);
    await pumpEventQueue();
    expect(calls, ["start"]);

    call.moveTo(VoipState.ended);
    await pumpEventQueue();
    expect(calls, ["start", "stop"]);
  });

  test('start is sent again when the call connects', () async {
    // A first start refused in the background, or made before the microphone
    // permission, is retried so the service gets promoted to the foreground.
    messenger.setMockMethodCallHandler(AndroidCallTask.channel, (call) async {
      calls.add(call.method);
      return false;
    });
    final sessions = NotifyingList<VoipSession>.empty(growable: true);
    AndroidCallTask.attach(sessions, android: true);

    final call = _FakeSession(VoipState.outgoing);
    sessions.add(call);
    await pumpEventQueue();
    expect(calls, ["start"]);

    call.moveTo(VoipState.connected);
    await pumpEventQueue();
    expect(calls, ["start", "start"]);
  });

  test('swiping the app away hangs up', () async {
    final sessions = NotifyingList<VoipSession>.empty(growable: true);
    AndroidCallTask.attach(sessions, android: true);
    final call = _FakeSession(VoipState.connected);
    sessions.add(call);

    await messenger.handlePlatformMessage(
      AndroidCallTask.channel.name,
      AndroidCallTask.channel.codec.encodeMethodCall(
        const MethodCall("taskRemoved"),
      ),
      (_) {},
    );

    expect(call.hangUps, 1);
  });

  test('the notification hang up action hangs up', () async {
    final sessions = NotifyingList<VoipSession>.empty(growable: true);
    AndroidCallTask.attach(sessions, android: true);
    final call = _FakeSession(VoipState.connected);
    sessions.add(call);

    await messenger.handlePlatformMessage(
      AndroidCallTask.channel.name,
      AndroidCallTask.channel.codec.encodeMethodCall(
        const MethodCall("hangUp"),
      ),
      (_) {},
    );

    expect(call.hangUps, 1);
  });

  test('does nothing off Android', () async {
    final sessions = NotifyingList<VoipSession>.empty(growable: true);
    AndroidCallTask.attach(sessions, android: false);
    sessions.add(_FakeSession(VoipState.connected));
    await pumpEventQueue();
    expect(calls, isEmpty);
  });
}
