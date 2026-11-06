import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Vommet: the sounds for what happens in a LiveKit call that the session
/// itself doesn't announce: the connection dropping, and screen shares
/// starting and stopping (yours and everyone else's). Returns the listener
/// so the caller can dispose it when the call ends.
lk.EventsListener<lk.RoomEvent> attachLivekitCallSounds(
    MatrixLivekitVoipSession session, void Function(SoundEvent) play) {
  final listener = session.livekitRoom.createListener();

  void screenShare(lk.TrackPublication publication, bool started) {
    if (publication.source != lk.TrackSource.screenShareVideo) return;
    play(started ? SoundEvent.screenShareStart : SoundEvent.screenShareStop);
  }

  listener.on<lk.RoomReconnectingEvent>((_) => play(SoundEvent.connectionLost));
  listener.on<lk.RoomDisconnectedEvent>((event) {
    if (event.reason == lk.DisconnectReason.clientInitiated) return;
    play(SoundEvent.connectionLost);
  });
  listener.on<lk.TrackPublishedEvent>((e) => screenShare(e.publication, true));
  listener
      .on<lk.LocalTrackPublishedEvent>((e) => screenShare(e.publication, true));
  listener
      .on<lk.TrackUnpublishedEvent>((e) => screenShare(e.publication, false));
  listener.on<lk.LocalTrackUnpublishedEvent>(
      (e) => screenShare(e.publication, false));
  return listener;
}
