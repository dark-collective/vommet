import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/utils/android_call_task.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements VoipSession {
  _FakeSession(this.state);

  @override
  VoipState state;

  int hangUps = 0;

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
  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(AndroidCallTask.channel, (call) async {
      calls.add(call.method);
      return true;
    });
  });
  tearDown(
      () => messenger.setMockMethodCallHandler(AndroidCallTask.channel, null));

  test('the service runs while there is a call', () async {
    final sessions = NotifyingList<VoipSession>.empty(growable: true);
    AndroidCallTask.attach(sessions, android: true);

    final call = _FakeSession(VoipState.connected);
    sessions.add(call);
    await pumpEventQueue();
    sessions.add(_FakeSession(VoipState.incoming));
    await pumpEventQueue();
    expect(calls, ["start"]);

    sessions.clear();
    await pumpEventQueue();
    expect(calls, ["start", "stop"]);
  });

  test('swiping the app away hangs up', () async {
    final sessions = NotifyingList<VoipSession>.empty(growable: true);
    AndroidCallTask.attach(sessions, android: true);
    final call = _FakeSession(VoipState.connected);
    sessions.add(call);

    await messenger.handlePlatformMessage(
        AndroidCallTask.channel.name,
        AndroidCallTask.channel.codec
            .encodeMethodCall(const MethodCall("taskRemoved")),
        (_) {});

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
