import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/utils/hang_up_on_quit.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements VoipSession {
  _FakeSession(this.state, {this.hangUp});

  @override
  VoipState state;

  final Future<void> Function()? hangUp;
  int hangUps = 0;

  @override
  Future<void> hangUpCall() async {
    hangUps++;
    await hangUp?.call();
    state = VoipState.ended;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('hangs up the calls we are in, not ringing or ended ones', () async {
    final connected = _FakeSession(VoipState.connected);
    final connecting = _FakeSession(VoipState.connecting);
    final ringing = _FakeSession(VoipState.incoming);
    final ended = _FakeSession(VoipState.ended);

    await hangUpCallsForQuit([connected, connecting, ringing, ended]);

    expect(connected.hangUps, 1);
    expect(connecting.hangUps, 1);
    expect(ringing.hangUps, 0);
    expect(ended.hangUps, 0);
  });

  test('a failing hang up does not stop the others or the quit', () async {
    final failing = _FakeSession(VoipState.connected,
        hangUp: () async => throw Exception("homeserver down"));
    final other = _FakeSession(VoipState.connected);

    await hangUpCallsForQuit([failing, other]);

    expect(other.hangUps, 1);
  });

  test('a slow hang up only holds quitting up to the timeout', () async {
    final slow = _FakeSession(VoipState.connected,
        hangUp: () => Future.delayed(const Duration(seconds: 2)));
    final clock = Stopwatch()..start();

    await hangUpCallsForQuit([slow],
        timeout: const Duration(milliseconds: 100));

    expect(slow.hangUps, 1);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
  });
}
