import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:commet/main.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Vommet: the microphone under push to talk. LiveKit normally stops the
/// microphone on mute and restarts it on unmute, which clips the start of
/// every sentence; with push to talk the microphone is published once, muted,
/// and only the track is muted and unmuted, the capture stays open (the
/// system's "microphone in use" light stays on for the call).
extension PushToTalkMicrophone on MatrixLivekitVoipSession {
  /// Publishes still landing, so a press meanwhile waits for the track
  /// instead of publishing a second one.
  static final Map<lk.LocalParticipant, Future<void>> _publishing = {};

  /// The room's microphone options, keeping the capture open while push to
  /// talk is on.
  static lk.AudioCaptureOptions captureOptions(lk.Room room) =>
      room.roomOptions.defaultAudioCaptureOptions
          .copyWith(stopAudioCaptureOnMute: !preferences.voipPushToTalk.value);

  /// Publishes the microphone muted, if it isn't published yet, so the first
  /// press of the push to talk key sends at once.
  Future<void> preparePushToTalk() async {
    final participant = livekitRoom.localParticipant;
    if (participant == null) return;
    await publishMuted(participant, captureOptions(livekitRoom));
  }

  /// Opens or closes the microphone for push to talk (capture kept open).
  Future<void> setPushToTalkMicrophone(bool off) async {
    final participant = livekitRoom.localParticipant;
    if (participant == null) return;
    await _publishing[participant];
    await participant.setMicrophoneEnabled(!off,
        audioCaptureOptions: captureOptions(livekitRoom));
  }

  /// Publishes a microphone track that sends silence until it's unmuted
  /// (nothing if one is published or being published).
  static Future<void> publishMuted(
      lk.LocalParticipant participant, lk.AudioCaptureOptions options) {
    final pending = _publishing[participant];
    if (pending != null) return pending;
    if (participant.getTrackPublicationBySource(lk.TrackSource.microphone) !=
        null) {
      return Future.value();
    }
    final future = () async {
      final track = await lk.LocalAudioTrack.create(options);
      // Silent from the start, before the publish lands.
      track.mediaStreamTrack.enabled = false;
      await participant.publishAudioTrack(track);
      await track.mute(stopOnMute: false);
    }();
    _publishing[participant] = future;
    return future.whenComplete(() => _publishing.remove(participant));
  }
}
