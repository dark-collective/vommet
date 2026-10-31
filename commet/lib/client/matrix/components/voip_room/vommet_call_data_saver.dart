import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Vommet issue 776: "Use less data for calls" in a LiveKit call.
///
/// Receives the lowest layer of other people's cameras while it is in
/// effect (screen shares at most the middle one; with stream watching on,
/// that decides the screen shares). When the network changes mid-call, the
/// voice bitrate changes at once, a running camera restarts with the new
/// size, and a stopped camera starts with it next time; a screen share
/// keeps its settings until the next one.
class LivekitCallDataSaver {
  LivekitCallDataSaver._(this._session) {
    _sub = _session.onStateChanged.listen((_) => unawaited(_applyReceive()));
    CallDataSaver.active.addListener(_onActiveChanged);
    unawaited(_applyReceive());
  }

  /// The one hook in the session's constructor.
  static void attach(MatrixLivekitVoipSession session) =>
      LivekitCallDataSaver._(session);

  final MatrixLivekitVoipSession _session;
  StreamSubscription? _sub;

  bool _ended() {
    if (_session.state != VoipState.ended) return false;
    unawaited(_sub?.cancel());
    _sub = null;
    CallDataSaver.active.removeListener(_onActiveChanged);
    return true;
  }

  Future<void> _applyReceive() async {
    if (_ended()) return;
    final watching = VoipStreamWatching.of(_session) != null;
    for (final stream
        in _session.streams.whereType<MatrixLivekitVoipStream>().toList()) {
      final pub = stream.publication;
      if (pub is! lk.RemoteTrackPublication || !pub.subscribed) continue;
      final share = stream.type == VoipStreamType.screenshare;
      if (stream.type != VoipStreamType.video && !(share && !watching))
        continue;
      try {
        await pub
            .setVideoQuality(CallDataSaver.receiveQuality(screenShare: share));
      } catch (e, s) {
        Log.onError(e, s, content: "Could not set the received video layer");
      }
    }
  }

  void _onActiveChanged() {
    if (_ended()) return;
    unawaited(_applySend());
    // Re-applies receiving here and in stream watching.
    _session.notifyStreamsChanged();
  }

  Future<void> _applySend() async {
    final local = _session.livekitRoom.localParticipant;
    if (local == null) return;
    for (final pub in local.audioTrackPublications.toList()) {
      final track = pub.track;
      if (pub.source == lk.TrackSource.microphone && track != null) {
        await CallDataSaver.applyVoiceBitrate(track);
      }
    }
    final camera = local.getTrackPublicationBySource(lk.TrackSource.camera);
    if (camera == null) return;
    final running = !camera.muted;
    try {
      // A camera publication keeps its size, so drop it: a running camera
      // starts again at once, a stopped one at its next start.
      await local.removePublishedTrack(camera.sid);
      if (running) {
        await local.setCameraEnabled(true,
            cameraCaptureOptions: CallDataSaver.cameraCaptureOptions());
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not restart the camera");
    }
    _session.notifyStreamsChanged();
  }
}
