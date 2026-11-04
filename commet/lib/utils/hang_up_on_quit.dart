import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/debug/log.dart';

/// Vommet issue 285: hangs up every call we're in before the app quits.
///
/// Quitting during a call used to leave our `m.call.member` state behind, so
/// everyone kept seeing us in the call until it expired (hours later on
/// homeservers without MSC4140 delayed events). Hanging up sends the empty
/// membership and leaves LiveKit; this waits at most [timeout] for it so a
/// slow homeserver can't hold up quitting. Ringing calls are left alone.
/// [reason] only labels the log lines.
Future<void> hangUpCallsForQuit(
  Iterable<VoipSession> sessions, {
  Duration timeout = const Duration(seconds: 4),
  String reason = "Quitting",
}) async {
  final live = sessions
      .where((s) => s.state != VoipState.ended && s.state != VoipState.incoming)
      .toList();
  await _endCalls(live, (s) => s.hangUpCall(), timeout, reason);
}

Future<void> _endCalls(
  List<VoipSession> sessions,
  Future<void> Function(VoipSession) end,
  Duration timeout,
  String reason,
) async {
  if (sessions.isEmpty) return;

  Log.i("$reason: ending ${sessions.length} call(s) first");
  Future<void> endOne(VoipSession session) async {
    try {
      await end(session);
    } catch (e, s) {
      Log.onError(e, s, content: "$reason: failed to end a call");
    }
  }

  await Future.wait(sessions.map(endOne)).timeout(timeout, onTimeout: () {
    Log.w("$reason: calls not ended after ${timeout.inSeconds} s, "
        "going on anyway");
    return const [];
  });
}

/// Vommet issue 985: logging out during a call left the call running, camera
/// and microphone on, with nothing left in the app to hang up. Ends the calls
/// of the account being logged out before its session goes: hangs up the
/// calls we're in and declines ringing ones. Unlike quitting, the app keeps
/// running, so any call still not ended after [timeout] (slow homeserver, or
/// the hang up failed) is handed to [forceEnd] to be torn down locally.
Future<void> hangUpCallsForLogout(
  Iterable<VoipSession> sessions,
  Client client, {
  required void Function(VoipSession) forceEnd,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final ours = sessions
      .where((s) => s.client == client && s.state != VoipState.ended)
      .toList();
  await _endCalls(
      ours,
      (s) => s.state == VoipState.incoming ? s.declineCall() : s.hangUpCall(),
      timeout,
      "Logging out");

  for (final session in ours.where((s) => s.state != VoipState.ended)) {
    Log.w("Logging out: ending a call locally");
    try {
      forceEnd(session);
    } catch (e, s) {
      Log.onError(e, s, content: "Logging out: failed to end a call locally");
    }
  }
}
