import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/utils/hang_up_on_quit.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements VoipSession {
  _FakeSession(this.state, {this.hangUp, Client? client}) : _client = client;

  final Client? _client;

  @override
  Client get client => _client!;

  @override
  VoipState state;

  final Future<void> Function()? hangUp;
  int hangUps = 0;
  int declines = 0;

  @override
  Future<void> declineCall() async {
    declines++;
    state = VoipState.ended;
  }

  @override
  Future<void> hangUpCall() async {
    hangUps++;
    await hangUp?.call();
    state = VoipState.ended;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
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

  test('logout hangs up only the calls of the account logging out', () async {
    final leaving = _FakeClient();
    final staying = _FakeClient();
    final ours = _FakeSession(VoipState.connected, client: leaving);
    final theirs = _FakeSession(VoipState.connected, client: staying);

    final forced = <VoipSession>[];

    await hangUpCallsForLogout([ours, theirs], leaving, forceEnd: forced.add);

    expect(ours.hangUps, 1);
    expect(ours.state, VoipState.ended);
    expect(theirs.hangUps, 0);
    expect(forced, isEmpty);
  });

  test('logout declines ringing calls of the account', () async {
    final leaving = _FakeClient();
    final ringing = _FakeSession(VoipState.incoming, client: leaving);
    final forced = <VoipSession>[];

    await hangUpCallsForLogout([ringing], leaving, forceEnd: forced.add);

    expect(ringing.declines, 1);
    expect(ringing.hangUps, 0);
    expect(forced, isEmpty);
  });

  test('logout ends locally the calls whose hang up fails or hangs', () async {
    final leaving = _FakeClient();
    final failing = _FakeSession(VoipState.connected,
        client: leaving, hangUp: () async => throw Exception("401"));
    final stuck = _FakeSession(VoipState.connected,
        client: leaving, hangUp: () => Completer<void>().future);
    final fine = _FakeSession(VoipState.connected, client: leaving);
    final forced = <VoipSession>[];

    await hangUpCallsForLogout([failing, stuck, fine], leaving,
        forceEnd: forced.add, timeout: const Duration(milliseconds: 100));

    expect(forced, unorderedEquals([failing, stuck]));
  });
}
