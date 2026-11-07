// Vommet issue 799: accepting an invite could load forever. The SDK's
// network timeout only covers a stalled response body, not a server that
// never answers, and a federated /join can be held open indefinitely (or
// answer while sync never shows the join). Accepting now gives up after a
// while with an error the invite's buttons already know how to show.
import 'dart:async';

import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';

/// The join wasn't confirmed in time: the /join request didn't answer, or
/// the next syncs didn't show the room as joined.
class JoinNotConfirmed implements Exception {
  const JoinNotConfirmed();

  @override
  String toString() => inviteJoinNotConfirmed;
}

/// How long the /join request may take.
const joinRequestLimit = Duration(seconds: 60);

/// How long, after /join answered, sync may take to show the room joined.
const joinConfirmLimit = Duration(seconds: 30);

/// Runs [request], then waits until [joined] holds, re-checking it after
/// every event on [syncs]. Throws [JoinNotConfirmed] when either step
/// takes longer than its limit; errors from [request] pass through.
Future<void> joinWithConfirmation({
  required Future<void> Function() request,
  required bool Function() joined,
  required Stream<Object?> syncs,
  Duration requestLimit = joinRequestLimit,
  Duration confirmLimit = joinConfirmLimit,
}) async {
  try {
    await request().timeout(requestLimit);
  } on TimeoutException {
    throw const JoinNotConfirmed();
  }
  if (joined()) return;
  try {
    await syncs.firstWhere((_) => joined()).timeout(confirmLimit);
  } on TimeoutException {
    if (!joined()) throw const JoinNotConfirmed();
  } on StateError {
    // The sync stream closed (logged out): nothing more to wait for.
    if (!joined()) throw const JoinNotConfirmed();
  }
}
