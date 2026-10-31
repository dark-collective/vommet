import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';

/// Vommet: Discord-style stream watching. Other people's screen shares
/// aren't played until you choose to watch them; until then the call shows
/// a card for each (with a small live preview when the sharer's app sends a
/// low-quality layer). Implemented by call sessions that can pause a stream
/// (room calls over LiveKit); in others every stream simply plays.
abstract class VoipStreamWatching {
  static final Expando<VoipStreamWatching> _bySession = Expando();

  /// The stream watching of [session], or null when the call doesn't use it
  /// (then every stream plays, as before).
  static VoipStreamWatching? of(VoipSession session) => _bySession[session];

  static void register(VoipSession session, VoipStreamWatching watching) =>
      _bySession[session] = watching;

  /// Whether [stream] is playing for you. Always true for your own streams,
  /// cameras and microphones; for a screen share (and its audio), true once
  /// you chose to watch it.
  bool isWatching(VoipStream stream);

  /// Whether an unwatched screen share can show a small live preview: the
  /// sharer's app sends a low-quality layer (simulcast).
  bool hasPreview(VoipStream stream);

  /// Starts or stops watching the screen share [stream] belongs to. Stopping
  /// pauses its video and drops its audio, so nothing is downloaded. A
  /// sharer who switches what they share stays watched.
  Future<void> setWatching(VoipStream stream, bool watching);

  /// Whether the audio of the screen share [stream] belongs to is muted for
  /// you (only for this call; the volume you set is kept). Muted audio isn't
  /// downloaded either.
  bool isStreamAudioMuted(VoipStream stream);

  Future<void> setStreamAudioMuted(VoipStream stream, bool muted);
}
