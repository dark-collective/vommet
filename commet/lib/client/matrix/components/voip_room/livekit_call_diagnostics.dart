import 'dart:async';

import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/debug/log.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Vommet: call diagnostics for the log page (Settings › About › Logs).
///
/// A remote screen share sometimes stays a spinner while its audio plays: the
/// tile exists but never gets a video track. These lines show which step is
/// missing — published, subscribed (or why not), muted, stream state — and a
/// check every 15 s reports a tile whose track differs from the room's.
/// Track ids and sources only; no names beyond the participant identity.
class LivekitCallDiagnostics {
  static void attach(lk.Room room, List<VoipStream> Function() streams) {
    final listener = room.createListener();
    final lastAudit = <String, String>{};

    String tile(String? sid) {
      final s = streams().whereType<MatrixLivekitVoipStream>();
      final match = s.where((t) => t.publication.sid == sid);
      if (match.isEmpty) return "no tile";
      final t = match.first;
      return "tile track=${t.publication.track != null}";
    }

    String pub(lk.TrackPublication p) =>
        "sid=${p.sid} source=${p.source.name} kind=${p.kind.name} "
        "muted=${p.muted} subscribed=${p.subscribed}";

    void log(String what, lk.TrackPublication p, String identity) =>
        Log.i("Call diag: $what ${pub(p)} from=$identity ${tile(p.sid)}");

    listener.on<lk.TrackPublishedEvent>(
        (e) => log("published", e.publication, e.participant.identity));
    listener.on<lk.TrackUnpublishedEvent>(
        (e) => log("unpublished", e.publication, e.participant.identity));
    listener.on<lk.TrackSubscribedEvent>(
        (e) => log("subscribed", e.publication, e.participant.identity));
    listener.on<lk.TrackUnsubscribedEvent>(
        (e) => log("unsubscribed", e.publication, e.participant.identity));
    listener.on<lk.TrackMutedEvent>(
        (e) => log("muted", e.publication, e.participant.identity));
    listener.on<lk.TrackUnmutedEvent>(
        (e) => log("unmuted", e.publication, e.participant.identity));
    listener.on<lk.TrackStreamStateUpdatedEvent>((e) => log(
        "stream ${e.streamState.name}", e.publication, e.participant.identity));
    listener.on<lk.TrackSubscriptionExceptionEvent>((e) => Log.w(
        "Call diag: subscription FAILED sid=${e.sid} reason=${e.reason.name} "
        "from=${e.participant?.identity}"));

    // Remote video tiles vs the room, every 15 s; logs only changes.
    final timer = Timer.periodic(const Duration(seconds: 15), (_) {
      for (final p in room.remoteParticipants.values) {
        for (final pub in p.trackPublications.values) {
          if (pub.kind != lk.TrackType.VIDEO) continue;
          final state = "${pub.subscriptionState.name} "
              "stream=${pub.streamState.name} enabled=${pub.enabled} "
              "${tile(pub.sid)}";
          if (lastAudit[pub.sid] == state) continue;
          lastAudit[pub.sid] = state;
          final stale = streams()
              .whereType<MatrixLivekitVoipStream>()
              .where((t) =>
                  t.publication.sid == pub.sid &&
                  !identical(t.publication, pub))
              .isNotEmpty;
          Log.i("Call diag: audit sid=${pub.sid} source=${pub.source.name} "
              "from=${p.identity} $state"
              "${stale ? " STALE-PUBLICATION (tile holds an older object)" : ""}");
        }
      }
    });

    listener.on<lk.RoomDisconnectedEvent>((_) {
      timer.cancel();
      listener.dispose();
    });
  }
}
