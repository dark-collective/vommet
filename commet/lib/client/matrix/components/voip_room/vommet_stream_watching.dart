import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Vommet: [VoipStreamWatching] for LiveKit calls (experiment
/// `vommet_experiment_stream_watching`).
///
/// The room still subscribes to everything automatically; screen shares you
/// don't watch are then held back per publication:
/// * video with a low simulcast layer: kept on that layer, for the preview;
/// * video without one: disabled, so the server stops sending it;
/// * screen-share audio: unsubscribed (also while you muted it).
/// It re-applies whenever the call's streams change (a share starts, a
/// track is subscribed, a stream arrives from another SFU); every step is
/// a no-op when the publication is already as wanted.
class LivekitStreamWatching implements VoipStreamWatching {
  LivekitStreamWatching._(this._session) {
    _sub = _session.onStateChanged.listen((_) => _applyAll());
    _applyAll();
  }

  /// The experiment's switch. Read when a call starts.
  static final BoolPreference experiment =
      BoolPreference("vommet_experiment_stream_watching", defaultValue: false);

  /// Starts stream watching for a new LiveKit call, when the experiment is
  /// on. The one hook in the session's constructor.
  static void attach(VoipSession session) {
    if (!experiment.value) return;
    VoipStreamWatching.register(session, LivekitStreamWatching._(session));
  }

  final VoipSession _session;
  StreamSubscription? _sub;

  /// Participants (LiveKit identities) whose screen share you watch.
  final Set<String> _watchedSharers = {};

  /// Participants whose screen-share audio you muted in this call.
  final Set<String> _mutedSharers = {};

  /// Subscription changes asked for and not seen yet, by publication, so
  /// they aren't sent again on every stream change.
  final Map<String, bool> _pendingSubscribe = {};

  static bool _isShare(VoipStream stream) =>
      stream.type == VoipStreamType.screenshare ||
      stream.type == VoipStreamType.screenshareAudio;

  @override
  bool isWatching(VoipStream stream) =>
      stream.direction == VoipStreamDirection.outgoing ||
      !_isShare(stream) ||
      _watchedSharers.contains(stream.participantId);

  @override
  bool hasPreview(VoipStream stream) =>
      stream is MatrixLivekitVoipStream && stream.publication.simulcasted;

  @override
  Future<void> setWatching(VoipStream stream, bool watching) async {
    if (watching) {
      _watchedSharers.add(stream.participantId);
    } else {
      _watchedSharers.remove(stream.participantId);
    }
    await _applyAll();
  }

  @override
  bool isStreamAudioMuted(VoipStream stream) =>
      _mutedSharers.contains(stream.participantId);

  @override
  Future<void> setStreamAudioMuted(VoipStream stream, bool muted) async {
    if (muted) {
      _mutedSharers.add(stream.participantId);
    } else {
      _mutedSharers.remove(stream.participantId);
    }
    await _applyAll();
  }

  Future<void> _applyAll() async {
    if (_session.state == VoipState.ended) {
      await _sub?.cancel();
      _sub = null;
      return;
    }
    for (final s
        in _session.streams.whereType<MatrixLivekitVoipStream>().toList()) {
      await _apply(s);
    }
  }

  Future<void> _apply(MatrixLivekitVoipStream stream) async {
    final pub = stream.publication;
    if (pub is! lk.RemoteTrackPublication || !_isShare(stream)) return;
    final watched = _watchedSharers.contains(stream.participantId);
    try {
      if (stream.type == VoipStreamType.screenshare) {
        if (watched || pub.simulcasted) {
          await pub.enable();
          if (pub.subscribed) {
            await pub.setVideoQuality(
                watched ? lk.VideoQuality.HIGH : lk.VideoQuality.LOW);
          }
        } else {
          await pub.disable();
        }
        return;
      }
      final want = watched && !_mutedSharers.contains(stream.participantId);
      if (pub.subscribed == want) {
        _pendingSubscribe.remove(pub.sid);
        return;
      }
      // Unsubscribing only works once the track has arrived; the next
      // stream change (its subscription) brings us back here.
      if (!want && !pub.subscribed) return;
      if (_pendingSubscribe[pub.sid] == want) return;
      _pendingSubscribe[pub.sid] = want;
      if (want) {
        await pub.subscribe();
      } else {
        await pub.unsubscribe();
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not apply stream watching");
    }
  }
}
