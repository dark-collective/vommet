import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/debug/log.dart';

/// Vommet issue 285: hangs up every call we're in before the app quits.
///
/// Quitting during a call used to leave our `m.call.member` state behind, so
/// everyone kept seeing us in the call until it expired (hours later on
/// homeservers without MSC4140 delayed events). Hanging up sends the empty
/// membership and leaves LiveKit; this waits at most [timeout] for it so a
/// slow homeserver can't hold up quitting. Ringing calls are left alone.
Future<void> hangUpCallsForQuit(
  Iterable<VoipSession> sessions, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final live = sessions
      .where((s) => s.state != VoipState.ended && s.state != VoipState.incoming)
      .toList();
  if (live.isEmpty) return;

  Log.i("Quitting: hanging up ${live.length} call(s) first");
  Future<void> hangUp(VoipSession session) async {
    try {
      await session.hangUpCall();
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to hang up a call before quitting");
    }
  }

  await Future.wait(live.map(hangUp)).timeout(timeout, onTimeout: () {
    Log.w("Quitting: calls not hung up after ${timeout.inSeconds} s, "
        "quitting anyway");
    return const [];
  });
}
